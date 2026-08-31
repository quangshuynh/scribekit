//
//  SessionRecoveryMetadata.swift
//  ScribeKit
//

import Foundation

/// Where a session stands in the lifecycle ScribeKit records on disk.
///
/// The distinction that matters after a relaunch is between a session
/// ScribeKit closed and a session that simply stopped existing. Only
/// ``inProgress`` means the second, which is why it is the only status
/// recovery offers: every other case was written by ScribeKit deliberately,
/// while it was still running.
nonisolated enum SessionRecoveryStatus: String, Codable, Sendable, CaseIterable, Hashable {
    /// The session's transcript is open and being written to. A record left in
    /// this state after ScribeKit exits describes a meeting that never
    /// finished.
    case inProgress

    /// The transcript was flushed and closed successfully and the meeting
    /// ended normally.
    case completed

    /// The meeting ended because the transcript stopped being saved. ScribeKit
    /// was running and told the user at the time, so this is a closed session
    /// rather than a lost one.
    case failed

    /// The meeting ended without anyone stopping it, and its artifacts were
    /// closed with everything that reached them.
    ///
    /// Two paths write it, and they mean the same thing about the files. A
    /// session found unfinished after a relaunch is marked this way once the
    /// user has been shown it, so the same interruption is not reported
    /// forever; and a meeting whose capture stream ended by itself is closed
    /// this way while ScribeKit is still running, because finalising a
    /// transcript successfully does not turn an unexpected end into a
    /// completion. It is distinct from ``failed``, which is about an artifact
    /// that could not be saved rather than about capture stopping.
    case interrupted
}

