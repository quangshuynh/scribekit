//
//  HistoryService.swift
//  ScribeKit
//

import Foundation

/// A session directory history could not make sense of.
///
/// Damaged records are reported rather than hidden. One unreadable session
/// never stops the rest of the folder from being listed, and nothing about it
/// is repaired, rewritten or removed.
nonisolated struct HistoryProblem: Identifiable, Equatable, Sendable {

    /// The session directory the problem was found in.
    let directory: URL

    /// What was wrong.
    let error: HistoryError

    /// The directory, which identifies the problem uniquely within one scan.
    var id: URL { directory }

    /// The session directory's name, which is what the interface shows.
    var name: String { directory.lastPathComponent }

    /// Creates a problem.
    ///
    /// - Parameters:
    ///   - directory: The session directory.
    ///   - error: What was wrong.
    init(directory: URL, error: HistoryError) {
        self.directory = directory
        self.error = error
    }
}

/// Everything one load of the save folder found.
nonisolated struct HistoryReport: Equatable, Sendable {

    /// The sessions found, newest first, each with the words said in it.
    let documents: [TranscriptSearchDocument]

    /// Session directories that could not be interpreted, in directory-name
    /// order.
    let problems: [HistoryProblem]

    /// A load that found nothing.
    static let empty = HistoryReport(documents: [], problems: [])

    /// The sessions, without their transcript text.
    var sessions: [HistorySession] { documents.map(\.session) }

    /// Whether there is anything for the interface to show.
    var isEmpty: Bool { documents.isEmpty && problems.isEmpty }

    /// Creates a report.
    ///
    /// - Parameters:
    ///   - documents: The sessions found.
    ///   - problems: Session directories that could not be interpreted.
    init(documents: [TranscriptSearchDocument], problems: [HistoryProblem]) {
        self.documents = documents
        self.problems = problems
    }
}

