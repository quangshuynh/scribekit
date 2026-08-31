//
//  MarkdownTranscriptStore.swift
//  ScribeKit
//

import Foundation
import OSLog

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
///
/// The audio file a session may also keep is not written here. The store owns
/// the transcript, the record and the folder lease, and that lease is what a
/// retained recording is written under — which is why the recording is closed
/// before ``finishSession(endedAt:outcome:capturedDuration:)`` is called, and why a recording
/// that could not be finalised reaches this type as
/// ``SessionCompletionOutcome/failed`` rather than as a completion.
///
/// Beside the transcript the store also keeps what the meeting observed about
/// its own recognition, in `.scribekit/review.json`. It holds span positions,
/// audio-relative offsets and the evidence behind them, never transcript text:
/// the canonical Markdown is written exactly as the recogniser produced it and
/// carries no confidence annotation of any kind.
///
/// Beside the transcript the store keeps one small operational record,
/// `.scribekit/session.json`, so a meeting that ends without ScribeKit is
/// recognisable as unfinished the next time it launches. The record is written
/// last when a session starts — a meeting that cannot establish one does not
/// begin — and last again when a session ends, after the transcript has been
/// flushed and closed, so nothing is ever recorded as completed ahead of the
/// file it describes.
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
        var metadata: SessionRecoveryMetadata
        var formatter: TranscriptMarkdownFormatter
        var appendsSinceSynchronize = 0

        /// How many finalised spans have been written, which is the index the
        /// next one will occupy in the document.
        var spanIndex = 0

        /// Whether the last thing written was a gap, so the next span is the
        /// first one finalised after untranscribed audio.
        var followsInterruption = false

        /// Whether the recogniser reported a confidence of its own for any
        /// span in this meeting.
        var sawRecognizerConfidence = false

        /// The spans put forward for review, in the order they were written.
        var reviewCandidates: [TranscriptReviewCandidate] = []

        /// When the meeting was paused, while it still is.
        var pausedAt: Date?

        /// Seconds of audio the meeting has captured, as the last pause or
        /// resume reported it. Media time, so it is also the length of the
        /// retained recording.
        var capturedDuration: Double = 0
    }

    private let fileStore: any TranscriptFileStoring
    private let recoveryStore: any SessionRecoveryStoring
    private let reviewStore: any SessionReviewStoring
    private let access: any SecurityScopedResourceAccessing
    private let timeZone: TimeZone
    private var current: OpenSession?

    /// Creates a store.
    ///
    /// - Parameters:
    ///   - fileStore: How directories and files are created. The system by
    ///     default; tests substitute a double that can fail on demand.
    ///   - recoveryStore: How the session record is written. The system by
    ///     default; tests substitute a double that can fail on demand.
    ///   - reviewStore: How the review sidecar is written. The system by
    ///     default; tests substitute a double that can fail on demand.
    ///   - access: How security-scoped access is started and stopped.
    ///   - timeZone: The zone session names and clock times are written in.
    ///     The current zone by default, so a meeting is filed and timed as the
    ///     user experienced it.
    init(
        fileStore: any TranscriptFileStoring = FileManagerTranscriptFileStore(),
        recoveryStore: any SessionRecoveryStoring = FileManagerSessionRecoveryStore(),
        reviewStore: any SessionReviewStoring = FileManagerSessionReviewStore(),
        access: any SecurityScopedResourceAccessing = SystemSecurityScopedResourceAccess(),
        timeZone: TimeZone = .current
    ) {
        self.fileStore = fileStore
        self.recoveryStore = recoveryStore
        self.reviewStore = reviewStore
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
                ScribeKitLog.persistence.info("Session directory created")
            } catch {
                ScribeKitLog.persistence.error("Session directory not created")
                throw TranscriptPersistenceError(.directoryCreationFailed, underlying: error)
            }

            let file: any TranscriptFileAppending
            do {
                file = try fileStore.createFile(at: layout.transcriptURL)
                ScribeKitLog.persistence.info("Transcript opened")
            } catch {
                ScribeKitLog.persistence.error("Transcript not opened")
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

            let metadata = SessionRecoveryMetadata(
                sessionID: session.id,
                title: session.displayTitle,
                startedAt: startedAt,
                sourceNames: session.selectedSources.map(\.displayName),
                localeIdentifier: localeIdentifier,
                audioRetention: session.audioRetention,
                audioPath: layout.audioURL(for: session.audioRetention)?.lastPathComponent,
                status: .inProgress
            )
            do {
                try recoveryStore.writeMetadata(metadata, to: layout)
            } catch {
                try? file.close()
                throw TranscriptPersistenceError(.recoveryMetadataFailed, underlying: error)
            }

            current = OpenSession(
                lease: lease,
                file: file,
                layout: layout,
                metadata: metadata,
                formatter: formatter
            )
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

        // Review evidence is recorded only once the span has actually reached
        // the file, so a candidate can never name a span the transcript does
        // not contain. The index it names is the count of spans written before
        // it, which is the index the parser gives that span when the document
        // is read back.
        if segment.confidence != nil { session.sawRecognizerConfidence = true }
        if let candidate = TranscriptReviewPolicy.candidate(
            for: segment,
            spanIndex: session.spanIndex,
            followsInterruption: session.followsInterruption
        ) {
            session.reviewCandidates.append(candidate)
        }
        session.spanIndex += 1
        session.followsInterruption = false
        current = session
    }

    func recordGap(_ gap: TranscriptGap) async throws {
        guard var session = current else { throw TranscriptPersistenceError(.noSessionInProgress) }

        try write(session.formatter.gap(gap), to: &session)
        session.followsInterruption = true
        current = session
    }

    func recordPause(at date: Date, capturedDuration: Double) async throws {
        guard var session = current else { throw TranscriptPersistenceError(.noSessionInProgress) }

        try write(session.formatter.paused(at: date), to: &session)
        session.pausedAt = date
        session.capturedDuration = capturedDuration
        session.metadata = session.metadata.pausing(at: date, capturedDuration: capturedDuration)
        // A pause is a point the transcript may have to survive from, so the
        // record is brought up to date now rather than at the next stop: a
        // ScribeKit that stops while a meeting is paused must leave a record
        // that says the meeting was paused, not one that says it was running.
        // A record that cannot be written does not fail the meeting — the
        // transcript is what matters and it is intact — but it is reported.
        do {
            try recoveryStore.writeMetadata(session.metadata, to: session.layout)
        } catch {
            current = session
            throw TranscriptPersistenceError(.recoveryMetadataFailed, underlying: error)
        }
        current = session
    }

    func recordResume(at date: Date, capturedDuration: Double) async throws {
        guard var session = current else { throw TranscriptPersistenceError(.noSessionInProgress) }

        let text = session.formatter.resumed(at: date, pausedAt: session.pausedAt)
        // The epoch opens before the marker is written, so every timestamp
        // from here on is measured from this resume rather than from a start
        // the wall clock has since run away from. Timestamps already in the
        // file are untouched.
        session.formatter.resume(at: date, capturedDuration: capturedDuration)
        try write(text, to: &session)
        session.pausedAt = nil
        session.capturedDuration = capturedDuration
        session.metadata = session.metadata.pausing(at: nil, capturedDuration: capturedDuration)
        do {
            try recoveryStore.writeMetadata(session.metadata, to: session.layout)
        } catch {
            current = session
            throw TranscriptPersistenceError(.recoveryMetadataFailed, underlying: error)
        }
        current = session
    }

    func finishSession(
        endedAt: Date,
        outcome: SessionCompletionOutcome,
        capturedDuration: Double
    ) async throws {
        guard var session = current else { throw TranscriptPersistenceError(.noSessionInProgress) }
        current = nil
        session.capturedDuration = max(session.capturedDuration, capturedDuration)
        defer { session.lease.release() }

        var failure: Error?
        if outcome.writesFooter {
            do {
                // A meeting whose capture died says so at the point it died,
                // before the closing block states when the document ended. The
                // remark is appended like every other structural marker: it
                // rewrites nothing, and it goes in before the footer so the
                // file still ends with its closing block.
                if outcome == .interrupted {
                    try session.file.append(session.formatter.captureInterrupted(at: endedAt))
                }
                try session.file.append(session.formatter.footer(
                    endedAt: endedAt,
                    capturedDuration: session.capturedDuration
                ))
            } catch {
                failure = error
            }
        }
        do { try session.file.synchronize() } catch { failure = failure ?? error }
        do { try session.file.close() } catch { failure = failure ?? error }

        // The record is only allowed to claim completion once the transcript
        // above has actually been flushed and closed. A transcript that failed
        // to close is left recorded as in progress, so the next launch offers
        // the meeting for recovery instead of believing a completion that
        // never happened.
        if let failure { throw TranscriptPersistenceError(.flushFailed, underlying: failure) }

        writeReview(for: session)

        do {
            // The captured length is recorded for every session ScribeKit
            // closes, not only for one that paused: at this point the runtime
            // has measured it, so leaving the field absent would describe a
            // record written before the field existed rather than the meeting
            // that just ended.
            try recoveryStore.writeMetadata(
                session.metadata.closed(
                    outcome,
                    at: endedAt,
                    capturedDuration: session.capturedDuration
                ),
                to: session.layout
            )
        } catch {
            throw TranscriptPersistenceError(.recoveryMetadataFailed, underlying: error)
        }
    }

    /// Writes the review sidecar for a session that has just been closed.
    ///
    /// Best effort, and deliberately so. The sidecar is optional bookkeeping:
    /// a meeting whose sidecar could not be written is a meeting with no review
    /// information, which is exactly the state every session recorded before
    /// this file existed is in and which History already handles. Failing a
    /// meeting whose transcript and recording are both safely closed, over a
    /// file that only makes a later convenience possible, would be the wrong
    /// trade. Nothing is hidden by it either: History says plainly when a
    /// session carries no review information.
    ///
    /// - Parameter session: The session that has just been flushed and closed.
    private func writeReview(for session: OpenSession) {
        let metadata = SessionReviewMetadata(
            sessionID: session.metadata.sessionID,
            recognizerConfidenceAvailable: session.sawRecognizerConfidence,
            candidates: session.reviewCandidates
        )
        try? reviewStore.writeReview(metadata, to: session.layout)
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