/// The operational record ScribeKit keeps beside a transcript, written to
/// `.scribekit/session.json` inside the session directory.
///
/// This is bookkeeping, not a second transcript. It holds what is needed to
/// recognise an unfinished meeting and describe it to the user, and nothing
/// that duplicates transcript content: `transcript.md` stays canonical, and a
/// session whose metadata is lost or unreadable still has a usable transcript.
///
/// Nothing here is a runtime object. Stream handles, recognisers, process
/// identifiers, continuations and security-scoped tokens all die with the
/// process that owned them, so persisting one would record a fact that is
/// false the moment it is written.
///
/// The record is versioned from its first release. ``schemaVersion`` is read
/// before anything else is interpreted, so a file written by a later ScribeKit
/// is refused rather than misread as this one.
///
/// ``audioRetention``, ``audioPath``, ``pausedAt`` and ``capturedDuration``
/// were added after version 1 was in use and the version was deliberately not
/// raised. All four are optional and additive:
/// a record written before they existed decodes with them absent, which is the
/// truth about a session that kept no audio, and a build that has never heard
/// of them ignores the extra keys. Raising the version would have made
/// every earlier session unreadable in exchange for nothing.
nonisolated struct SessionRecoveryMetadata: Codable, Equatable, Sendable {

    /// The schema version this build writes and is able to read.
    static let currentSchemaVersion = 1

    /// The version of the record's layout.
    let schemaVersion: Int

    /// The session's stable identity, matching ``MeetingSession/id``.
    let sessionID: UUID

    /// The meeting's display title, the same one the transcript header carries.
    let title: String

    /// When the meeting's timeline began.
    let startedAt: Date

    /// Display names of the applications that were being captured.
    let sourceNames: [String]

    /// The BCP-47 locale recognition ran in.
    let localeIdentifier: String

    /// The transcript's path relative to the session directory.
    let transcriptPath: String

    /// What the meeting was asked to keep of its audio.
    ///
    /// Recorded because it is not discoverable afterwards: a meeting that was
    /// keeping audio and was killed before its first captured buffer leaves a
    /// session directory that looks exactly like one that was keeping none.
    /// `nil` in records written before audio retention existed.
    let audioRetention: AudioRetentionMode?

    /// The retained recording's path relative to the session directory, when
    /// the session was keeping one. `nil` otherwise, and no claim that the
    /// file is there or that it plays.
    let audioPath: String?

    /// Where the session stands.
    let status: SessionRecoveryStatus

    /// When ScribeKit closed the session, for every status it wrote while it
    /// was running — ``SessionRecoveryStatus/completed``,
    /// ``SessionRecoveryStatus/failed``, and the
    /// ``SessionRecoveryStatus/interrupted`` written when capture ended by
    /// itself. `nil` otherwise, because a meeting ScribeKit did not close has
    /// no end time it can honestly state.
    let endedAt: Date?

    /// When ScribeKit *recorded* an interruption.
    ///
    /// For a session found unfinished after a relaunch this is the moment the
    /// user was shown it. For a meeting whose capture ended while ScribeKit
    /// was running it is the moment capture ended, which this process did
    /// observe.
    ///
    /// It is deliberately not the moment a killed process stopped: that moment is
    /// not observable from inside a process that was killed, and inventing it
    /// would put a fact in the record that nothing measured.
    let interruptedAt: Date?

    /// When the meeting was paused, while it still is.
    ///
    /// Set while a meeting is paused and cleared when it resumes, so a record
    /// found with both this and ``SessionRecoveryStatus/inProgress`` describes
    /// a meeting that was paused when ScribeKit stopped. `nil` in every record
    /// written before pausing existed, and in every meeting that was running
    /// when it was last written.
    let pausedAt: Date?

    /// Seconds of audio the meeting had captured when the record was last
    /// written.
    ///
    /// Media time, not wall-clock time: it excludes whatever the meeting spent
    /// paused, which is what makes it the length of the retained recording and
    /// the offset the next resumed span continues from. `nil` in records
    /// written before pausing existed.
    let capturedDuration: Double?

    /// Creates a record.
    ///
    /// - Parameters:
    ///   - schemaVersion: The layout version. Defaults to
    ///     ``currentSchemaVersion``; a test passes another to prove an unknown
    ///     version is refused.
    ///   - sessionID: The session's stable identity.
    ///   - title: The meeting's display title.
    ///   - startedAt: When the meeting's timeline began.
    ///   - sourceNames: Display names of the captured applications.
    ///   - localeIdentifier: The BCP-47 recognition locale.
    ///   - transcriptPath: The transcript's path relative to the session
    ///     directory.
    ///   - audioRetention: What the meeting was asked to keep of its audio.
    ///   - audioPath: The recording's path relative to the session directory.
    ///   - status: Where the session stands.
    ///   - endedAt: When ScribeKit closed the session, if it did.
    ///   - interruptedAt: When ScribeKit recorded an interruption, if it has.
    ///   - pausedAt: When the meeting was paused, while it still is.
    ///   - capturedDuration: Seconds of audio captured so far.
    init(
        schemaVersion: Int = SessionRecoveryMetadata.currentSchemaVersion,
        sessionID: UUID,
        title: String,
        startedAt: Date,
        sourceNames: [String],
        localeIdentifier: String,
        transcriptPath: String = SessionArtifactLayout.transcriptFileName,
        audioRetention: AudioRetentionMode? = nil,
        audioPath: String? = nil,
        status: SessionRecoveryStatus,
        endedAt: Date? = nil,
        interruptedAt: Date? = nil,
        pausedAt: Date? = nil,
        capturedDuration: Double? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.title = title
        self.startedAt = startedAt
        self.sourceNames = sourceNames
        self.localeIdentifier = localeIdentifier
        self.transcriptPath = transcriptPath
        self.audioRetention = audioRetention
        self.audioPath = audioPath
        self.status = status
        self.endedAt = endedAt
        self.interruptedAt = interruptedAt
        self.pausedAt = pausedAt
        self.capturedDuration = capturedDuration
    }

    /// Whether ScribeKit stopped while this meeting was paused.
    ///
    /// Only true for a record that says a meeting was still open, so a
    /// completed meeting that happened to be paused before its Stop is not
    /// described as having been abandoned mid-pause.
    var wasPausedWhenInterrupted: Bool {
        pausedAt != nil && (status == .inProgress || status == .interrupted)
    }

    /// The same record with the meeting's pause state brought up to date.
    ///
    /// - Parameters:
    ///   - pausedAt: When the meeting was paused, or `nil` once it resumed.
    ///   - capturedDuration: Seconds of audio captured so far.
    /// - Returns: A copy carrying the new pause state.
    func pausing(at pausedAt: Date?, capturedDuration: Double) -> SessionRecoveryMetadata {
        copy(
            status: status,
            endedAt: endedAt,
            interruptedAt: interruptedAt,
            pausedAt: pausedAt,
            capturedDuration: capturedDuration
        )
    }

    /// The same record marked as closed by ScribeKit.
    ///
    /// - Parameters:
    ///   - outcome: How the session ended.
    ///   - endedAt: When it ended.
    ///   - capturedDuration: Seconds of audio the meeting captured, which the
    ///     runtime knows exactly at this point and which is therefore recorded
    ///     for every session ScribeKit closes rather than only for one that
    ///     was paused. `nil` keeps whatever the record already carries, which
    ///     is what a caller that cannot measure it must pass.
    /// - Returns: A copy carrying the new status, end time and captured
    ///   length.
    func closed(
        _ outcome: SessionCompletionOutcome,
        at endedAt: Date,
        capturedDuration: Double? = nil
    ) -> SessionRecoveryMetadata {
        // A closed meeting is not paused, whatever it was doing a moment ago.
        // An interruption ScribeKit closed itself is dated: unlike one found
        // after a relaunch, this process was running and watched it happen.
        copy(
            status: outcome.recoveryStatus,
            endedAt: endedAt,
            interruptedAt: outcome == .interrupted ? endedAt : interruptedAt,
            pausedAt: .some(nil),
            capturedDuration: capturedDuration
        )
    }

    /// The same record marked as an interruption ScribeKit has now reported.
    ///
    /// - Parameter date: When the interruption was recorded, not when the
    ///   meeting stopped.
    /// - Returns: A copy carrying ``SessionRecoveryStatus/interrupted``.
    func markingInterruption(recordedAt date: Date) -> SessionRecoveryMetadata {
        // ``pausedAt`` is carried through: that the meeting was paused when
        // ScribeKit stopped is a fact it observed and wrote down, and the
        // recovery screen says so rather than dropping it.
        copy(status: .interrupted, endedAt: endedAt, interruptedAt: date)
    }

    /// Where the transcript lives, given the session's directory.
    ///
    /// - Parameter directory: The session directory the record was read from.
    /// - Returns: The transcript's location.
    func transcriptURL(in directory: URL) -> URL {
        directory.appending(path: transcriptPath, directoryHint: .notDirectory)
    }

    /// Where the retained recording would be, given the session's directory.
    ///
    /// - Parameter directory: The session directory the record was read from.
    /// - Returns: The recording's location, or `nil` when the session was
    ///   keeping no audio. This is arithmetic on a path; it says nothing about
    ///   whether a file is there.
    func audioURL(in directory: URL) -> URL? {
        audioPath.map { directory.appending(path: $0, directoryHint: .notDirectory) }
    }

    /// Builds a copy with a different lifecycle position.
    ///
    /// - Parameters:
    ///   - status: The new status.
    ///   - endedAt: The new end time.
    ///   - interruptedAt: The new interruption time.
    ///   - pausedAt: The new pause time, wrapped once so that `.some(nil)`
    ///     clears it and an omitted argument keeps the current one.
    ///   - capturedDuration: The new captured duration. Defaults to the
    ///     current one.
    /// - Returns: The copy.
    private func copy(
        status: SessionRecoveryStatus,
        endedAt: Date?,
        interruptedAt: Date?,
        pausedAt: Date?? = nil,
        capturedDuration: Double? = nil
    ) -> SessionRecoveryMetadata {
        SessionRecoveryMetadata(
            schemaVersion: schemaVersion,
            sessionID: sessionID,
            title: title,
            startedAt: startedAt,
            sourceNames: sourceNames,
            localeIdentifier: localeIdentifier,
            transcriptPath: transcriptPath,
            audioRetention: audioRetention,
            audioPath: audioPath,
            status: status,
            endedAt: endedAt,
            interruptedAt: interruptedAt,
            pausedAt: pausedAt ?? self.pausedAt,
            capturedDuration: capturedDuration ?? self.capturedDuration
        )
    }
}

