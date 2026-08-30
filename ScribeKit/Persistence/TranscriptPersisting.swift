//
//  TranscriptPersisting.swift
//  ScribeKit
//

import Foundation

/// Writes a meeting's finalised transcript to a durable file.
///
/// The protocol is the whole boundary between a running meeting and the
/// filesystem: a coordinator asks for a session, hands over finalised spans
/// and gaps as they happen, and finishes the session. No `FileManager` or
/// `FileHandle` call belongs anywhere above this line, and a test substitutes
/// a double to exercise a meeting without a disk.
///
/// The lifecycle is explicit and singular. A session must be started before
/// anything can be appended to it, and finished before another begins;
/// implementations serialise writes, so a caller never orders them itself.
///
/// Durability contract: once ``appendFinalSegment(_:)`` returns without
/// throwing, the segment has been handed to the filesystem and will not be
/// discarded by ScribeKit. A failure is thrown rather than absorbed, because
/// the only thing worse than losing recognised words is claiming they were
/// saved.
nonisolated protocol TranscriptPersisting: Sendable {

    /// Creates a session's directory and its transcript file, and writes the
    /// transcript header.
    ///
    /// - Parameters:
    ///   - session: The meeting being recorded. Its destination is the folder
    ///     the user chose, and access to it is held for the session's life.
    ///   - localeIdentifier: The BCP-47 locale recognition runs in.
    ///   - startedAt: The wall-clock moment the run's timeline begins;
    ///     segment offsets are measured from it.
    /// - Returns: Where the session's artifacts live.
    /// - Throws: ``TranscriptPersistenceError`` when access is refused or the
    ///   directory or file cannot be created.
    func startSession(
        _ session: MeetingSession,
        localeIdentifier: String,
        startedAt: Date
    ) async throws -> SessionArtifactLayout

    /// Appends one finalised span to the transcript.
    ///
    /// - Parameter segment: A span the recogniser has finalised. A partial
    ///   hypothesis is refused rather than written, because it will be
    ///   restated and would appear twice.
    /// - Throws: ``TranscriptPersistenceError`` when no session is in
    ///   progress, the segment is not finalised, or the write fails.
    func appendFinalSegment(_ segment: TranscriptSegment) async throws

    /// Appends a marker for audio that was never transcribed.
    ///
    /// - Parameter gap: The untranscribed stretch.
    /// - Throws: ``TranscriptPersistenceError`` when no session is in progress
    ///   or the write fails.
    func recordGap(_ gap: TranscriptGap) async throws

    /// Records that the user paused the meeting.
    ///
    /// The session stays open. The marker is a structural remark rather than
    /// speech, and the session record is updated so that a ScribeKit that
    /// stops while a meeting is paused leaves a record saying so.
    ///
    /// - Parameters:
    ///   - date: The wall-clock moment capture stopped.
    ///   - capturedDuration: Seconds of audio the meeting had captured, which
    ///     is where the recording ends and where a resume continues from.
    /// - Throws: ``TranscriptPersistenceError`` when no session is in progress
    ///   or the write fails.
    func recordPause(at date: Date, capturedDuration: Double) async throws

    /// Records that the user resumed the meeting, opening a new stretch in
    /// which media time and wall-clock time run together again.
    ///
    /// - Parameters:
    ///   - date: The wall-clock moment capture started again.
    ///   - capturedDuration: Seconds of audio captured before the pause, which
    ///     is the media offset the resumed audio continues from.
    /// - Throws: ``TranscriptPersistenceError`` when no session is in progress
    ///   or the write fails.
    func recordResume(at date: Date, capturedDuration: Double) async throws

    /// Flushes everything accepted so far, closes the file, records how the
    /// session ended, and releases access to the user's folder.
    ///
    /// A caller may only report a meeting as complete once this has returned
    /// without throwing. The ordering that makes that safe is part of the
    /// contract: a session is never recorded as completed before its
    /// transcript has been flushed and closed successfully, so a record
    /// claiming completion is never ahead of the file it describes.
    ///
    /// - Parameters:
    ///   - endedAt: The wall-clock moment the session finished.
    ///   - outcome: Whether the meeting finished normally or was ended because
    ///     the transcript could not be saved. ``SessionCompletionOutcome/failed``
    ///     writes no closing block, because a meeting that stopped being saved
    ///     has no honest end time to state in the document.
    ///   - capturedDuration: Seconds of audio the meeting captured, which is
    ///     the length of the retained recording and, for a meeting that was
    ///     paused, shorter than the meeting's wall-clock length.
    /// - Throws: ``TranscriptPersistenceError`` when no session is in progress,
    ///   the transcript could not be flushed and closed, or the session record
    ///   could not be updated. Resources are released either way, and a
    ///   session whose record could not be updated is left recorded as
    ///   unfinished rather than falsely as complete.
    func finishSession(
        endedAt: Date,
        outcome: SessionCompletionOutcome,
        capturedDuration: Double
    ) async throws
}

