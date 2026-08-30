//
//  SessionRecoveryService.swift
//  ScribeKit
//

import Foundation

/// An unfinished meeting ScribeKit found in the user's save folder.
///
/// A candidate is evidence, not a promise. It says that a session record was
/// left marked in progress and that a readable transcript is sitting beside
/// it; it makes no claim about speech that never reached the file, and none
/// about what happened between the last durable write and the relaunch.
nonisolated struct SessionRecoveryCandidate: Identifiable, Equatable, Sendable {

    /// The record read from the session's `.scribekit/session.json`.
    let metadata: SessionRecoveryMetadata

    /// Where the session's artifacts live.
    let layout: SessionArtifactLayout

    /// The save folder the session was found in, which is the directory
    /// security-scoped access is held for.
    let destination: URL

    /// The transcript as the filesystem describes it.
    let transcript: SessionFileInfo

    /// The retained recording as the filesystem describes it, when the session
    /// was keeping one and the file is there.
    ///
    /// It is measured, never opened: a recording a killed process left behind
    /// may or may not play, and ScribeKit reports its size rather than a
    /// promise it has not verified.
    let retainedAudio: SessionFileInfo?

    /// The session's own identity, so a list of candidates is stable.
    var id: UUID { metadata.sessionID }

    /// Where the transcript is.
    var transcriptURL: URL { metadata.transcriptURL(in: layout.directory) }

    /// Where the retained recording is, when there is one to point at.
    var retainedAudioURL: URL? {
        retainedAudio == nil ? nil : metadata.audioURL(in: layout.directory)
    }

    /// Creates a candidate.
    ///
    /// - Parameters:
    ///   - metadata: The session's record.
    ///   - layout: Where its artifacts live.
    ///   - destination: The save folder it was found in.
    ///   - transcript: The transcript's size and modification date.
    ///   - retainedAudio: The recording's size and modification date, when the
    ///     session kept one and it is still there.
    init(
        metadata: SessionRecoveryMetadata,
        layout: SessionArtifactLayout,
        destination: URL,
        transcript: SessionFileInfo,
        retainedAudio: SessionFileInfo? = nil
    ) {
        self.metadata = metadata
        self.layout = layout
        self.destination = destination
        self.transcript = transcript
        self.retainedAudio = retainedAudio
    }
}

/// A session directory ScribeKit could not make sense of.
///
/// Damaged records are reported rather than repaired or removed. A record that
/// cannot be read may be the only remaining evidence of what happened to a
/// meeting, and the transcript beside it is the user's either way.
nonisolated struct SessionRecoveryProblem: Identifiable, Equatable, Sendable {

    /// The session directory the problem was found in.
    let directory: URL

    /// What was wrong.
    let error: SessionRecoveryError

    /// The directory, which identifies the problem uniquely within one scan.
    var id: URL { directory }

    /// The session directory's name, which is what the interface shows.
    var name: String { directory.lastPathComponent }

    /// Creates a problem.
    ///
    /// - Parameters:
    ///   - directory: The session directory.
    ///   - error: What was wrong.
    init(directory: URL, error: SessionRecoveryError) {
        self.directory = directory
        self.error = error
    }
}

/// Everything one scan of the save folder found.
nonisolated struct SessionRecoveryReport: Equatable, Sendable {

    /// Sessions left marked in progress, most recently started first.
    let candidates: [SessionRecoveryCandidate]

    /// Session directories whose records could not be interpreted, in
    /// directory-name order.
    let problems: [SessionRecoveryProblem]

    /// A scan that found nothing to report.
    static let empty = SessionRecoveryReport(candidates: [], problems: [])

    /// Whether there is anything for the interface to show.
    var isEmpty: Bool { candidates.isEmpty && problems.isEmpty }

    /// Creates a report.
    ///
    /// - Parameters:
    ///   - candidates: Sessions left marked in progress.
    ///   - problems: Session directories that could not be interpreted.
    init(candidates: [SessionRecoveryCandidate], problems: [SessionRecoveryProblem]) {
        self.candidates = candidates
        self.problems = problems
    }
}

