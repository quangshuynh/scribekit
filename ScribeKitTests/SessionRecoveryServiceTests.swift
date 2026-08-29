//
//  SessionRecoveryServiceTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@Suite("SessionRecoveryService")
struct SessionRecoveryServiceTests {

    private let destination = URL(filePath: "/Users/example/Meetings", directoryHint: .isDirectory)
    private let zone = TimeZone(identifier: "America/New_York")!

    /// 31 August 2026, 15:00:00 UTC.
    private let startedAt = Date(timeIntervalSince1970: 1_788_188_400)

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
    /// - Returns: The record.
    private func metadata(
        title: String,
        status: SessionRecoveryStatus,
        started: Date? = nil
    ) -> SessionRecoveryMetadata {
        SessionRecoveryMetadata(
            sessionID: UUID(),
            title: title,
            startedAt: started ?? startedAt,
            sourceNames: ["Microsoft Teams"],
            localeIdentifier: "en-US",
            status: status
        )
    }

    /// A service over an in-memory save folder.
    ///
    /// - Parameter store: The folder's contents.
    /// - Returns: The service and the access double it balances.
    private func makeService(
        _ store: FakeSessionRecoveryStore
    ) -> (SessionRecoveryService, FakeSecurityScopedAccess) {
        let access = FakeSecurityScopedAccess()
        return (SessionRecoveryService(store: store, access: access, timeZone: zone), access)
    }

    // MARK: - Discovery

