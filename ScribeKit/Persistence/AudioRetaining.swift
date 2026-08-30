//
//  AudioRetaining.swift
//  ScribeKit
//

import Foundation

/// Writes a meeting's captured audio to a durable file, when the user asked
/// for one.
///
/// The protocol is the whole boundary between a running meeting and an audio
/// file: a coordinator opens a session, capture delivers buffers straight to
/// it, and the coordinator closes the session. Containers, codecs and
/// `AVFoundation` stay below this line, so a whole meeting's retention
/// lifecycle is testable without a disk, an encoder or capture permission.
///
/// Appending is ``AudioSampleConsuming/consume(_:)`` rather than a method of
/// its own, because that is exactly what a retainer is: one more consumer on
/// the capture system's delivery queue, bound by the same obligation to return
/// quickly and to hold nothing. Buffers are written where they arrive; there is
/// no queue between capture and the file, so there is no backlog to bound and
/// nothing to evict, and audio memory stays flat however long a meeting runs.
///
/// Because `consume` cannot throw, a failed write is reported through
/// ``failures``. The first failure closes the session's file and stops the
/// retainer accepting anything more: audio that was not written is never
/// papered over by carrying on as though the recording were whole.
///
/// Retention never deletes. A file that failed part-way through is closed and
/// left where it is, because a partial recording of a meeting is the user's and
/// cannot be captured again.
nonisolated protocol AudioRetaining: AudioSampleConsuming {

    /// Retention failures reported after a session started successfully.
    ///
    /// A write happening on the capture queue cannot throw to anyone, so the
    /// failure is delivered here instead. At most one is reported per session:
    /// the retainer stops writing after the first.
    var failures: AsyncStream<AudioRetentionError> { get }

    /// Opens the session's audio file.
    ///
    /// - Parameters:
    ///   - mode: What the user chose to keep. ``AudioRetentionMode/none``
    ///     opens nothing and creates nothing.
    ///   - layout: Where the session's artifacts live.
    ///   - format: The format capture was asked for, which fixes the file's
    ///     own format. An audio file's format is decided when its container is
    ///     created and cannot change afterwards, so audio arriving in another
    ///     sample rate or channel count is refused rather than resampled behind
    ///     the user's back.
    /// - Returns: The file that was created, or `nil` when the mode keeps no
    ///   audio.
    /// - Throws: ``AudioRetentionError`` when a session is already open or the
    ///   file cannot be created.
    func startSession(
        mode: AudioRetentionMode,
        layout: SessionArtifactLayout,
        format: CapturedAudioFormat
    ) throws -> URL?

    /// Closes the session's audio file.
    ///
    /// A caller may only report a meeting as complete once this has returned
    /// without throwing. The audio file is a durable artifact of the meeting,
    /// so a session record claiming completion must never be ahead of it.
    ///
    /// - Throws: ``AudioRetentionError`` when no session is open, when a write
    ///   failed earlier in the session, or when the file could not be closed
    ///   and read back.
    func finishSession() throws

    /// Closes the session's audio file without reporting whether that
    /// succeeded, for teardown paths that are already handling a failure.
    ///
    /// The file itself is left on disk either way.
    func cancelSession()
}

/// A reason retained audio could not be started, continued or finished.
///
/// ``underlying`` keeps the originating system error for local diagnostics and
/// is deliberately not part of the reason, so callers and tests match on
/// ScribeKit's own vocabulary rather than on an `AVFoundation` status code.
struct AudioRetentionError: Error {

    /// What went wrong, in ScribeKit's own terms rather than the system's.
    enum Reason: Equatable, Sendable {
        /// A session was started while one was already open.
        case sessionAlreadyInProgress

        /// A close or write arrived with no session open.
        case noSessionInProgress

        /// The audio file could not be created in the session directory.
        case cannotCreateAudioFile

        /// Audio arrived in a format the open file cannot hold.
        case unsupportedCapturedFormat

        /// Captured frames could not be prepared for the file.
        case audioConversionFailed

        /// Writing captured audio to the file failed.
        case audioWriteFailed

        /// The file could not be closed, or could not be read back afterwards.
        case audioFinishFailed
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

extension AudioRetentionError: LocalizedError {
    /// A message for the meeting screen that says plainly what it means for
    /// the recording, without quoting a raw OS error code and without
    /// promising a repair ScribeKit will not attempt.
    var errorDescription: String? {
        switch reason {
        case .sessionAlreadyInProgress:
            "A meeting's audio is already being recorded."
        case .noSessionInProgress:
            "There is no meeting to record audio for."
        case .cannotCreateAudioFile:
            "The audio file could not be created in the meeting folder, so the meeting was not started."
        case .unsupportedCapturedFormat:
            "Audio arrived in a different format from the one this recording was opened for, so it was not written to the audio file."
        case .audioConversionFailed:
            "Captured audio could not be prepared for the audio file."
        case .audioWriteFailed:
            "The audio file could not be written to, so the recording is incomplete. What had already been written was kept."
        case .audioFinishFailed:
            "The audio file could not be completed, so it may not play. It was left in the meeting folder exactly as it is."
        }
    }
}
