//
//  HistoryServiceTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@Suite("HistoryService")
struct HistoryServiceTests {

    private let destination = URL(filePath: "/Users/example/Meetings", directoryHint: .isDirectory)

    /// 29 August 2026, 14:01:00 UTC.
    private let startedAt = TranscriptFixture.startedAt

    /// A session directory inside the save folder.
    ///
    /// - Parameter name: The directory's name.
    /// - Returns: Its location.
    private func directory(_ name: String) -> URL {
        destination.appending(path: name, directoryHint: .isDirectory)
    }

    /// A record for one session.
    ///
    /// - Parameters:
    ///   - title: The meeting's title.
    ///   - status: Where the session stands.
    ///   - started: When the meeting began.
    ///   - retention: What the meeting was asked to keep of its audio.
    /// - Returns: The record.
    private func metadata(
        title: String,
        status: SessionRecoveryStatus,
        started: Date? = nil,
        retention: AudioRetentionMode? = nil
    ) -> SessionRecoveryMetadata {
        let layout = SessionArtifactLayout(directory: destination)
        return SessionRecoveryMetadata(
            sessionID: UUID(),
            title: title,
            startedAt: started ?? startedAt,
            sourceNames: ["QuickTime Player"],
            localeIdentifier: "en-US",
            audioRetention: retention,
            audioPath: retention.flatMap { layout.audioURL(for: $0)?.lastPathComponent },
            status: status,
            endedAt: status == .completed || status == .failed
                ? (started ?? startedAt).addingTimeInterval(120)
                : nil
        )
    }

    /// A service over an in-memory save folder.
    ///
    /// - Parameter store: The folder's contents.
    /// - Returns: The service and the access double it balances.
    private func makeService(_ store: FakeHistoryStore) -> (HistoryService, FakeSecurityScopedAccess) {
        let access = FakeSecurityScopedAccess()
        return (HistoryService(store: store, access: access), access)
    }

    // MARK: - Discovery

    @Test("Every recorded session in the folder is listed, newest first")
    func listsEverySession() async throws {
        let store = FakeHistoryStore()
        for (index, name) in ["2026-08-29-first", "2026-08-29-second", "2026-08-29-third"].enumerated() {
            try store.addSession(
                directory(name),
                in: destination,
                metadata: metadata(
                    title: name,
                    status: .completed,
                    started: startedAt.addingTimeInterval(Double(index) * 3_600)
                ),
                transcript: TranscriptFixture.transcript(title: name, texts: ["Something was said."])
            )
        }
        let (service, access) = makeService(store)

        let report = try await service.load(destination)

        #expect(report.sessions.map(\.title) == ["2026-08-29-third", "2026-08-29-second", "2026-08-29-first"])
        #expect(report.problems.isEmpty)
        #expect(access.isBalanced)
        #expect(access.started == [destination])
    }