    @Test("A session left in progress is offered, with its own title and paths")
    func inProgressSessionIsDiscovered() async throws {
        let store = FakeSessionRecoveryStore()
        let session = directory("2026-08-31-ios-training-day-2")
        let record = metadata(title: "iOS Training - Day 2", status: .inProgress)
        try store.addSession(
            session,
            in: destination,
            metadata: record,
            transcript: TranscriptFileInfo(byteCount: 413, modifiedAt: startedAt.addingTimeInterval(600))
        )
        let (service, _) = makeService(store)

        let report = try await service.scan(destination)

        #expect(report.candidates.count == 1)
        let candidate = try #require(report.candidates.first)
        #expect(candidate.metadata.title == "iOS Training - Day 2")
        #expect(candidate.id == record.sessionID)
        #expect(candidate.layout.directory == session)
        #expect(candidate.transcriptURL.path(percentEncoded: false)
                == "/Users/example/Meetings/2026-08-31-ios-training-day-2/transcript.md")
        #expect(candidate.transcript.byteCount == 413)
        #expect(candidate.destination == destination)
        #expect(report.problems.isEmpty)
    }

    @Test("A session ScribeKit closed is not offered as unfinished",
          arguments: [SessionRecoveryStatus.completed, .failed, .interrupted])
    func closedSessionsAreNotOffered(status: SessionRecoveryStatus) async throws {
        let store = FakeSessionRecoveryStore()
        try store.addSession(
            directory("2026-08-31-closures-walkthrough"),
            in: destination,
            metadata: metadata(title: "Closures Walkthrough", status: status)
        )
        let (service, _) = makeService(store)

        let report = try await service.scan(destination)

        #expect(report.isEmpty)
    }

    @Test("A directory ScribeKit never recorded is passed over in silence")
    func directoriesWithoutRecordsAreIgnored() async throws {
        let store = FakeSessionRecoveryStore()
        try store.addSession(directory("holiday-photos"), in: destination, metadata: nil, transcript: nil)
        let (service, _) = makeService(store)

        let report = try await service.scan(destination)

        #expect(report.isEmpty)
    }

    @Test("Unfinished sessions are ordered newest first, deterministically")
    func multipleCandidatesAreOrdered() async throws {
        let store = FakeSessionRecoveryStore()
        try store.addSession(
            directory("2026-08-31-first"),
            in: destination,
            metadata: metadata(title: "First", status: .inProgress, started: startedAt)
        )
        try store.addSession(
            directory("2026-08-31-third"),
            in: destination,
            metadata: metadata(title: "Third", status: .inProgress,
                               started: startedAt.addingTimeInterval(7_200))
        )
        try store.addSession(
            directory("2026-08-31-second"),
            in: destination,
            metadata: metadata(title: "Second", status: .inProgress,
                               started: startedAt.addingTimeInterval(3_600))
        )
        let (service, _) = makeService(store)

        let report = try await service.scan(destination)

        #expect(report.candidates.map(\.metadata.title) == ["Third", "Second", "First"])
        let again = try await service.scan(destination)
        #expect(again.candidates.map(\.metadata.title) == report.candidates.map(\.metadata.title))
    }

    @Test("Candidates found together stay separate sessions")
    func candidatesAreNotMerged() async throws {
        let store = FakeSessionRecoveryStore()
        try store.addSession(
            directory("2026-08-31-a"),
            in: destination,
            metadata: metadata(title: "A", status: .inProgress, started: startedAt)
        )
        try store.addSession(
            directory("2026-08-31-b"),
            in: destination,
            metadata: metadata(title: "B", status: .inProgress, started: startedAt.addingTimeInterval(60))
        )
        let (service, _) = makeService(store)

        let report = try await service.scan(destination)

        #expect(Set(report.candidates.map(\.layout.directory)).count == 2)
        #expect(Set(report.candidates.map(\.id)).count == 2)
    }

    // MARK: - Damaged records

    @Test("A damaged record is reported and its bytes are left exactly as they were")
    func malformedRecordIsReportedNotRepaired() async throws {
        let store = FakeSessionRecoveryStore()
        let session = directory("2026-08-31-damaged")
        let bytes = Data(#"{"schemaVersion": 1, "title": "#.utf8)
        try store.addSession(session, in: destination, rawMetadata: bytes)
        let (service, _) = makeService(store)

        let report = try await service.scan(destination)

        #expect(report.candidates.isEmpty)
        #expect(report.problems.map(\.error) == [.metadataMalformed])
        #expect(report.problems.first?.directory == session)
        #expect(store.storedBytes(in: session) == bytes)
        #expect(store.writes.isEmpty)
    }

    @Test("A record from a newer ScribeKit is reported as unsupported and left alone")
    func unknownSchemaVersionIsReported() async throws {
        let store = FakeSessionRecoveryStore()
        let session = directory("2026-08-31-from-the-future")
        let bytes = try metadata(title: "Later", status: .inProgress).encoded()
            .replacing(Data("\"schemaVersion\" : 1".utf8), with: Data("\"schemaVersion\" : 9".utf8))
        try store.addSession(session, in: destination, rawMetadata: bytes)
        let (service, _) = makeService(store)

        let report = try await service.scan(destination)

        #expect(report.problems.map(\.error) == [.unsupportedSchemaVersion(9)])
        #expect(store.storedBytes(in: session) == bytes)
        #expect(store.writes.isEmpty)
    }

    @Test("A record naming a transcript that is not there is reported as inconsistent")
    func missingTranscriptIsReported() async throws {
        let store = FakeSessionRecoveryStore()
        let session = directory("2026-08-31-no-transcript")
        try store.addSession(
            session,
            in: destination,
            metadata: metadata(title: "Missing", status: .inProgress),
            transcript: nil
        )
        let (service, _) = makeService(store)

        let report = try await service.scan(destination)

        #expect(report.candidates.isEmpty)
        #expect(report.problems.map(\.error) == [.transcriptMissing])
        #expect(store.appends.isEmpty)
        #expect(store.writes.isEmpty)
    }

    @Test("A transcript that cannot be read is reported rather than replaced")
    func unreadableTranscriptIsReported() async throws {
        let store = FakeSessionRecoveryStore()
        let session = directory("2026-08-31-unreadable")
        try store.addSession(session, in: destination, metadata: metadata(title: "Locked", status: .inProgress))
        store.makeTranscriptUnreadable(at: SessionArtifactLayout(directory: session).transcriptURL)
        let (service, _) = makeService(store)

        let report = try await service.scan(destination)

        #expect(report.problems.map(\.error) == [.transcriptUnreadable])
        #expect(store.appends.isEmpty)
    }

    @Test("One damaged record does not hide a healthy unfinished session beside it")
    func damageDoesNotHideOtherSessions() async throws {
        let store = FakeSessionRecoveryStore()
        try store.addSession(directory("2026-08-31-a-damaged"), in: destination, rawMetadata: Data("{".utf8))
        try store.addSession(
            directory("2026-08-31-b-healthy"),
            in: destination,
            metadata: metadata(title: "Healthy", status: .inProgress)
        )
        let (service, _) = makeService(store)

        let report = try await service.scan(destination)

        #expect(report.candidates.map(\.metadata.title) == ["Healthy"])
        #expect(report.problems.count == 1)
    }

    // MARK: - Inaccessible destinations

    @Test("A save folder that cannot be listed is reported, not replaced with another")
    func unlistableDestinationIsReported() async {
        let store = FakeSessionRecoveryStore()
        store.failListing()
        let (service, _) = makeService(store)

        await #expect(throws: SessionRecoveryError.destinationUnavailable) {
            try await service.scan(destination)
        }
    }

    @Test("A save folder macOS will not open is reported as unavailable")
    func refusedAccessIsReported() async {
        let store = FakeSessionRecoveryStore()
        let access = FakeSecurityScopedAccess(isGranted: false)
        let service = SessionRecoveryService(store: store, access: access, timeZone: zone)

        await #expect(throws: SessionRecoveryError.destinationUnavailable) {
            try await service.scan(destination)
        }
        #expect(access.started.isEmpty)
        #expect(access.stopped.isEmpty)
    }

    @Test("A missing session directory fails safely rather than crashing")
    func missingSessionDirectoryIsSafe() async throws {
        let store = FakeSessionRecoveryStore()
        let session = directory("2026-08-31-vanished")
        try store.addSession(session, in: destination, metadata: metadata(title: "Gone", status: .inProgress))
        let (service, _) = makeService(store)
        let report = try await service.scan(destination)
        let candidate = try #require(report.candidates.first)

        let emptied = FakeSessionRecoveryStore()
        let (afterRemoval, _) = makeService(emptied)

        #expect(try await afterRemoval.scan(destination).isEmpty)
        await #expect(throws: SessionRecoveryError.metadataMissing) {
            try await afterRemoval.recordInterruption(for: candidate)
        }
    }

    // MARK: - Access lifetime

    @Test("A scan opens access to the save folder and closes it again")
    func scanBalancesAccess() async throws {
        let store = FakeSessionRecoveryStore()
        try store.addSession(
            directory("2026-08-31-training"),
            in: destination,
            metadata: metadata(title: "Training", status: .inProgress)
        )
        let (service, access) = makeService(store)

        _ = try await service.scan(destination)

        #expect(access.started == [destination])
        #expect(access.stopped == [destination])
        #expect(access.isBalanced)
    }

    @Test("Access is closed again even when the scan fails")
    func failedScanBalancesAccess() async {
        let store = FakeSessionRecoveryStore()
        store.failListing()
        let (service, access) = makeService(store)

        _ = try? await service.scan(destination)

        #expect(access.isBalanced)
        #expect(access.started == [destination])
    }

    // MARK: - Inspection is read-only

    @Test("Looking for unfinished meetings writes nothing at all")
    func scanningNeverWrites() async throws {
        let store = FakeSessionRecoveryStore()
        let healthy = directory("2026-08-31-healthy")
        let damaged = directory("2026-08-31-damaged")
        let done = directory("2026-08-31-done")
        try store.addSession(healthy, in: destination, metadata: metadata(title: "Healthy", status: .inProgress))
        try store.addSession(damaged, in: destination, rawMetadata: Data("not json".utf8))
        try store.addSession(done, in: destination, metadata: metadata(title: "Done", status: .completed))
        let before = [healthy, damaged, done].map { store.storedBytes(in: $0) }
        let (service, _) = makeService(store)

        _ = try await service.scan(destination)
        _ = try await service.scan(destination)

        #expect(store.writes.isEmpty)
        #expect(store.appends.isEmpty)
        #expect([healthy, damaged, done].map { store.storedBytes(in: $0) } == before)
    }

    // MARK: - Recording an interruption

    @Test("Recording an interruption marks the record and notes it in the transcript once")
    func recordingAnInterruption() async throws {
        let store = FakeSessionRecoveryStore()
        let session = directory("2026-08-31-training")
        try store.addSession(session, in: destination, metadata: metadata(title: "Training", status: .inProgress))
        let (service, access) = makeService(store)
        let candidate = try #require(try await service.scan(destination).candidates.first)
        let noticed = startedAt.addingTimeInterval(86_400)

        let updated = try await service.recordInterruption(for: candidate, at: noticed)

        #expect(updated.status == .interrupted)
        #expect(updated.interruptedAt == noticed)
        #expect(store.storedMetadata(in: session)?.status == .interrupted)
        #expect(store.appends.count == 1)
        #expect(store.appends.first?.url == candidate.transcriptURL)
        #expect(access.isBalanced)
    }

    @Test("The note states what is known and invents neither a time nor a duration")
    func theNoteInventsNothing() async throws {
        let store = FakeSessionRecoveryStore()
        let session = directory("2026-08-31-training")
        try store.addSession(session, in: destination, metadata: metadata(title: "Training", status: .inProgress))
        let (service, _) = makeService(store)
        let candidate = try #require(try await service.scan(destination).candidates.first)

        _ = try await service.recordInterruption(for: candidate, at: startedAt)
        let note = try #require(store.appends.first?.text)

        #expect(note.contains("Session interrupted."))
        #expect(note.contains("When it stopped is not known"))
        #expect(note.hasPrefix("---\n\n> "))
        #expect(!note.contains("seconds"))
        #expect(!note.contains("Duration"))
        #expect(!note.contains("Ended"))
    }

    @Test("A session already recorded as interrupted is not annotated a second time")
    func recordingIsNotRepeated() async throws {
        let store = FakeSessionRecoveryStore()
        let session = directory("2026-08-31-training")
        try store.addSession(session, in: destination, metadata: metadata(title: "Training", status: .inProgress))
        let (service, _) = makeService(store)
        let candidate = try #require(try await service.scan(destination).candidates.first)

        _ = try await service.recordInterruption(for: candidate, at: startedAt)
        let second = try await service.recordInterruption(for: candidate, at: startedAt.addingTimeInterval(60))

        #expect(second.interruptedAt == startedAt)
        #expect(store.appends.count == 1)
        #expect(store.writes.count == 1)
    }

    @Test("A record that cannot be updated leaves the transcript untouched")
    func failedRecordUpdateLeavesTheTranscriptAlone() async throws {
        let store = FakeSessionRecoveryStore()
        let session = directory("2026-08-31-training")
        try store.addSession(session, in: destination, metadata: metadata(title: "Training", status: .inProgress))
        let (service, access) = makeService(store)
        let candidate = try #require(try await service.scan(destination).candidates.first)
        store.failWrites()

        await #expect(throws: SessionRecoveryError.metadataWriteFailed) {
            try await service.recordInterruption(for: candidate, at: startedAt)
        }
        #expect(store.appends.isEmpty)
        #expect(store.storedMetadata(in: session)?.status == .inProgress)
        #expect(access.isBalanced)
    }

    @Test("A note that cannot be appended is reported, and cannot be appended twice later")
    func failedAnnotationIsReported() async throws {
        let store = FakeSessionRecoveryStore()
        let session = directory("2026-08-31-training")
        try store.addSession(session, in: destination, metadata: metadata(title: "Training", status: .inProgress))
        let (service, _) = makeService(store)
        let candidate = try #require(try await service.scan(destination).candidates.first)
        store.failAppends()

        await #expect(throws: SessionRecoveryError.transcriptAnnotationFailed) {
            try await service.recordInterruption(for: candidate, at: startedAt)
        }
        #expect(store.storedMetadata(in: session)?.status == .interrupted)
        #expect(store.appends.isEmpty)
        #expect(try await service.scan(destination).isEmpty)
    }

    @Test("A session whose transcript has gone is not annotated or re-recorded")
    func interruptionNeedsItsTranscript() async throws {
        let store = FakeSessionRecoveryStore()
        let session = directory("2026-08-31-training")
        try store.addSession(session, in: destination, metadata: metadata(title: "Training", status: .inProgress))
        let (service, _) = makeService(store)
        let candidate = try #require(try await service.scan(destination).candidates.first)

        let withoutTranscript = FakeSessionRecoveryStore()
        try withoutTranscript.addSession(
            session,
            in: destination,
            metadata: metadata(title: "Training", status: .inProgress),
            transcript: nil
        )
        let (afterLoss, _) = makeService(withoutTranscript)

        await #expect(throws: SessionRecoveryError.transcriptMissing) {
            try await afterLoss.recordInterruption(for: candidate, at: startedAt)
        }
        #expect(withoutTranscript.writes.isEmpty)
        #expect(withoutTranscript.appends.isEmpty)
    }
}
