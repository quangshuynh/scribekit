//
//  MarkdownTranscriptStoreTests.swift
//  ScribeKitTests
//

import Foundation
import Synchronization
import Testing
@testable import ScribeKit

/// A file store that records what was created and can fail on demand, so the
/// writer's ordering and failure handling are testable without arranging a
/// full disk or a revoked permission.
private nonisolated final class FakeFileStore: TranscriptFileStoring {
    private struct State {
        var existing: Set<String> = []
        var directories: [URL] = []
        var files: [URL] = []
        var directoryError: (any Error)?
        var createFileError: (any Error)?
    }

    private let state = Mutex(State())

    /// The last file opened for appending.
    let file = FakeFile()

    /// Names that already exist, used to exercise collision naming.
    func markExisting(_ paths: [String]) {
        state.withLock { $0.existing.formUnion(paths) }
    }

    /// Directories the writer asked for, in order.
    var directories: [URL] { state.withLock { $0.directories } }

    /// Files the writer asked for, in order.
    var files: [URL] { state.withLock { $0.files } }

    /// Makes directory creation fail.
    func failDirectoryCreation(with error: any Error) {
        state.withLock { $0.directoryError = error }
    }

    /// Makes file creation fail.
    func failFileCreation(with error: any Error) {
        state.withLock { $0.createFileError = error }
    }

    func exists(at url: URL) -> Bool {
        state.withLock { $0.existing.contains(url.lastPathComponent) }
    }

    func createDirectory(at url: URL) throws {
        let error: (any Error)? = state.withLock { state in
            if let error = state.directoryError { return error }
            state.directories.append(url)
            state.existing.insert(url.lastPathComponent)
            return nil
        }
        if let error { throw error }
    }

    func createFile(at url: URL) throws -> any TranscriptFileAppending {
        let error: (any Error)? = state.withLock { state in
            if let error = state.createFileError { return error }
            state.files.append(url)
            return nil
        }
        if let error { throw error }
        return file
    }
}

/// A file that accumulates what was appended and can fail on demand.
private nonisolated final class FakeFile: TranscriptFileAppending {
    private struct State {
        var text = ""
        var synchronizeCount = 0
        var closeCount = 0
        var appendError: (any Error)?
        var closeError: (any Error)?
    }

    private let state = Mutex(State())

    /// Everything appended so far.
    var text: String { state.withLock { $0.text } }

    /// How many times the file was flushed to the storage device.
    var synchronizeCount: Int { state.withLock { $0.synchronizeCount } }

    /// How many times the file was closed.
    var closeCount: Int { state.withLock { $0.closeCount } }

    /// Makes every later append fail.
    func failAppends(with error: any Error) {
        state.withLock { $0.appendError = error }
    }

    /// Makes closing fail.
    func failClose(with error: any Error) {
        state.withLock { $0.closeError = error }
    }

    func append(_ text: String) throws {
        let error: (any Error)? = state.withLock { state in
            if let error = state.appendError { return error }
            state.text += text
            return nil
        }
        if let error { throw error }
    }

    func synchronize() throws {
        state.withLock { $0.synchronizeCount += 1 }
    }

    func close() throws {
        let error: (any Error)? = state.withLock { state in
            state.closeCount += 1
            return state.closeError
        }
        if let error { throw error }
    }
}

/// Records the review sidecars a session wrote, and can refuse to write one.
private nonisolated final class FakeSessionReviewStore: SessionReviewStoring {
    private struct State {
        var written: [SessionReviewMetadata] = []
        var fails = false
    }

    private let state = Mutex(State())

    /// The sidecars written, in order.
    var written: [SessionReviewMetadata] { state.withLock { $0.written } }

    /// Makes every write fail, as a read-only or full disk would.
    func failWrites() { state.withLock { $0.fails = true } }

    func writeReview(_ metadata: SessionReviewMetadata, to layout: SessionArtifactLayout) throws {
        try state.withLock { state in
            if state.fails { throw SessionReviewError.writeFailed }
            state.written.append(metadata)
        }
    }
}

@Suite("MarkdownTranscriptStore")
struct MarkdownTranscriptStoreTests {

    private let zone = TimeZone(identifier: "America/New_York")!
    private let destination = URL(filePath: "/Users/example/Meetings", directoryHint: .isDirectory)