    @Test("A session carries its recorded metadata and the paths of its files")
    func sessionCarriesItsMetadata() async throws {
        let store = FakeHistoryStore()
        let session = directory("2026-08-29-closures-walkthrough")
        let record = metadata(title: "Closures Walkthrough", status: .completed, retention: .compressed)
        try store.addSession(
            session,
            in: destination,
            metadata: record,
            transcript: TranscriptFixture.transcript(texts: ["A closure captures the variables it refers to."]),
            transcriptInfo: SessionFileInfo(byteCount: 613, modifiedAt: startedAt.addingTimeInterval(120))
        )
        store.addFile(
            SessionFileInfo(byteCount: 2_391_327, modifiedAt: startedAt.addingTimeInterval(120)),
            at: session.appending(path: "audio.m4a", directoryHint: .notDirectory)
        )
        let (service, _) = makeService(store)

        let found = try #require(try await service.load(destination).sessions.first)

        #expect(found.title == "Closures Walkthrough")
        #expect(found.sessionID == record.sessionID)
        #expect(found.status == .completed)
        #expect(found.startedAt == startedAt)
        #expect(found.endedAt == startedAt.addingTimeInterval(120))
        #expect(found.duration == 120)
        #expect(found.sourceNames == ["QuickTime Player"])
        #expect(found.localeIdentifier == "en-US")
        #expect(found.transcript.byteCount == 613)
        #expect(found.transcriptURL.path(percentEncoded: false)
                == "/Users/example/Meetings/2026-08-29-closures-walkthrough/transcript.md")
        #expect(found.audio?.url.lastPathComponent == "audio.m4a")
        #expect(found.audio?.format == .compressed)
        #expect(found.audio?.file.byteCount == 2_391_327)
        #expect(!found.isLegacy)
    }

    @Test("Every status ScribeKit records is shown, and named honestly",
          arguments: [
            (SessionRecoveryStatus.completed, HistorySessionStatus.completed),
            (.failed, .failed),
            (.interrupted, .interrupted),
            (.inProgress, .inProgress)
          ])
    func everyRecordedStatusIsShown(
        recorded: SessionRecoveryStatus,
        expected: HistorySessionStatus
    ) async throws {
        let store = FakeHistoryStore()
        try store.addSession(
            directory("2026-08-29-status"),
            in: destination,
            metadata: metadata(title: "Status", status: recorded),
            transcript: TranscriptFixture.transcript(texts: ["Whatever happened, happened."])
        )
        let (service, _) = makeService(store)

        let found = try #require(try await service.load(destination).sessions.first)

        #expect(found.status == expected)
    }

    @Test("A failed meeting's usable transcript is offered rather than hidden")
    func failedSessionIsSurfaced() async throws {
        let store = FakeHistoryStore()
        try store.addSession(
            directory("2026-08-29-failed"),
            in: destination,
            metadata: metadata(title: "Failed Meeting", status: .failed),
            transcript: TranscriptFixture.transcript(texts: ["Everything said before the disk filled up."])
        )
        let (service, _) = makeService(store)

        let report = try await service.load(destination)
        let found = try #require(report.sessions.first)

        #expect(found.status == .failed)
        #expect(report.documents.first?.spans.map(\.text) == ["Everything said before the disk filled up."])
        #expect(report.problems.isEmpty)
    }

    @Test("Recordings are recognised by the file that is actually there",
          arguments: [
            (AudioRetentionMode.raw, "audio.caf", HistoryAudioFormat.raw),
            (.compressed, "audio.m4a", .compressed)
          ])
    func audioFormatsAreMapped(
        mode: AudioRetentionMode,
        fileName: String,
        format: HistoryAudioFormat
    ) async throws {
        let store = FakeHistoryStore()
        let session = directory("2026-08-29-with-audio")
        try store.addSession(
            session,
            in: destination,
            metadata: metadata(title: "With Audio", status: .completed, retention: mode),
            transcript: TranscriptFixture.transcript(texts: ["Recorded."])
        )
        store.addFile(
            SessionFileInfo(byteCount: 4_096, modifiedAt: nil),
            at: session.appending(path: fileName, directoryHint: .notDirectory)
        )
        let (service, _) = makeService(store)

        let found = try #require(try await service.load(destination).sessions.first)

        #expect(found.audio?.format == format)
        #expect(found.audio?.url.lastPathComponent == fileName)
        #expect(!found.isMissingExpectedAudio)
    }

    @Test("A meeting that kept no audio offers none")
    func noAudioSessionHasNoAudio() async throws {
        let store = FakeHistoryStore()
        try store.addSession(
            directory("2026-08-29-no-audio"),
            in: destination,
            metadata: metadata(title: "No Audio", status: .completed, retention: AudioRetentionMode.none),
            transcript: TranscriptFixture.transcript(texts: ["Only words."])
        )
        let (service, _) = makeService(store)

        let found = try #require(try await service.load(destination).sessions.first)

        #expect(found.audio == nil)
        #expect(!found.isMissingExpectedAudio)
    }

    @Test("A record naming a recording that is not there says so")
    func missingExpectedAudioIsReported() async throws {
        let store = FakeHistoryStore()
        try store.addSession(
            directory("2026-08-29-lost-audio"),
            in: destination,
            metadata: metadata(title: "Lost Audio", status: .interrupted, retention: .raw),
            transcript: TranscriptFixture.transcript(texts: ["Started, then stopped."])
        )
        let (service, _) = makeService(store)

        let found = try #require(try await service.load(destination).sessions.first)

        #expect(found.audio == nil)
        #expect(found.isMissingExpectedAudio)
    }

    // MARK: - Damaged and unreadable sessions

    @Test("A damaged record is reported and the healthy sessions still load")
    func malformedRecordDoesNotBlockTheRest() async throws {
        let store = FakeHistoryStore()
        let broken = directory("2026-08-29-broken")
        try store.addSession(
            directory("2026-08-29-healthy"),
            in: destination,
            metadata: metadata(title: "Healthy", status: .completed),
            transcript: TranscriptFixture.transcript(texts: ["This one is fine."])
        )
        let damaged = Data("{ \"schemaVersion\": 1, \"title\": ".utf8)
        try store.addSession(
            broken,
            in: destination,
            rawMetadata: damaged,
            transcript: TranscriptFixture.transcript(texts: ["This one has a damaged record."])
        )
        let (service, _) = makeService(store)

        let report = try await service.load(destination)

        #expect(report.sessions.map(\.title) == ["Healthy"])
        #expect(report.problems.map(\.name) == ["2026-08-29-broken"])
        #expect(report.problems.first?.error == .metadataMalformed)
        #expect(store.storedBytes(in: broken) == damaged)
    }

    @Test("A record from a newer ScribeKit is reported, not guessed at")
    func unsupportedSchemaIsReported() async throws {
        let store = FakeHistoryStore()
        let future = directory("2026-08-29-from-the-future")
        let record = SessionRecoveryMetadata(
            schemaVersion: 99,
            sessionID: UUID(),
            title: "Later Format",
            startedAt: startedAt,
            sourceNames: [],
            localeIdentifier: "en-US",
            status: .completed
        )
        try store.addSession(
            future,
            in: destination,
            metadata: record,
            transcript: TranscriptFixture.transcript(texts: ["Written by a later build."])
        )
        try store.addSession(
            directory("2026-08-29-healthy"),
            in: destination,
            metadata: metadata(title: "Healthy", status: .completed),
            transcript: TranscriptFixture.transcript(texts: ["This one is fine."])
        )
        let (service, _) = makeService(store)

        let report = try await service.load(destination)

        #expect(report.sessions.map(\.title) == ["Healthy"])
        #expect(report.problems.first?.error == .unsupportedSchemaVersion(99))
        #expect(store.storedBytes(in: future) == (try record.encoded()))
    }

    @Test("A record naming a transcript that is not there is reported, not invented")
    func missingTranscriptIsReported() async throws {
        let store = FakeHistoryStore()
        try store.addSession(
            directory("2026-08-29-no-transcript"),
            in: destination,
            metadata: metadata(title: "No Transcript", status: .completed),
            transcript: nil
        )
        let (service, _) = makeService(store)

        let report = try await service.load(destination)

        #expect(report.sessions.isEmpty)
        #expect(report.problems.map(\.error) == [.transcriptMissing])
    }

    @Test("A transcript that cannot be read is reported")
    func unreadableTranscriptIsReported() async throws {
        let store = FakeHistoryStore()
        let session = directory("2026-08-29-unreadable")
        try store.addSession(
            session,
            in: destination,
            metadata: metadata(title: "Unreadable", status: .completed),
            transcript: TranscriptFixture.transcript(texts: ["Never read."])
        )
        store.makeTranscriptUnreadable(at: SessionArtifactLayout(directory: session).transcriptURL)
        let (service, _) = makeService(store)

        let report = try await service.load(destination)

        #expect(report.sessions.isEmpty)
        #expect(report.problems.map(\.error) == [.transcriptUnreadable])
    }

    @Test("A record that cannot be read is reported")
    func unreadableRecordIsReported() async throws {
        let store = FakeHistoryStore()
        let session = directory("2026-08-29-locked-record")
        try store.addSession(
            session,
            in: destination,
            metadata: metadata(title: "Locked", status: .completed),
            transcript: TranscriptFixture.transcript(texts: ["Fine."])
        )
        store.makeMetadataUnreadable(at: SessionArtifactLayout(directory: session).metadataURL)
        let (service, _) = makeService(store)

        let report = try await service.load(destination)

        #expect(report.sessions.isEmpty)
        #expect(report.problems.map(\.error) == [.metadataUnreadable])
    }

    @Test("A save folder that cannot be listed is reported rather than replaced")
    func unavailableDestinationIsReported() async throws {
        let store = FakeHistoryStore()
        store.failListing()
        let (service, access) = makeService(store)

        await #expect(throws: HistoryError.destinationUnavailable) {
            try await service.load(destination)
        }
        #expect(access.isBalanced)
    }

    @Test("A folder macOS refuses access to is reported as unavailable")
    func refusedAccessIsReported() async throws {
        let store = FakeHistoryStore()
        let service = HistoryService(store: store, access: FakeSecurityScopedAccess(isGranted: false))

        await #expect(throws: HistoryError.destinationUnavailable) {
            try await service.load(destination)
        }
    }

    // MARK: - Legacy and foreign directories

    @Test("A ScribeKit transcript with no record is offered with limited metadata")
    func legacyTranscriptIsDiscovered() async throws {
        let store = FakeHistoryStore()
        try store.addSession(
            directory("2026-08-29-before-records"),
            in: destination,
            metadata: nil,
            transcript: TranscriptFixture.transcript(
                title: "Before Records Existed",
                sourceNames: ["Microsoft Teams"],
                texts: ["Written by an earlier ScribeKit."]
            ),
            transcriptInfo: SessionFileInfo(byteCount: 402, modifiedAt: startedAt)
        )
        let (service, _) = makeService(store)

        let report = try await service.load(destination)
        let found = try #require(report.sessions.first)

        #expect(found.title == "Before Records Existed")
        #expect(found.status == .unrecorded)
        #expect(found.isLegacy)
        #expect(found.sessionID == nil)
        #expect(found.startedAt == nil)
        #expect(found.endedAt == nil)
        #expect(found.duration == nil)
        #expect(found.sourceNames == ["Microsoft Teams"])
        #expect(found.localeIdentifier == "en-US")
        #expect(found.sortDate == startedAt)
        #expect(report.documents.first?.spans.map(\.text) == ["Written by an earlier ScribeKit."])
    }

    @Test("A recording beside a transcript with no record is still found")
    func legacyAudioIsFound() async throws {
        let store = FakeHistoryStore()
        let session = directory("2026-08-29-legacy-audio")
        try store.addSession(
            session,
            in: destination,
            metadata: nil,
            transcript: TranscriptFixture.transcript(texts: ["Said aloud."])
        )
        store.addFile(
            SessionFileInfo(byteCount: 8_192, modifiedAt: nil),
            at: session.appending(path: "audio.caf", directoryHint: .notDirectory)
        )
        let (service, _) = makeService(store)

        let found = try #require(try await service.load(destination).sessions.first)

        #expect(found.audio?.format == .raw)
        #expect(!found.isMissingExpectedAudio)
    }

    @Test("Markdown ScribeKit did not write is not listed as a meeting")
    func foreignMarkdownIsNotAMeeting() async throws {
        let store = FakeHistoryStore()
        try store.addSession(
            directory("shopping-lists"),
            in: destination,
            metadata: nil,
            transcript: "# Shopping List\n\n- Milk\n- Bread\n"
        )
        try store.addSession(
            directory("2026-08-29-real"),
            in: destination,
            metadata: metadata(title: "Real Meeting", status: .completed),
            transcript: TranscriptFixture.transcript(texts: ["A real meeting."])
        )
        let (service, _) = makeService(store)

        let report = try await service.load(destination)

        #expect(report.sessions.map(\.title) == ["Real Meeting"])
        #expect(report.problems.isEmpty)
    }

    @Test("A directory with nothing of ScribeKit's in it is passed over in silence")
    func unrelatedDirectoryIsIgnored() async throws {
        let store = FakeHistoryStore()
        store.addDirectory(directory("holiday-photos"), in: destination)
        let (service, _) = makeService(store)

        let report = try await service.load(destination)

        #expect(report.isEmpty)
    }

    // MARK: - Ordering and repeatability

    @Test("Two loads of the same folder produce the same list in the same order")
    func loadsAreRepeatable() async throws {
        let store = FakeHistoryStore()
        for name in ["b-session", "a-session", "c-session"] {
            try store.addSession(
                directory(name),
                in: destination,
                metadata: metadata(title: name, status: .completed, started: startedAt),
                transcript: TranscriptFixture.transcript(title: name, texts: ["Same start time."])
            )
        }
        let (service, _) = makeService(store)

        let first = try await service.load(destination)
        let second = try await service.load(destination)

        #expect(first == second)
        #expect(first.sessions.map(\.title) == ["a-session", "b-session", "c-session"])
    }

    @Test("A load reads each transcript exactly once")
    func eachTranscriptIsReadOnce() async throws {
        let store = FakeHistoryStore()
        for name in ["one", "two", "three"] {
            try store.addSession(
                directory(name),
                in: destination,
                metadata: metadata(title: name, status: .completed),
                transcript: TranscriptFixture.transcript(title: name, texts: ["Text."])
            )
        }
        let (service, _) = makeService(store)

        _ = try await service.load(destination)

        #expect(store.readCount == 3)
    }
}
