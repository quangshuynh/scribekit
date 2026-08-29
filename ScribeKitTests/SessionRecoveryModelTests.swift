//
//  SessionRecoveryModelTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@MainActor
@Suite("SessionRecoveryModel")
struct SessionRecoveryModelTests {

    private let destination = URL(filePath: "/Users/example/Meetings", directoryHint: .isDirectory)

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
    /// - Returns: The record.
    private func metadata(title: String, status: SessionRecoveryStatus) -> SessionRecoveryMetadata {
        SessionRecoveryMetadata(
            sessionID: UUID(),
            title: title,
            startedAt: startedAt,
            sourceNames: ["QuickTime Player"],
            localeIdentifier: "en-US",
            status: status
        )
    }

    /// A model over an in-memory save folder.
    ///
    /// - Parameter store: The folder's contents.
    /// - Returns: The model.
    private func makeModel(_ store: FakeSessionRecoveryStore) -> SessionRecoveryModel {
        SessionRecoveryModel(service: SessionRecoveryService(
            store: store,
            access: FakeSecurityScopedAccess(),
            timeZone: TimeZone(identifier: "America/New_York")!
        ))
    }

    /// A save folder holding one unfinished meeting.
    ///
    /// - Returns: The store and the session's directory.
    private func folderWithOneUnfinishedMeeting() throws -> (FakeSessionRecoveryStore, URL) {
        let store = FakeSessionRecoveryStore()
        let session = directory("2026-08-31-ios-training-day-2")
        try store.addSession(
            session,
            in: destination,
            metadata: metadata(title: "iOS Training - Day 2", status: .inProgress)
        )
        return (store, session)
    }

    @Test("Nothing is claimed about a folder that has not been checked")
    func startsUnchecked() {
        let model = makeModel(FakeSessionRecoveryStore())

        #expect(model.state == .unchecked)
        #expect(!model.isVisible)
        #expect(model.candidates.isEmpty)
        #expect(model.problems.isEmpty)
    }

    @Test("A folder with nothing unfinished says nothing at all")
    func clearFolderIsSilent() async throws {
        let store = FakeSessionRecoveryStore()
        try store.addSession(
            directory("2026-08-31-done"),
            in: destination,
            metadata: metadata(title: "Done", status: .completed)
        )
        let model = makeModel(store)

        await model.check(destination)

        #expect(model.state == .clear)
        #expect(!model.isVisible)
        #expect(!model.hasFindings)
    }

    @Test("An unfinished meeting is offered with what is known about it")
    func unfinishedMeetingIsOffered() async throws {
        let (store, _) = try folderWithOneUnfinishedMeeting()
        let model = makeModel(store)

        await model.check(destination)

        #expect(model.isVisible)
        #expect(model.hasFindings)
        #expect(model.candidates.map(\.metadata.title) == ["iOS Training - Day 2"])
    }

    @Test("A save folder that cannot be opened is said to be unavailable, not empty")
    func unavailableFolderIsStated() async {
        let store = FakeSessionRecoveryStore()
        store.failListing()
        let model = makeModel(store)

        await model.check(destination)

        guard case let .unavailable(message) = model.state else {
            Issue.record("Expected the folder to be reported as unavailable")
            return
        }
        #expect(message.contains("could not"))
        #expect(model.isVisible)
        #expect(model.candidates.isEmpty)
    }

    @Test("A save folder that could not be restored is reported without looking anywhere else")
    func unrestorableFolderIsStated() {
        let model = makeModel(FakeSessionRecoveryStore())

        model.reportDestinationUnavailable("The saved folder could not be found.")

        #expect(model.state == .unavailable(message: "The saved folder could not be found."))
        #expect(model.isVisible)
    }

    @Test("Dismissing hides a meeting for this launch and changes nothing on disk")
    func dismissingChangesNothing() async throws {
        let (store, session) = try folderWithOneUnfinishedMeeting()
        let model = makeModel(store)
        await model.check(destination)
        let candidate = try #require(model.candidates.first)

        model.dismiss(candidate)

        #expect(model.candidates.isEmpty)
        #expect(!model.hasFindings)
        #expect(store.writes.isEmpty)
        #expect(store.appends.isEmpty)
        #expect(store.storedMetadata(in: session)?.status == .inProgress)
    }

    @Test("Recording an interruption marks the session and stops offering it")
    func recordingHidesAndMarks() async throws {
        let (store, session) = try folderWithOneUnfinishedMeeting()
        let model = makeModel(store)
        await model.check(destination)
        let candidate = try #require(model.candidates.first)

        await model.recordInterruption(for: candidate)

        #expect(model.candidates.isEmpty)
        #expect(store.storedMetadata(in: session)?.status == .interrupted)
        #expect(store.appends.count == 1)
        let message = try #require(model.actionMessage)
        #expect(message.contains("iOS Training - Day 2"))
        #expect(message.contains("interrupted"))
    }

    @Test("A recovery that fails says so and keeps offering the meeting")
    func failedRecordingKeepsTheMeetingOffered() async throws {
        let (store, session) = try folderWithOneUnfinishedMeeting()
        let model = makeModel(store)
        await model.check(destination)
        let candidate = try #require(model.candidates.first)
        store.failWrites()

        await model.recordInterruption(for: candidate)

        #expect(model.candidates.count == 1)
        #expect(model.actionMessage != nil)
        #expect(store.storedMetadata(in: session)?.status == .inProgress)
        #expect(store.appends.isEmpty)
    }

    @Test("A damaged record is shown as a problem rather than as a recoverable meeting")
    func damagedRecordIsShownAsAProblem() async throws {
        let store = FakeSessionRecoveryStore()
        let session = directory("2026-08-31-damaged")
        try store.addSession(session, in: destination, rawMetadata: Data("{".utf8))
        let model = makeModel(store)

        await model.check(destination)

        #expect(model.candidates.isEmpty)
        #expect(model.problems.map(\.error) == [.metadataMalformed])
        #expect(model.problems.map(\.name) == ["2026-08-31-damaged"])
        #expect(model.isVisible)
    }

    @Test("Checking a folder again starts from what is on disk now")
    func recheckingReplacesTheReport() async throws {
        let (store, _) = try folderWithOneUnfinishedMeeting()
        let model = makeModel(store)
        await model.check(destination)
        #expect(model.hasFindings)

        await model.check(URL(filePath: "/Users/example/Elsewhere", directoryHint: .isDirectory))

        #expect(model.state == .clear)
        #expect(!model.hasFindings)
    }
}