    /// 31 August 2026, 11:00:00 in ``zone``.
    private var startedAt: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 11, minute: 0))!
    }

    /// The meeting the tests record.
    private var session: MeetingSession {
        MeetingSession(
            title: "iOS Training - Day 2",
            createdAt: startedAt,
            selectedSources: [.application(bundleIdentifier: "com.example.Teams", displayName: "Microsoft Teams")],
            destination: destination
        )
    }

    /// A finalised span.
    ///
    /// - Parameters:
    ///   - text: The recognised text.
    ///   - start: Seconds from the start of the run.
    ///   - state: Whether the recogniser finalised it.
    /// - Returns: The segment.
    private func segment(
        _ text: String,
        start: Double = 0,
        state: TranscriptSegment.RecognitionState = .final
    ) -> TranscriptSegment {
        TranscriptSegment(
            text: text,
            startTime: start,
            endTime: start + 1,
            state: state,
            localeIdentifier: "en-US"
        )
    }

    /// A store over doubles, with the fakes it writes through.
    private func makeStore(
        access: FakeSecurityScopedAccess = FakeSecurityScopedAccess(),
        recoveryStore: FakeSessionRecoveryStore = FakeSessionRecoveryStore(),
        reviewStore: FakeSessionReviewStore = FakeSessionReviewStore()
    ) -> (MarkdownTranscriptStore, FakeFileStore, FakeSecurityScopedAccess) {
        let fileStore = FakeFileStore()
        let store = MarkdownTranscriptStore(
            fileStore: fileStore,
            recoveryStore: recoveryStore,
            reviewStore: reviewStore,
            access: access,
            timeZone: zone
        )
        return (store, fileStore, access)
    }

    /// A finalised span the recogniser reported a confidence for.
    ///
    /// - Parameters:
    ///   - text: The recognised text.
    ///   - start: Seconds from the start of the run.
    ///   - confidence: The recogniser's own confidence.
    /// - Returns: The segment.
    private func segment(_ text: String, start: Double, confidence: Double?) -> TranscriptSegment {
        TranscriptSegment(
            text: text,
            startTime: start,
            endTime: start + 1,
            state: .final,
            localeIdentifier: "en-US",
            confidence: confidence
        )
    }

    /// Starts a session on the store.
    ///
    /// - Parameter store: The store to start.
    /// - Returns: Where the session's artifacts live.
    private func start(_ store: MarkdownTranscriptStore) async throws -> SessionArtifactLayout {
        try await store.startSession(session, localeIdentifier: "en-US", startedAt: startedAt)
    }

    // MARK: - Pause and resume

    @Test("A paused meeting writes truthful markers and keeps one transcript")
    func pauseAndResumeAreWrittenStructurally() async throws {
        let recoveryStore = FakeSessionRecoveryStore()
        let (store, fileStore, _) = makeStore(recoveryStore: recoveryStore)
        let layout = try await start(store)

        try await store.appendFinalSegment(segment("Phrase A.", start: 30))
        // Paused 40 s into the meeting with 40 s captured, resumed five
        // minutes later on the wall clock and not a second later in the audio.
        try await store.recordPause(at: startedAt.addingTimeInterval(40), capturedDuration: 40)
        try await store.recordResume(at: startedAt.addingTimeInterval(340), capturedDuration: 40)
        try await store.appendFinalSegment(segment("Phrase B.", start: 41))
        try await store.finishSession(
            endedAt: startedAt.addingTimeInterval(400),
            outcome: .completed,
            capturedDuration: 100
        )

        let text = fileStore.file.text
        #expect(text.contains("> **Paused:** 11:00:40 AM."))
        #expect(text.contains("> **Resumed:** 11:05:40 AM, after 5 min 0 s paused."))
        // Media offset 41 s is one second after the resume, which is
        // 11:05:41 on the wall clock and not 11:00:41.
        #expect(text.contains("**11:05:41 AM**"))
        #expect(text.contains("**11:00:30 AM**"))
        #expect(text.contains("Phrase A."))
        #expect(text.contains("Phrase B."))
        #expect(text.contains("**Duration:** 6 min 40 s"))
        #expect(text.contains("**Captured:** 1 min 40 s"))
        // Recognised prose is untouched: the only structural additions are the
        // two blockquote markers.
        #expect(text.components(separatedBy: "Phrase A.").count == 2)
        #expect(text.components(separatedBy: "> **").count == 3)
        #expect(fileStore.files == [layout.transcriptURL])
    }

    @Test("Pausing records the pause in the session record without closing the session")
    func pauseUpdatesTheRecordHonestly() async throws {
        let recoveryStore = FakeSessionRecoveryStore()
        let (store, _, _) = makeStore(recoveryStore: recoveryStore)
        let layout = try await start(store)

        try await store.recordPause(at: startedAt.addingTimeInterval(40), capturedDuration: 40)
        let paused = try recoveryStore.loadMetadata(from: layout)
        #expect(paused.status == .inProgress)
        #expect(paused.wasPausedWhenInterrupted)
        #expect(paused.capturedDuration == 40)
        #expect(await store.currentLayout != nil)

        try await store.recordResume(at: startedAt.addingTimeInterval(340), capturedDuration: 40)
        let resumed = try recoveryStore.loadMetadata(from: layout)
        #expect(resumed.status == .inProgress)
        #expect(!resumed.wasPausedWhenInterrupted)

        try await store.finishSession(
            endedAt: startedAt.addingTimeInterval(400),
            outcome: .completed,
            capturedDuration: 100
        )
        let closed = try recoveryStore.loadMetadata(from: layout)
        #expect(closed.status == .completed)
        #expect(closed.pausedAt == nil)
    }

    // MARK: - Session creation

    @Test("Starting a session creates a dated directory and a transcript in it")
    func startCreatesTheExpectedLayout() async throws {
        let (store, fileStore, _) = makeStore()

        let layout = try await start(store)

        #expect(layout.directory.lastPathComponent == "2026-08-31-ios-training-day-2")
        #expect(layout.directory.deletingLastPathComponent().path() == destination.path())
        #expect(layout.transcriptURL.lastPathComponent == "transcript.md")
        #expect(fileStore.directories == [layout.directory])
        #expect(fileStore.files == [layout.transcriptURL])
    }

    @Test("The transcript writer creates no audio file, whatever the meeting is keeping", arguments: [
        AudioRetentionMode.none, .raw, .compressed
    ])
    func onlyTheTranscriptIsCreated(retention: AudioRetentionMode) async throws {
        let (store, fileStore, _) = makeStore()
        var meeting = session
        meeting.audioRetention = retention

        _ = try await store.startSession(meeting, localeIdentifier: "en-US", startedAt: startedAt)

        // Audio is a separate artifact with a separate owner: this writer
        // creates the transcript and the record, and nothing else.
        #expect(fileStore.files.count == 1)
        #expect(fileStore.files.allSatisfy { $0.pathExtension == "md" })
    }

    @Test("A name already in use is stepped past rather than written into")
    func collidingNamesGainASuffix() async throws {
        let (store, fileStore, _) = makeStore()
        fileStore.markExisting(["2026-08-31-ios-training-day-2", "2026-08-31-ios-training-day-2-2"])

        let layout = try await start(store)

        #expect(layout.directory.lastPathComponent == "2026-08-31-ios-training-day-2-3")
    }

    @Test("The header is written when the transcript is created")
    func headerIsWrittenOnce() async throws {
        let (store, fileStore, _) = makeStore()

        _ = try await start(store)

        #expect(fileStore.file.text == """
            # iOS Training - Day 2

            **Date:** 2026-08-31
            **Started:** 11:00 AM
            **Sources:** Microsoft Teams
            **Language:** en-US
            **Captured by:** ScribeKit

            ## Transcript


            """)
    }

    @Test("A second session is refused while one is open")
    func oneSessionAtATime() async throws {
        let (store, _, _) = makeStore()
        _ = try await start(store)

        await #expect(throws: TranscriptPersistenceError.self) {
            _ = try await start(store)
        }
    }

    // MARK: - Access

    @Test("The folder lease is held for the session and released when it ends")
    func leaseSpansTheSession() async throws {
        let (store, _, access) = makeStore()

        _ = try await start(store)
        #expect(access.started == [destination])
        #expect(access.stopped.isEmpty)

        try await store.appendFinalSegment(segment("One."))
        #expect(access.stopped.isEmpty)

        try await store.finishSession(endedAt: startedAt.addingTimeInterval(60))
        #expect(access.stopped == [destination])
    }

    @Test("Refused access fails the session instead of writing outside the sandbox")
    func refusedAccessFailsTheStart() async {
        let (store, fileStore, _) = makeStore(access: FakeSecurityScopedAccess(isGranted: false))

        await #expect(throws: TranscriptPersistenceError.self) {
            _ = try await start(store)
        }
        #expect(fileStore.directories.isEmpty)
    }

    @Test("A failed start releases the lease it had taken")
    func failedStartReleasesTheLease() async {
        let (store, fileStore, access) = makeStore()
        fileStore.failDirectoryCreation(with: CocoaError(.fileWriteNoPermission))

        await #expect(throws: TranscriptPersistenceError.self) {
            _ = try await start(store)
        }
        #expect(access.isBalanced)
    }

    @Test("A transcript that cannot be created is reported, not worked around")
    func fileCreationFailureIsReported() async {
        let (store, fileStore, access) = makeStore()
        fileStore.failFileCreation(with: CocoaError(.fileWriteVolumeReadOnly))

        await #expect(throws: TranscriptPersistenceError.self) {
            _ = try await start(store)
        }
        #expect(access.isBalanced)
    }

    // MARK: - Appending

    @Test("Finalised spans are appended in order, after the header")
    func appendsAreOrdered() async throws {
        let (store, fileStore, _) = makeStore()
        _ = try await start(store)

        try await store.appendFinalSegment(segment("First sentence.", start: 0))
        try await store.appendFinalSegment(segment("Second sentence.", start: 5))
        try await store.appendFinalSegment(segment("Third sentence.", start: 70))

        let body = fileStore.file.text.components(separatedBy: "## Transcript\n\n")[1]
        #expect(body == """
            ### 11:00 AM

            **11:00:00 AM**

            First sentence.

            **11:00:05 AM**

            Second sentence.

            ### 11:01 AM

            **11:01:10 AM**

            Third sentence.


            """)
    }

    @Test("A partial hypothesis is refused rather than written")
    func partialsAreRefused() async throws {
        let (store, fileStore, _) = makeStore()
        _ = try await start(store)
        let before = fileStore.file.text

        await #expect(throws: TranscriptPersistenceError.self) {
            try await store.appendFinalSegment(segment("Today we", state: .partial))
        }
        #expect(fileStore.file.text == before)
    }

    @Test("Repeated revisions of one sentence leave one entry, because only the final one is offered")
    func onlyFinalisedTextBecomesAnEntry() async throws {
        let (store, fileStore, _) = makeStore()
        _ = try await start(store)

        for text in ["Today", "Today we", "Today we are"] {
            try? await store.appendFinalSegment(segment(text, state: .partial))
        }
        try await store.appendFinalSegment(segment("Today we are learning Swift."))

        #expect(fileStore.file.text.components(separatedBy: "**11:00:00 AM**").count == 2)
        #expect(!fileStore.file.text.contains("Today we are\n"))
    }

    @Test("Gaps are written as an explicit marker")
    func gapsAreWritten() async throws {
        let (store, fileStore, _) = makeStore()
        _ = try await start(store)

        try await store.recordGap(TranscriptGap(startTime: 12, duration: 0.8, reason: .audioDropped))

        #expect(fileStore.file.text.hasSuffix(
            "> **Transcription gap:** approximately 0.8 seconds of audio around 11:00:12 AM "
            + "was not transcribed; recognition fell behind capture.\n\n"
        ))
    }

    @Test("Appending without a session is refused")
    func appendNeedsASession() async {
        let (store, _, _) = makeStore()

        await #expect(throws: TranscriptPersistenceError.self) {
            try await store.appendFinalSegment(segment("Nowhere to go."))
        }
    }

    @Test("A failed append is surfaced rather than absorbed")
    func appendFailureIsSurfaced() async throws {
        let (store, fileStore, _) = makeStore()
        _ = try await start(store)
        fileStore.file.failAppends(with: CocoaError(.fileWriteOutOfSpace))

        await #expect(throws: TranscriptPersistenceError.self) {
            try await store.appendFinalSegment(segment("Lost words."))
        }
    }

    @Test("The transcript is checkpointed periodically, not on every sentence")
    func flushesAreCoarse() async throws {
        let (store, fileStore, _) = makeStore()
        _ = try await start(store)

        for index in 0..<MarkdownTranscriptStore.synchronizeInterval {
            try await store.appendFinalSegment(segment("Sentence \(index).", start: Double(index)))
        }

        #expect(fileStore.file.synchronizeCount == 1)
    }

    // MARK: - Finishing

    @Test("Finishing writes the footer, flushes, closes and releases")
    func finishCompletesTheDocument() async throws {
        let (store, fileStore, access) = makeStore()
        _ = try await start(store)
        try await store.appendFinalSegment(segment("Only sentence."))

        try await store.finishSession(endedAt: startedAt.addingTimeInterval(2_832))

        #expect(fileStore.file.text.hasSuffix("""
            ---

            **Ended:** 11:47 AM
            **Duration:** 47 min 12 s

            """))
        #expect(fileStore.file.synchronizeCount == 1)
        #expect(fileStore.file.closeCount == 1)
        #expect(access.isBalanced)
    }

    @Test("A close that fails is reported, and the folder is released anyway")
    func closeFailureIsReported() async throws {
        let (store, fileStore, access) = makeStore()
        _ = try await start(store)
        fileStore.file.failClose(with: CocoaError(.fileWriteUnknown))

        await #expect(throws: TranscriptPersistenceError.self) {
            try await store.finishSession(endedAt: startedAt)
        }
        #expect(access.isBalanced)
    }

    @Test("Finishing twice is refused, so a session cannot be closed over")
    func finishNeedsAnOpenSession() async throws {
        let (store, _, _) = makeStore()
        _ = try await start(store)
        try await store.finishSession(endedAt: startedAt)

        await #expect(throws: TranscriptPersistenceError.self) {
            try await store.finishSession(endedAt: startedAt)
        }
    }

    @Test("A finished session can be followed by a distinct new one")
    func sessionsAreRepeatable() async throws {
        let (store, fileStore, _) = makeStore()
        let first = try await start(store)
        try await store.finishSession(endedAt: startedAt)

        let second = try await start(store)

        #expect(first.directory != second.directory)
        #expect(fileStore.directories.count == 2)
    }

    // MARK: - Real files

    @Test("A real session directory and transcript are created on disk and stay readable")
    func writesARealReadableFile() async throws {
        let root = URL.temporaryDirectory.appending(
            path: "scribekit-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = MarkdownTranscriptStore(
            access: FakeSecurityScopedAccess(),
            timeZone: zone
        )
        let meeting = MeetingSession(
            title: "iOS Training - Day 2",
            createdAt: startedAt,
            selectedSources: [.application(bundleIdentifier: "com.example.Teams", displayName: "Microsoft Teams")],
            destination: root
        )

        let layout = try await store.startSession(meeting, localeIdentifier: "en-US", startedAt: startedAt)
        try await store.appendFinalSegment(segment("Today we are learning about closures.", start: 2))

        // Readable while the meeting is still running: the file is appended to,
        // never rewritten, so what has been written is already there.
        let midMeeting = try String(contentsOf: layout.transcriptURL, encoding: .utf8)
        #expect(midMeeting.contains("# iOS Training - Day 2"))
        #expect(midMeeting.contains("Today we are learning about closures."))
        #expect(!midMeeting.contains("**Ended:**"))

        try await store.appendFinalSegment(segment("A closure is a block of code.", start: 65))
        try await store.finishSession(endedAt: startedAt.addingTimeInterval(120))

        let finished = try String(contentsOf: layout.transcriptURL, encoding: .utf8)
        #expect(finished.hasPrefix(midMeeting))
        #expect(finished.contains("### 11:01 AM"))
        #expect(finished.contains("**Duration:** 2 min 0 s"))
        // The transcript is the user's document; the session record beside it is
        // ScribeKit's own bookkeeping, and it is the only other thing written.
        #expect(FileManager.default.fileExists(atPath: layout.metadataURL.path(percentEncoded: false)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: layout.directory.path(percentEncoded: false))
            .sorted() == [".scribekit", "transcript.md"])
    }

    // MARK: - Session record

    @Test("Starting a session records it as in progress, beside the transcript")
    func startRecordsTheSessionAsInProgress() async throws {
        let recoveryStore = FakeSessionRecoveryStore()
        let (store, _, _) = makeStore(recoveryStore: recoveryStore)
        let meeting = session

        let layout = try await store.startSession(meeting, localeIdentifier: "en-US", startedAt: startedAt)
        let record = try #require(recoveryStore.storedMetadata(in: layout.directory))

        #expect(record.schemaVersion == SessionRecoveryMetadata.currentSchemaVersion)
        #expect(record.status == .inProgress)
        #expect(record.sessionID == meeting.id)
        #expect(record.title == "iOS Training - Day 2")
        #expect(record.startedAt == startedAt)
        #expect(record.sourceNames == ["Microsoft Teams"])
        #expect(record.localeIdentifier == "en-US")
        #expect(record.transcriptPath == "transcript.md")
        #expect(record.audioRetention == AudioRetentionMode.none)
        #expect(record.audioPath == nil)
        #expect(record.endedAt == nil)
        #expect(layout.metadataURL.path(percentEncoded: false).hasSuffix(".scribekit/session.json"))
    }

    @Test("The record names the recording a meeting is keeping", arguments: [
        (AudioRetentionMode.raw, "audio.caf"),
        (AudioRetentionMode.compressed, "audio.m4a")
    ])
    func recordNamesTheRecording(retention: AudioRetentionMode, name: String) async throws {
        let recoveryStore = FakeSessionRecoveryStore()
        let (store, _, _) = makeStore(recoveryStore: recoveryStore)
        var meeting = session
        meeting.audioRetention = retention

        let layout = try await store.startSession(meeting, localeIdentifier: "en-US", startedAt: startedAt)
        let record = try #require(recoveryStore.storedMetadata(in: layout.directory))

        #expect(record.audioRetention == retention)
        #expect(record.audioPath == name)
        #expect(record.audioURL(in: layout.directory) == layout.audioURL(for: retention))
    }

    @Test("A meeting whose session record cannot be written does not begin")
    func startWithoutARecordIsRefused() async {
        let recoveryStore = FakeSessionRecoveryStore()
        recoveryStore.failWrites()
        let access = FakeSecurityScopedAccess()
        let (store, fileStore, _) = makeStore(access: access, recoveryStore: recoveryStore)

        await #expect(throws: TranscriptPersistenceError.self) {
            _ = try await start(store)
        }

        #expect(fileStore.file.closeCount == 1)
        #expect(access.isBalanced)
        #expect(await store.currentLayout == nil)
    }

    @Test("The reason a start without a record is refused names the record, not the transcript")
    func startWithoutARecordNamesTheRecord() async {
        let recoveryStore = FakeSessionRecoveryStore()
        recoveryStore.failWrites()
        let (store, _, _) = makeStore(recoveryStore: recoveryStore)

        do {
            _ = try await start(store)
            Issue.record("Expected the start to be refused")
        } catch let error as TranscriptPersistenceError {
            #expect(error.reason == .recoveryMetadataFailed)
        } catch {
            Issue.record("Expected a transcript persistence error")
        }
    }

    @Test("The transcript is flushed and closed before completion is recorded")
    func completionFollowsTheClosedTranscript() async throws {
        let recoveryStore = FakeSessionRecoveryStore()
        let (store, fileStore, _) = makeStore(recoveryStore: recoveryStore)
        _ = try await start(store)
        let observed = Mutex<[(status: SessionRecoveryStatus, closes: Int, flushes: Int, text: String)]>([])
        recoveryStore.observeWrites { metadata in
            observed.withLock {
                $0.append((
                    status: metadata.status,
                    closes: fileStore.file.closeCount,
                    flushes: fileStore.file.synchronizeCount,
                    text: fileStore.file.text
                ))
            }
        }

        try await store.finishSession(endedAt: startedAt.addingTimeInterval(64))

        let writes = observed.withLock { $0 }
        #expect(writes.count == 1)
        let completion = try #require(writes.first)
        #expect(completion.status == .completed)
        #expect(completion.closes == 1)
        #expect(completion.flushes >= 1)
        #expect(completion.text.contains("**Ended:**"))
    }

    @Test("A transcript that will not close is never recorded as completed")
    func aTranscriptThatWillNotCloseStaysUnfinished() async throws {
        let recoveryStore = FakeSessionRecoveryStore()
        let (store, fileStore, access) = makeStore(recoveryStore: recoveryStore)
        let layout = try await start(store)
        fileStore.file.failClose(with: CocoaError(.fileWriteUnknown))

        await #expect(throws: TranscriptPersistenceError.self) {
            try await store.finishSession(endedAt: startedAt.addingTimeInterval(64))
        }

        #expect(recoveryStore.storedMetadata(in: layout.directory)?.status == .inProgress)
        #expect(recoveryStore.writes.map(\.status) == [.inProgress])
        #expect(access.isBalanced)
    }

    @Test("A completion that cannot be recorded is reported instead of claimed")
    func unrecordedCompletionIsReported() async throws {
        let recoveryStore = FakeSessionRecoveryStore()
        let (store, _, access) = makeStore(recoveryStore: recoveryStore)
        let layout = try await start(store)
        recoveryStore.failWrites()

        do {
            try await store.finishSession(endedAt: startedAt.addingTimeInterval(64))
            Issue.record("Expected the completion to be reported as unrecorded")
        } catch let error as TranscriptPersistenceError {
            #expect(error.reason == .recoveryMetadataFailed)
        }

        #expect(recoveryStore.storedMetadata(in: layout.directory)?.status == .inProgress)
        #expect(access.isBalanced)
    }

    @Test("A meeting ended by a save failure is recorded as failed, with no closing block")
    func aFailedMeetingIsRecordedAsFailed() async throws {
        let recoveryStore = FakeSessionRecoveryStore()
        let (store, fileStore, access) = makeStore(recoveryStore: recoveryStore)
        let layout = try await start(store)

        try await store.finishSession(endedAt: startedAt.addingTimeInterval(64), outcome: .failed)

        let record = try #require(recoveryStore.storedMetadata(in: layout.directory))
        #expect(record.status == .failed)
        #expect(record.endedAt == startedAt.addingTimeInterval(64))
        #expect(!fileStore.file.text.contains("**Ended:**"))
        #expect(!fileStore.file.text.contains("**Duration:**"))
        #expect(fileStore.file.closeCount == 1)
        #expect(access.isBalanced)
    }

    @Test("A meeting whose capture died is recorded as interrupted, with its closing block and a marker")
    func anInterruptedMeetingIsRecordedAsInterrupted() async throws {
        let recoveryStore = FakeSessionRecoveryStore()
        let (store, fileStore, access) = makeStore(recoveryStore: recoveryStore)
        let layout = try await start(store)
        try await store.appendFinalSegment(segment("Before the stream ended."))
        let before = fileStore.file.text

        try await store.finishSession(
            endedAt: startedAt.addingTimeInterval(64),
            outcome: .interrupted,
            capturedDuration: 64
        )

        let record = try #require(recoveryStore.storedMetadata(in: layout.directory))
        #expect(record.status == .interrupted)
        #expect(record.endedAt == startedAt.addingTimeInterval(64))
        #expect(record.interruptedAt == startedAt.addingTimeInterval(64))
        #expect(record.capturedDuration == 64)
        // The artifacts closed cleanly, so the document states when it ended,
        // and it says plainly that nobody stopped the meeting.
        let text = fileStore.file.text
        #expect(text.hasPrefix(before))
        #expect(text.contains("**Capture ended unexpectedly:**"))
        #expect(text.contains("Before the stream ended."))
        #expect(text.contains("**Ended:**"))
        #expect(text.range(of: "**Capture ended unexpectedly:**")!.lowerBound
            < text.range(of: "**Ended:**")!.lowerBound)
        #expect(fileStore.file.closeCount == 1)
        #expect(access.isBalanced)
    }

    @Test("A never-paused meeting records the length it captured, not only a paused one")
    func capturedDurationIsRecordedForEveryClosedSession() async throws {
        let recoveryStore = FakeSessionRecoveryStore()
        let (store, _, _) = makeStore(recoveryStore: recoveryStore)
        let layout = try await start(store)

        try await store.finishSession(
            endedAt: startedAt.addingTimeInterval(64),
            outcome: .completed,
            capturedDuration: 61.5
        )

        let record = try #require(recoveryStore.storedMetadata(in: layout.directory))
        #expect(record.status == .completed)
        #expect(record.capturedDuration == 61.5)
        #expect(record.pausedAt == nil)
    }

    @Test("A paused meeting records the media time it captured rather than its wall-clock length")
    func capturedDurationExcludesTimePaused() async throws {
        let recoveryStore = FakeSessionRecoveryStore()
        let (store, _, _) = makeStore(recoveryStore: recoveryStore)
        let layout = try await start(store)
        try await store.recordPause(at: startedAt.addingTimeInterval(30), capturedDuration: 30)
        try await store.recordResume(at: startedAt.addingTimeInterval(90), capturedDuration: 30)

        try await store.finishSession(
            endedAt: startedAt.addingTimeInterval(150),
            outcome: .completed,
            capturedDuration: 90
        )

        let record = try #require(recoveryStore.storedMetadata(in: layout.directory))
        #expect(record.capturedDuration == 90)
        #expect(record.pausedAt == nil)
    }

    // MARK: - Review metadata

    @Test("A finished session records the spans worth reviewing, by their position in the document")
    func reviewSidecarNamesSpansByPosition() async throws {
        let reviewStore = FakeSessionReviewStore()
        let (store, _, _) = makeStore(reviewStore: reviewStore)
        _ = try await start(store)

        try await store.appendFinalSegment(segment("Good morning everyone.", start: 0, confidence: 0.95))
        try await store.appendFinalSegment(segment("The boat hole telemetry.", start: 5, confidence: 0.144))
        try await store.appendFinalSegment(segment("Let us start with the budget.", start: 9, confidence: 0.82))
        try await store.finishSession(endedAt: startedAt.addingTimeInterval(60))

        let written = try #require(reviewStore.written.first)
        #expect(written.recognizerConfidenceAvailable)
        #expect(written.candidates.map(\.spanIndex) == [1])
        #expect(written.candidates.first?.startTime == 5)
        #expect(written.candidates.first?.reasons == [.lowConfidence])
        #expect(written.candidates.first?.priority == .high)
    }

    @Test("A span written straight after a gap is flagged as being beside missing audio")
    func spanAfterAGapIsFlagged() async throws {
        let reviewStore = FakeSessionReviewStore()
        let (store, _, _) = makeStore(reviewStore: reviewStore)
        _ = try await start(store)

        try await store.appendFinalSegment(segment("Before the loss.", start: 0, confidence: 0.99))
        try await store.recordGap(TranscriptGap(startTime: 1, duration: 2, reason: .audioDropped))
        try await store.appendFinalSegment(segment("After the loss.", start: 3, confidence: 0.99))
        try await store.appendFinalSegment(segment("And on from there.", start: 5, confidence: 0.99))
        try await store.finishSession(endedAt: startedAt.addingTimeInterval(60))

        let written = try #require(reviewStore.written.first)
        #expect(written.candidates.map(\.spanIndex) == [1])
        #expect(written.candidates.first?.reasons == [.nearInterruption])
        #expect(written.candidates.first?.priority == .low)
    }

    @Test("A meeting whose recogniser reported no confidence says so rather than claiming certainty")
    func absentConfidenceIsRecorded() async throws {
        let reviewStore = FakeSessionReviewStore()
        let (store, _, _) = makeStore(reviewStore: reviewStore)
        _ = try await start(store)

        try await store.appendFinalSegment(segment("Nothing measured this.", start: 0, confidence: nil))
        try await store.finishSession(endedAt: startedAt.addingTimeInterval(60))

        let written = try #require(reviewStore.written.first)
        #expect(!written.recognizerConfidenceAvailable)
        #expect(written.candidates.isEmpty)
    }

    @Test("The transcript's bytes are the same whatever confidence the recogniser reported")
    func confidenceNeverReachesTheTranscript() async throws {
        let (confident, confidentFiles, _) = makeStore()
        _ = try await start(confident)
        try await confident.appendFinalSegment(segment("The boat hole telemetry.", start: 5, confidence: 0.99))
        try await confident.finishSession(endedAt: startedAt.addingTimeInterval(60))

        let (unsure, unsureFiles, _) = makeStore()
        _ = try await start(unsure)
        try await unsure.appendFinalSegment(segment("The boat hole telemetry.", start: 5, confidence: 0.02))
        try await unsure.finishSession(endedAt: startedAt.addingTimeInterval(60))

        #expect(confidentFiles.file.text == unsureFiles.file.text)
        #expect(!unsureFiles.file.text.contains("0.02"))
        #expect(!unsureFiles.file.text.lowercased().contains("confidence"))
    }

    @Test("A sidecar that cannot be written does not fail a meeting whose transcript is safe")
    func reviewFailureDoesNotFailTheMeeting() async throws {
        let reviewStore = FakeSessionReviewStore()
        reviewStore.failWrites()
        let (store, fileStore, access) = makeStore(reviewStore: reviewStore)
        _ = try await start(store)

        try await store.appendFinalSegment(segment("The boat hole telemetry.", start: 5, confidence: 0.1))
        try await store.finishSession(endedAt: startedAt.addingTimeInterval(60))

        #expect(reviewStore.written.isEmpty)
        #expect(fileStore.file.text.contains("**Ended:**"))
        #expect(fileStore.file.closeCount == 1)
        #expect(access.isBalanced)
    }
}