/// Lists the meetings in the user's save folder and reads what was said in
/// them.
///
/// History and recovery ask different questions of the same folder. Recovery
/// asks whether a meeting is unfinished, considers only records marked in
/// progress, and may write one thing — the interruption it records at the
/// user's request. History asks what is in the folder, shows every session it
/// can describe, and writes nothing at all: its store has no write side.
/// Keeping them separate is what stops either question from having to be
/// answered in terms of the other.
///
/// The service is an actor, so its filesystem work runs off the main actor and
/// one load at a time. The scan is sequential rather than a task per
/// transcript: a save folder is local storage being read in order, and fanning
/// hundreds of concurrent reads at it would cost more than it saved.
///
/// It runs when it is asked to. There is no timer, no filesystem watcher and
/// no repeat scan, and nothing is left running when a load returns.
///
/// Security-scoped access is owned here and nowhere else in history: one load
/// opens access to the save folder for the length of that load and closes it
/// again, so History holds no claim on the user's folder while it is merely
/// being looked at.
actor HistoryService {

    private let store: any HistoryStoring
    private let access: any SecurityScopedResourceAccessing

    /// Creates a service.
    ///
    /// - Parameters:
    ///   - store: How session artifacts are read. The system by default; tests
    ///     substitute a double that can fail on demand.
    ///   - access: How security-scoped access is started and stopped.
    init(
        store: any HistoryStoring = FileManagerHistoryStore(),
        access: any SecurityScopedResourceAccessing = SystemSecurityScopedResourceAccess()
    ) {
        self.store = store
        self.access = access
    }

    /// Lists the meetings in one save folder.
    ///
    /// Only the immediate subdirectories of `destination` are looked at. A
    /// directory holding neither a session record nor a recognisable ScribeKit
    /// transcript is not a meeting and is passed over in silence; a directory
    /// ScribeKit clearly wrote but cannot describe is reported as a problem
    /// rather than dropped.
    ///
    /// Nothing is written. Records and transcripts are read, file sizes and
    /// modification dates are measured, and recordings are neither opened nor
    /// decoded, so a load leaves every byte of every artifact exactly as it
    /// found it.
    ///
    /// - Parameter destination: The folder the user chose, restored from its
    ///   security-scoped bookmark.
    /// - Returns: What the load found.
    /// - Throws: ``HistoryError/destinationUnavailable`` when the folder
    ///   cannot be opened or listed. ScribeKit never substitutes another
    ///   folder for one it cannot reach.
    func load(_ destination: URL) throws -> HistoryReport {
        try withDestinationAccess(destination) {
            var documents: [TranscriptSearchDocument] = []
            var problems: [HistoryProblem] = []

            for directory in try store.sessionDirectories(in: destination) {
                do {
                    if let document = try document(in: directory) {
                        documents.append(document)
                    }
                } catch let error as HistoryError {
                    problems.append(HistoryProblem(directory: directory, error: error))
                }
            }

            return HistoryReport(
                documents: documents.sorted(by: Self.newestFirst),
                problems: problems.sorted { $0.directory.path < $1.directory.path }
            )
        }
    }

    /// Describes one session directory.
    ///
    /// - Parameter directory: The directory to read.
    /// - Returns: The session and its text, or `nil` when the directory is not
    ///   a ScribeKit meeting at all.
    /// - Throws: ``HistoryError`` when the directory is a ScribeKit meeting
    ///   that cannot be described.
    private func document(in directory: URL) throws -> TranscriptSearchDocument? {
        let layout = SessionArtifactLayout(directory: directory)
        guard let data = try store.metadataData(at: layout.metadataURL) else {
            return legacyDocument(in: directory, layout: layout)
        }

        let metadata: SessionRecoveryMetadata
        do {
            metadata = try SessionRecoveryMetadata.decoded(from: data)
        } catch SessionRecoveryError.unsupportedSchemaVersion(let version) {
            throw HistoryError.unsupportedSchemaVersion(version)
        } catch {
            throw HistoryError.metadataMalformed
        }

        let transcriptURL = metadata.transcriptURL(in: directory)
        guard let info = store.fileInfo(at: transcriptURL) else { throw HistoryError.transcriptMissing }
        let document = TranscriptDocument.parse(try store.readTranscript(at: transcriptURL))

        let session = HistorySession(
            directory: directory,
            sessionID: metadata.sessionID,
            title: metadata.title,
            status: HistorySessionStatus(metadata.status),
            startedAt: metadata.startedAt,
            endedAt: metadata.endedAt,
            sourceNames: metadata.sourceNames,
            localeIdentifier: metadata.localeIdentifier,
            transcriptURL: transcriptURL,
            transcript: info,
            audioRetention: metadata.audioRetention,
            audio: metadata.audioURL(in: directory).flatMap(audio(at:))
        )
        return TranscriptSearchDocument(session: session, spans: document.spans)
    }

    /// Describes a session directory that holds no record.
    ///
    /// A transcript written before session records existed is still a meeting
    /// the user keeps, so history offers it — but only on deterministic
    /// evidence that ScribeKit wrote it: the title heading, the
    /// `**Captured by:** ScribeKit` field and the transcript heading. A
    /// Markdown file the user happens to store in the same folder has none of
    /// those and is not listed as a meeting.
    ///
    /// Recovery is unaffected by this. A session with no record is not an
    /// unfinished meeting and never becomes a recovery candidate; history
    /// reads the same folder without changing what recovery considers.
    ///
    /// - Parameters:
    ///   - directory: The directory to read.
    ///   - layout: Where its artifacts would be.
    /// - Returns: The session and its text, or `nil` when the directory is not
    ///   a ScribeKit meeting.
    private func legacyDocument(in directory: URL, layout: SessionArtifactLayout) -> TranscriptSearchDocument? {
        guard let info = store.fileInfo(at: layout.transcriptURL),
              let text = try? store.readTranscript(at: layout.transcriptURL)
        else { return nil }

        let document = TranscriptDocument.parse(text)
        guard document.isScribeKitTranscript, let title = document.title else { return nil }

        let session = HistorySession(
            directory: directory,
            sessionID: nil,
            title: title,
            status: .unrecorded,
            startedAt: nil,
            endedAt: nil,
            sourceNames: document.sourceNames,
            localeIdentifier: document.localeIdentifier,
            transcriptURL: layout.transcriptURL,
            transcript: info,
            audioRetention: nil,
            audio: legacyAudio(in: layout)
        )
        return TranscriptSearchDocument(session: session, spans: document.spans)
    }

    /// Finds a recording beside a transcript that has no record naming one.
    ///
    /// The two names ScribeKit writes are tried, in a fixed order, and nothing
    /// else in the directory is considered a recording.
    ///
    /// - Parameter layout: Where the session's artifacts would be.
    /// - Returns: The recording, or `nil` when there is none.
    private func legacyAudio(in layout: SessionArtifactLayout) -> HistoryAudio? {
        for mode in [AudioRetentionMode.raw, .compressed] {
            guard let url = layout.audioURL(for: mode), let found = audio(at: url) else { continue }
            return found
        }
        return nil
    }

    /// Measures a recording without opening it.
    ///
    /// - Parameter url: Where the recording would be.
    /// - Returns: Its format, size and modification date, or `nil` when no
    ///   file is there.
    private func audio(at url: URL) -> HistoryAudio? {
        guard let format = HistoryAudioFormat(fileExtension: url.pathExtension),
              let info = store.fileInfo(at: url)
        else { return nil }
        return HistoryAudio(url: url, format: format, file: info)
    }

    /// Runs work with security-scoped access to the save folder held open for
    /// exactly the length of that work.
    ///
    /// - Parameters:
    ///   - destination: The folder the user chose.
    ///   - body: The work to perform.
    /// - Returns: Whatever `body` returns.
    /// - Throws: ``HistoryError/destinationUnavailable`` when macOS refuses
    ///   access, or whatever `body` throws.
    private func withDestinationAccess<T>(
        _ destination: URL,
        perform body: () throws -> T
    ) throws -> T {
        do {
            return try SecurityScopedAccess.withAccess(to: destination, using: access) { _ in try body() }
        } catch is SaveLocationError {
            throw HistoryError.destinationUnavailable
        }
    }

    /// Orders sessions newest first, breaking ties on the directory path so
    /// repeated loads of the same folder produce the same list.
    ///
    /// - Parameters:
    ///   - lhs: One document.
    ///   - rhs: Another.
    /// - Returns: Whether `lhs` sorts before `rhs`.
    private static func newestFirst(
        _ lhs: TranscriptSearchDocument,
        _ rhs: TranscriptSearchDocument
    ) -> Bool {
        if lhs.session.sortDate != rhs.session.sortDate {
            return lhs.session.sortDate > rhs.session.sortDate
        }
        return lhs.session.directory.path < rhs.session.directory.path
    }
}
