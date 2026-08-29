//
//  MarkdownTranscriptStore.swift
//  ScribeKit
//

import Foundation

/// Writes the canonical Markdown transcript for one meeting at a time.
///
/// The actor is the serialised owner of everything a durable session needs:
/// the lease on the user's folder, the open file, and the formatter's position
/// in the document. Because it is an actor, appends are ordered without a
/// queue of their own and a caller that awaits one is naturally held back
/// while the previous write completes — the backpressure a transcript needs,
/// with nothing to overflow and nothing to evict. Writes happen on the actor's
/// executor, never on the main actor.
///
/// The file is append-only. A header is written when the session starts, each
/// finalised span and gap is appended as it arrives, and a footer closes the
/// document; nothing already written is rewritten, so the cost of a meeting
/// does not grow with its length and the document on disk is readable at any
/// moment during the meeting.
///
/// Durability boundary, stated plainly: an append reaches the file as soon as
/// it returns, so everything accepted survives ScribeKit exiting or crashing.
/// The stronger guarantee — surviving a power loss — needs the file system's
/// own flush, which is asked for every ``synchronizeInterval`` appends and
/// once more when the session ends. There is no timer and no flush per audio
/// buffer.
actor MarkdownTranscriptStore: TranscriptPersisting {

    /// How many appends are made between flushes to the storage device.
    ///
    /// A coarse, event-driven checkpoint: frequent enough that a power loss
    /// costs a paragraph rather than a meeting, rare enough that finalising a
    /// sentence does not wait on the disk.
    static let synchronizeInterval = 25

    /// One open session.
    private struct OpenSession {
        let lease: SecurityScopedLease
        let file: any TranscriptFileAppending
        let layout: SessionArtifactLayout
        var formatter: TranscriptMarkdownFormatter
        var appendsSinceSynchronize = 0
    }

    private let fileStore: any TranscriptFileStoring
    private let access: any SecurityScopedResourceAccessing
    private let timeZone: TimeZone
    private var current: OpenSession?

    /// Creates a store.
    ///
    /// - Parameters:
    ///   - fileStore: How directories and files are created. The system by
    ///     default; tests substitute a double that can fail on demand.
    ///   - access: How security-scoped access is started and stopped.
    ///   - timeZone: The zone session names and clock times are written in.
    ///     The current zone by default, so a meeting is filed and timed as the
    ///     user experienced it.
    init(
        fileStore: any TranscriptFileStoring = FileManagerTranscriptFileStore(),
        access: any SecurityScopedResourceAccessing = SystemSecurityScopedResourceAccess(),
        timeZone: TimeZone = .current
    ) {
        self.fileStore = fileStore
        self.access = access
        self.timeZone = timeZone
    }

    /// Where the session being written lives, or `nil` when none is open.
    var currentLayout: SessionArtifactLayout? { current?.layout }

    func startSession(
        _ session: MeetingSession,
        localeIdentifier: String,
        startedAt: Date
    ) async throws -> SessionArtifactLayout {
        guard current == nil else { throw TranscriptPersistenceError(.sessionAlreadyInProgress) }

        let lease: SecurityScopedLease
        do {
            lease = try SecurityScopedLease.acquire(session.destination, using: access)
        } catch {
            throw TranscriptPersistenceError(.accessDenied, underlying: error)
        }

        do {
            let layout = SessionArtifactLayout(
                destination: session.destination,
                directoryName: directoryName(for: session, startedAt: startedAt)
            )
            do {
                try fileStore.createDirectory(at: layout.directory)
            } catch {
                throw TranscriptPersistenceError(.directoryCreationFailed, underlying: error)
            }

            let file: any TranscriptFileAppending
            do {
                file = try fileStore.createFile(at: layout.transcriptURL)
            } catch {
                throw TranscriptPersistenceError(.transcriptCreationFailed, underlying: error)
            }

            let formatter = TranscriptMarkdownFormatter(startedAt: startedAt, timeZone: timeZone)
            do {
                try file.append(formatter.header(
                    title: session.displayTitle,
                    sourceNames: session.selectedSources.map(\.displayName),
                    localeIdentifier: localeIdentifier
                ))
            } catch {
                try? file.close()
                throw TranscriptPersistenceError(.writeFailed, underlying: error)
            }

            current = OpenSession(lease: lease, file: file, layout: layout, formatter: formatter)
            return layout
        } catch {
            lease.release()
            throw error
        }
    }

    func appendFinalSegment(_ segment: TranscriptSegment) async throws {
        guard var session = current else { throw TranscriptPersistenceError(.noSessionInProgress) }
        guard segment.state == .final else { throw TranscriptPersistenceError(.segmentNotFinalized) }
        guard !segment.displayText.isEmpty else { return }

        let text = session.formatter.finalSegment(segment)
        try write(text, to: &session)
        current = session
    }

    func recordGap(_ gap: TranscriptGap) async throws {
        guard var session = current else { throw TranscriptPersistenceError(.noSessionInProgress) }

        try write(session.formatter.gap(gap), to: &session)
        current = session
    }

    func finishSession(endedAt: Date) async throws {
        guard let session = current else { throw TranscriptPersistenceError(.noSessionInProgress) }
        current = nil
        defer { session.lease.release() }

        var failure: Error?
        do { try session.file.append(session.formatter.footer(endedAt: endedAt)) } catch { failure = error }
        do { try session.file.synchronize() } catch { failure = failure ?? error }
        do { try session.file.close() } catch { failure = failure ?? error }

        if let failure { throw TranscriptPersistenceError(.flushFailed, underlying: failure) }
    }

    /// Names the session's directory, stepping past names already in use.
    ///
    /// - Parameters:
    ///   - session: The meeting being recorded.
    ///   - startedAt: When the session started.
    /// - Returns: A directory name that was free when it was chosen.
    private func directoryName(for session: MeetingSession, startedAt: Date) -> String {
        SessionDirectoryName.make(
            date: startedAt,
            title: session.title,
            timeZone: timeZone
        ) { candidate in
            fileStore.exists(at: session.destination.appending(path: candidate, directoryHint: .isDirectory))
        }
    }

    /// Appends text and checkpoints when enough has accumulated.
    ///
    /// - Parameters:
    ///   - text: The Markdown to append.
    ///   - session: The open session, whose flush counter is advanced.
    /// - Throws: ``TranscriptPersistenceError`` describing the failed write or
    ///   flush. The session is left open so the caller decides what a failure
    ///   means for the meeting.
    private func write(_ text: String, to session: inout OpenSession) throws {
        do {
            try session.file.append(text)
        } catch {
            throw TranscriptPersistenceError(.writeFailed, underlying: error)
        }

        session.appendsSinceSynchronize += 1
        guard session.appendsSinceSynchronize >= Self.synchronizeInterval else { return }
        session.appendsSinceSynchronize = 0
        do {
            try session.file.synchronize()
        } catch {
            throw TranscriptPersistenceError(.flushFailed, underlying: error)
        }
    }
}