/// Finds meetings that never finished, and records honestly that they did not.
///
/// The service is an actor so its filesystem work runs off the main actor and
/// one scan or update at a time. It runs when it is asked to and then stops:
/// there is no timer, no watcher and no repeated scan, because a session
/// record only changes when ScribeKit itself changes it.
///
/// What it will not do is as much of its definition as what it will. It never
/// starts capture, never touches ScreenCaptureKit or the Speech framework,
/// never walks anywhere but the immediate children of the folder the user
/// chose, never repairs or deletes a damaged record, and never rewrites a
/// transcript — the one modification it makes is appending a note the user
/// explicitly asked for.
///
/// Security-scoped access is owned here and nowhere else in recovery: each
/// call opens access to the save folder for the length of that call and closes
/// it again, so nothing is left held between a scan and whatever the user does
/// next.
actor SessionRecoveryService {

    private let store: any SessionRecoveryStoring
    private let access: any SecurityScopedResourceAccessing
    private let timeZone: TimeZone

    /// Creates a service.
    ///
    /// - Parameters:
    ///   - store: How session records and transcripts are reached. The system
    ///     by default; tests substitute a double that can fail on demand.
    ///   - access: How security-scoped access is started and stopped.
    ///   - timeZone: The zone the interruption note is written in.
    init(
        store: any SessionRecoveryStoring = FileManagerSessionRecoveryStore(),
        access: any SecurityScopedResourceAccessing = SystemSecurityScopedResourceAccess(),
        timeZone: TimeZone = .current
    ) {
        self.store = store
        self.access = access
        self.timeZone = timeZone
    }

    /// Scans one save folder for meetings that never finished.
    ///
    /// Only the immediate subdirectories of `destination` are looked at, and
    /// only their `.scribekit/session.json`. A directory without one is not a
    /// session ScribeKit recorded and is passed over in silence; every other
    /// way of failing to read a record is reported.
    ///
    /// Nothing is written, no transcript is opened for reading and no recording
    /// is decoded, so a scan leaves every byte of every artifact exactly as it
    /// found it — a partly written audio file included.
    ///
    /// - Parameter destination: The folder the user chose, restored from its
    ///   security-scoped bookmark.
    /// - Returns: What the scan found.
    /// - Throws: ``SessionRecoveryError/destinationUnavailable`` when the
    ///   folder cannot be opened or listed. ScribeKit never substitutes
    ///   another folder for one it cannot reach.
    func scan(_ destination: URL) throws -> SessionRecoveryReport {
        try withDestinationAccess(destination) {
            var candidates: [SessionRecoveryCandidate] = []
            var problems: [SessionRecoveryProblem] = []

            for directory in try store.sessionDirectories(in: destination) {
                let layout = SessionArtifactLayout(directory: directory)
                let metadata: SessionRecoveryMetadata
                do {
                    metadata = try store.loadMetadata(from: layout)
                } catch SessionRecoveryError.metadataMissing {
                    continue
                } catch let error as SessionRecoveryError {
                    problems.append(SessionRecoveryProblem(directory: directory, error: error))
                    continue
                }

                guard metadata.status == .inProgress else { continue }

                do {
                    let transcript = try store.transcriptInfo(at: metadata.transcriptURL(in: directory))
                    candidates.append(SessionRecoveryCandidate(
                        metadata: metadata,
                        layout: layout,
                        destination: destination,
                        transcript: transcript,
                        retainedAudio: metadata.audioURL(in: directory).flatMap(store.audioInfo)
                    ))
                } catch let error as SessionRecoveryError {
                    problems.append(SessionRecoveryProblem(directory: directory, error: error))
                }
            }

            return SessionRecoveryReport(
                candidates: candidates.sorted(by: Self.newestFirst),
                problems: problems.sorted { $0.directory.path < $1.directory.path }
            )
        }
    }

    /// Records that a meeting was found unfinished, and says so in its
    /// transcript.
    ///
    /// The record is updated first and the note appended second, which is
    /// deliberately the opposite order from completion. Completion is a claim
    /// about the transcript, so it must follow the file; the note is a remark
    /// added to the user's own document, and the failure worth preventing
    /// there is adding it twice. Updating the record first means an
    /// interruption is at worst recorded without its note, never noted twice.
    ///
    /// The record is re-read before anything is written. A session that is no
    /// longer marked in progress — because another ScribeKit already handled
    /// it — is returned unchanged rather than annotated again.
    ///
    /// - Parameters:
    ///   - candidate: The unfinished session, from ``scan(_:)``.
    ///   - date: When the interruption is being recorded, which is now. It is
    ///     not, and is never presented as, the moment the meeting stopped.
    /// - Returns: The record as it now stands on disk.
    /// - Throws: ``SessionRecoveryError`` when the session can no longer be
    ///   read, the record cannot be replaced, or the note cannot be appended.
    func recordInterruption(
        for candidate: SessionRecoveryCandidate,
        at date: Date = Date()
    ) throws -> SessionRecoveryMetadata {
        try withDestinationAccess(candidate.destination) {
            let current = try store.loadMetadata(from: candidate.layout)
            guard current.status == .inProgress else { return current }

            let transcriptURL = current.transcriptURL(in: candidate.layout.directory)
            _ = try store.transcriptInfo(at: transcriptURL)

            let updated = current.markingInterruption(recordedAt: date)
            try store.writeMetadata(updated, to: candidate.layout)
            try store.appendToTranscript(
                TranscriptMarkdownFormatter.interruptionNotice(recordedAt: date, timeZone: timeZone),
                at: transcriptURL
            )
            return updated
        }
    }

    /// Runs work with security-scoped access to the save folder held open for
    /// exactly the length of that work.
    ///
    /// - Parameters:
    ///   - destination: The folder the user chose.
    ///   - body: The work to perform.
    /// - Returns: Whatever `body` returns.
    /// - Throws: ``SessionRecoveryError/destinationUnavailable`` when macOS
    ///   refuses access, or whatever `body` throws.
    private func withDestinationAccess<T>(
        _ destination: URL,
        perform body: () throws -> T
    ) throws -> T {
        do {
            return try SecurityScopedAccess.withAccess(to: destination, using: access) { _ in try body() }
        } catch is SaveLocationError {
            throw SessionRecoveryError.destinationUnavailable
        }
    }

    /// Orders candidates most recently started first, breaking ties on the
    /// directory path so a scan of the same folder always produces the same
    /// list.
    ///
    /// - Parameters:
    ///   - lhs: One candidate.
    ///   - rhs: Another.
    /// - Returns: Whether `lhs` sorts before `rhs`.
    private static func newestFirst(
        _ lhs: SessionRecoveryCandidate,
        _ rhs: SessionRecoveryCandidate
    ) -> Bool {
        if lhs.metadata.startedAt != rhs.metadata.startedAt {
            return lhs.metadata.startedAt > rhs.metadata.startedAt
        }
        return lhs.layout.directory.path < rhs.layout.directory.path
    }
}