// MARK: - Encoding

nonisolated extension SessionRecoveryMetadata {

    /// Only the version, read before anything else is interpreted.
    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    /// The encoder used for every record ScribeKit writes.
    ///
    /// Keys are sorted and the output is indented so the file is stable
    /// between writes and legible to anyone who opens it while working out
    /// what happened to a meeting.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// The decoder used for every record ScribeKit reads.
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Renders the record as the bytes of `session.json`.
    ///
    /// - Returns: UTF-8 JSON.
    /// - Throws: ``SessionRecoveryError/metadataMalformed`` when the record
    ///   cannot be encoded, which would mean a programming error rather than a
    ///   damaged file.
    func encoded() throws -> Data {
        do {
            return try Self.encoder.encode(self)
        } catch {
            throw SessionRecoveryError.metadataMalformed
        }
    }

    /// Reads a record, refusing anything this build cannot interpret.
    ///
    /// The version is read on its own first. A record from a later schema is
    /// reported as unsupported rather than decoded field by field, because
    /// fields that happen to still parse would give a confident answer about a
    /// layout this build has never seen.
    ///
    /// - Parameter data: The contents of `session.json`.
    /// - Returns: The decoded record.
    /// - Throws: ``SessionRecoveryError/metadataMalformed`` when the bytes are
    ///   not a readable v1 record, or
    ///   ``SessionRecoveryError/unsupportedSchemaVersion(_:)`` when they
    ///   announce a version this build does not know.
    static func decoded(from data: Data) throws -> SessionRecoveryMetadata {
        guard let probe = try? decoder.decode(SchemaProbe.self, from: data) else {
            throw SessionRecoveryError.metadataMalformed
        }
        guard probe.schemaVersion == currentSchemaVersion else {
            throw SessionRecoveryError.unsupportedSchemaVersion(probe.schemaVersion)
        }
        guard let metadata = try? decoder.decode(SessionRecoveryMetadata.self, from: data) else {
            throw SessionRecoveryError.metadataMalformed
        }
        return metadata
    }
}

