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
        access: FakeSecurityScopedAccess = FakeSecurityScopedAccess()
    ) -> (MarkdownTranscriptStore, FakeFileStore, FakeSecurityScopedAccess) {
        let fileStore = FakeFileStore()
        let store = MarkdownTranscriptStore(fileStore: fileStore, access: access, timeZone: zone)
        return (store, fileStore, access)
    }

    /// Starts a session on the store.
    ///
    /// - Parameter store: The store to start.
    /// - Returns: Where the session's artifacts live.
    private func start(_ store: MarkdownTranscriptStore) async throws -> SessionArtifactLayout {
        try await store.startSession(session, localeIdentifier: "en-US", startedAt: startedAt)
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

    @Test("No audio file and no metadata file are created")
    func onlyTheTranscriptIsCreated() async throws {
        let (store, fileStore, _) = makeStore()

        _ = try await start(store)

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

            **11:00:00**

            First sentence.

            **11:00:05**

            Second sentence.

            ### 11:01 AM

            **11:01:10**

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

        #expect(fileStore.file.text.components(separatedBy: "**11:00:00**").count == 2)
        #expect(!fileStore.file.text.contains("Today we are\n"))
    }

    @Test("Gaps are written as an explicit marker")
    func gapsAreWritten() async throws {
        let (store, fileStore, _) = makeStore()
        _ = try await start(store)

        try await store.recordGap(TranscriptGap(startTime: 12, duration: 0.8, reason: .audioDropped))

        #expect(fileStore.file.text.hasSuffix(
            "> **Transcription gap:** approximately 0.8 seconds of audio around 11:00:12 "
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
        #expect(!FileManager.default.fileExists(atPath: layout.metadataURL.path(percentEncoded: false)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: layout.directory.path(percentEncoded: false))
            == ["transcript.md"])
    }
}