nonisolated extension TranscriptPersisting {
    /// Finishes a session that ended normally.
    ///
    /// - Parameter endedAt: The wall-clock moment the session finished.
    /// - Throws: Whatever ``finishSession(endedAt:outcome:capturedDuration:)``
    ///   throws.
    func finishSession(endedAt: Date) async throws {
        try await finishSession(endedAt: endedAt, outcome: .completed, capturedDuration: 0)
    }

    /// Finishes a session whose captured length is not being stated.
    ///
    /// - Parameters:
    ///   - endedAt: The wall-clock moment the session finished.
    ///   - outcome: How the meeting ended.
    /// - Throws: Whatever ``finishSession(endedAt:outcome:capturedDuration:)``
    ///   throws.
    func finishSession(endedAt: Date, outcome: SessionCompletionOutcome) async throws {
        try await finishSession(endedAt: endedAt, outcome: outcome, capturedDuration: 0)
    }
}

/// A reason durable transcript writing could not start, continue or finish.
///
/// ``underlying`` keeps the originating system error for local diagnostics and
/// is deliberately not part of equality, so callers and tests can match on the
/// reason alone.
struct TranscriptPersistenceError: Error {

    /// What went wrong, in ScribeKit's own terms rather than the system's.
    enum Reason: Equatable, Sendable {
        /// A segment or gap arrived with no session open.
        case noSessionInProgress

        /// A session was started while one was already in progress.
        case sessionAlreadyInProgress

        /// The system refused access to the user's chosen folder.
        case accessDenied

        /// The session directory could not be created.
        case directoryCreationFailed

        /// The transcript file could not be created.
        case transcriptCreationFailed

        /// A partial hypothesis was offered for durable writing.
        case segmentNotFinalized

        /// Appending to the transcript failed.
        case writeFailed

        /// The transcript could not be flushed or closed.
        case flushFailed

        /// The session record that makes a meeting recoverable could not be
        /// written. A meeting does not start without one, and does not finish
        /// as completed without one either.
        case recoveryMetadataFailed
    }

    /// What went wrong.
    let reason: Reason

    /// The system error behind ``reason``, when there was one.
    let underlying: Error?

    /// Creates an error.
    ///
    /// - Parameters:
    ///   - reason: What went wrong.
    ///   - underlying: The originating system error, kept for diagnostics.
    init(_ reason: Reason, underlying: Error? = nil) {
        self.reason = reason
        self.underlying = underlying
    }
}

extension TranscriptPersistenceError: LocalizedError {
    /// A message for the meeting screen that says plainly what it means for
    /// the transcript, without quoting a raw OS error code.
    var errorDescription: String? {
        switch reason {
        case .noSessionInProgress:
            "There is no meeting to save transcript text to."
        case .sessionAlreadyInProgress:
            "A meeting is already being saved."
        case .accessDenied:
            "macOS did not grant ScribeKit access to the save folder, so the transcript could not be created. Choose the folder again."
        case .directoryCreationFailed:
            "The meeting folder could not be created in the save location, so no transcript was started."
        case .transcriptCreationFailed:
            "The transcript file could not be created in the meeting folder."
        case .segmentNotFinalized:
            "Only finalised speech can be written to a transcript."
        case .writeFailed:
            "The transcript could not be written to. Recognised speech is no longer being saved."
        case .flushFailed:
            "The transcript could not be completed. Some recognised speech may not have reached the file."
        case .recoveryMetadataFailed:
            "ScribeKit could not write the session record this meeting needs to be recoverable, so the meeting was not started or was not recorded as finished."
        }
    }
}