/// How a meeting ended, as the writer reports it to the session record.
///
/// The cases are not interchangeable, and the distinction they carry is not
/// the same distinction as "did the files close cleanly". ``completed`` says
/// two things at once and needs both: every durable artifact the meeting
/// enabled — the transcript, and the retained recording when there is one —
/// was finished successfully, *and* the meeting ended because someone ended
/// it. ``failed`` says an artifact stopped working. ``interrupted`` says the
/// artifacts are fine and the meeting is not: capture ended by itself, so the
/// document stops where the audio did.
///
/// Closing a transcript successfully is therefore never on its own enough to
/// record a completion, which is why the caller states the outcome rather than
/// letting one be assumed.
nonisolated enum SessionCompletionOutcome: Equatable, Sendable {
    /// Every durable artifact was finished normally, at the end of a meeting
    /// that was stopped deliberately.
    case completed

    /// The meeting ended because a durable artifact could not be saved or
    /// could not be finalised.
    case failed

    /// The meeting ended because capture stopped without being asked to. The
    /// artifacts are closed and hold everything that reached them.
    case interrupted

    /// Whether the transcript's closing block may be written for this outcome.
    ///
    /// A footer states when the meeting ended and how long it ran, which are
    /// facts about a document that closed cleanly. That is true of a meeting
    /// whose capture died as much as of one that was stopped; it is not true
    /// of a meeting whose file refused a write.
    var writesFooter: Bool { self != .failed }

    /// The status this outcome is recorded as.
    var recoveryStatus: SessionRecoveryStatus {
        switch self {
        case .completed: .completed
        case .failed: .failed
        case .interrupted: .interrupted
        }
    }
}
