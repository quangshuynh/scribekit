//
//  HistoryModelTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// A remembered save folder, without a bookmark or the sandbox.
private nonisolated final class FakeHistorySaveLocation: SaveLocationPersisting, @unchecked Sendable {
    var restoreOutcome: Result<URL?, Error> = .success(nil)
    private(set) var restoreCount = 0

    init(folder: URL? = nil) {
        restoreOutcome = .success(folder)
    }

    func save(_ url: URL) throws {}

    func restore() throws -> URL? {
        restoreCount += 1
        return try restoreOutcome.get()
    }

    func clear() throws {}
}

@MainActor
@Suite("HistoryModel")
struct HistoryModelTests {

    private let destination = URL(filePath: "/Users/example/Meetings", directoryHint: .isDirectory)

    /// A session directory inside the save folder.
    private func directory(_ name: String) -> URL {
        destination.appending(path: name, directoryHint: .isDirectory)
    }

    /// A store holding two meetings with different words in them.
    private func makeStore() throws -> FakeHistoryStore {
        let store = FakeHistoryStore()
        try store.addSession(
            directory("2026-08-29-closures-walkthrough"),
            in: destination,
            metadata: SessionRecoveryMetadata(
                sessionID: UUID(),
                title: "Closures Walkthrough",
                startedAt: TranscriptFixture.startedAt,
                sourceNames: ["QuickTime Player"],
                localeIdentifier: "en-US",
                status: .completed,
                endedAt: TranscriptFixture.startedAt.addingTimeInterval(120)
            ),
            transcript: TranscriptFixture.transcript(
                title: "Closures Walkthrough",
                texts: ["A closure captures the variables it refers to."]
            )
        )
        try store.addSession(
            directory("2026-08-29-standup"),
            in: destination,
            metadata: SessionRecoveryMetadata(
                sessionID: UUID(),
                title: "Standup",
                startedAt: TranscriptFixture.startedAt.addingTimeInterval(3_600),
                sourceNames: ["Microsoft Teams"],
                localeIdentifier: "en-US",
                status: .completed,
                endedAt: TranscriptFixture.startedAt.addingTimeInterval(3_720)
            ),
            transcript: TranscriptFixture.transcript(title: "Standup", texts: ["Nothing blocking today."])
        )
        return store
    }

    /// A model over an in-memory save folder.
    ///
    /// - Parameters:
    ///   - store: The folder's contents.
    ///   - remembersFolder: Whether a save folder is remembered at all.
    /// - Returns: The model, the bookmark double and the access double.
    private func makeModel(
        _ store: FakeHistoryStore,
        remembersFolder: Bool = true
    ) -> (HistoryModel, FakeHistorySaveLocation, FakeSecurityScopedAccess) {
        let access = FakeSecurityScopedAccess()
        let saveLocation = FakeHistorySaveLocation(folder: remembersFolder ? destination : nil)
        let model = HistoryModel(
            service: HistoryService(store: store, access: access),
            saveLocation: saveLocation
        )
        return (model, saveLocation, access)
    }

    @Test("Before a load, the screen has nothing to show")
    func startsUnloaded() throws {
        let (model, _, _) = makeModel(FakeHistoryStore())

        #expect(model.state == .unloaded)
        #expect(model.results.isEmpty)
        #expect(model.sessionCount == 0)
    }

    @Test("A load lists the save folder's meetings, newest first")
    func loadListsMeetings() async throws {
        let (model, saveLocation, access) = makeModel(try makeStore())

        await model.load()

        #expect(model.sessionCount == 2)
        #expect(model.results.map(\.session.title) == ["Standup", "Closures Walkthrough"])
        #expect(model.problems.isEmpty)
        #expect(model.destination == destination)
        #expect(saveLocation.restoreCount == 1)
        #expect(access.isBalanced)
    }

    @Test("Typing narrows the list without reading a file")
    func searchingReadsNoFiles() async throws {
        let store = try makeStore()
        let (model, _, _) = makeModel(store)
        await model.load()
        let readsAfterLoad = store.readCount

        model.query = "closure"
        #expect(model.results.map(\.session.title) == ["Closures Walkthrough"])

        model.query = "blocking"
        #expect(model.results.map(\.session.title) == ["Standup"])

        model.query = "helicopter"
        #expect(model.results.isEmpty)

        #expect(store.readCount == readsAfterLoad)
    }

    @Test("Clearing the search brings every meeting back")
    func clearingSearchRestoresEverything() async throws {
        let (model, _, _) = makeModel(try makeStore())
        await model.load()

        model.query = "closure"
        #expect(model.results.count == 1)

        model.query = ""
        #expect(model.results.count == 2)
    }

    @Test("A refresh replaces the listing rather than adding to it")
    func refreshReplacesTheListing() async throws {
        let store = try makeStore()
        let (model, _, _) = makeModel(store)
        await model.load()
        #expect(model.sessionCount == 2)

        await model.load()

        #expect(model.sessionCount == 2)
        #expect(model.results.map(\.session.title) == ["Standup", "Closures Walkthrough"])
    }

    @Test("With no folder remembered, the screen says so rather than looking elsewhere")
    func noDestinationIsReported() async throws {
        let (model, _, access) = makeModel(try makeStore(), remembersFolder: false)

        await model.load()

        #expect(model.unavailableMessage == HistoryError.noDestination.errorDescription)
        #expect(model.destination == nil)
        #expect(model.results.isEmpty)
        #expect(access.started.isEmpty)
    }

    @Test("A folder that cannot be listed is reported, and no meetings are invented")
    func unavailableFolderIsReported() async throws {
        let store = FakeHistoryStore()
        store.failListing()
        let (model, _, access) = makeModel(store)

        await model.load()

        #expect(model.unavailableMessage == HistoryError.destinationUnavailable.errorDescription)
        #expect(model.results.isEmpty)
        #expect(access.isBalanced)
    }

    @Test("A damaged session is surfaced beside the healthy ones")
    func problemsAreSurfaced() async throws {
        let store = try makeStore()
        try store.addSession(
            directory("2026-08-29-damaged"),
            in: destination,
            rawMetadata: Data("{ not json".utf8),
            transcript: TranscriptFixture.transcript(texts: ["Unreachable."])
        )
        let (model, _, _) = makeModel(store)

        await model.load()

        #expect(model.sessionCount == 2)
        #expect(model.problems.map(\.name) == ["2026-08-29-damaged"])
        #expect(model.problems.first?.error == .metadataMalformed)
    }

    @Test("The detail pane finds the text of the meeting that is selected")
    func documentLookup() async throws {
        let (model, _, _) = makeModel(try makeStore())
        await model.load()

        let document = try #require(model.document(for: directory("2026-08-29-standup")))

        #expect(document.session.title == "Standup")
        #expect(document.spans.map(\.text) == ["Nothing blocking today."])
        #expect(model.document(for: directory("nothing-here")) == nil)
    }
}
