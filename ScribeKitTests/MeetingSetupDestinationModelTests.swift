//
//  MeetingSetupDestinationModelTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// Save-location storage with scripted outcomes, so restoration, replacement
/// and failure can be exercised without bookmarks, the sandbox or a real folder.
private nonisolated final class FakeSaveLocation: SaveLocationPersisting, @unchecked Sendable {
    var restoreOutcome: Result<URL?, Error> = .success(nil)
    var saveOutcome: Result<Void, Error> = .success(())
    var clearOutcome: Result<Void, Error> = .success(())

    private(set) var savedURLs: [URL] = []
    private(set) var clearCount = 0

    func save(_ url: URL) throws {
        try saveOutcome.get()
        savedURLs.append(url)
    }

    func restore() throws -> URL? {
        try restoreOutcome.get()
    }

    func clear() throws {
        try clearOutcome.get()
        clearCount += 1
    }
}

@MainActor
@Suite("MeetingSetupDestinationModel")
struct MeetingSetupDestinationModelTests {

    private let folder = URL(filePath: "/Users/example/Meetings", directoryHint: .isDirectory)
    private let otherFolder = URL(filePath: "/Users/example/Archive", directoryHint: .isDirectory)

    @Test("With nothing stored, no destination is offered")
    func startsWithoutDestination() {
        let storage = FakeSaveLocation()
        let model = MeetingSetupDestinationModel(persistence: storage)

        model.restore()

        #expect(model.state == .none)
        #expect(model.url == nil)
        #expect(!model.canClear)
        #expect(model.warningMessage == nil)
        #expect(model.pathDescription == MeetingSetupDestinationModel.emptyDescription)
    }

    @Test("A stored destination comes back as restored")
    func restoresStoredDestination() {
        let storage = FakeSaveLocation()
        storage.restoreOutcome = .success(folder)
        let model = MeetingSetupDestinationModel(persistence: storage)

        model.restore()

        #expect(model.state == .available(.init(url: folder, origin: .restored)))
        #expect(model.url == folder)
        #expect(model.isRestored)
        #expect(model.warningMessage == nil)
        #expect(model.canClear)
    }

    @Test("A destination that cannot be restored is reported, not replaced", arguments: [
        SaveLocationError.Reason.bookmarkResolutionFailed,
        .staleBookmarkNotRefreshed,
        .accessDenied,
        .directoryUnavailable,
        .malformedStoredData
    ])
    func reportsUnusableStoredDestination(reason: SaveLocationError.Reason) {
        let storage = FakeSaveLocation()
        let error = SaveLocationError(reason)
        storage.restoreOutcome = .failure(error)
        let model = MeetingSetupDestinationModel(persistence: storage)

        model.restore()

        #expect(model.state == .unavailable(message: error.errorDescription ?? ""))
        #expect(model.url == nil)
        #expect(model.warningMessage == error.errorDescription)
        #expect(model.canClear)
        #expect(model.pathDescription == MeetingSetupDestinationModel.emptyDescription)
    }

    @Test("Choosing a folder stores it and marks it as chosen here")
    func storesChosenFolder() {
        let storage = FakeSaveLocation()
        let model = MeetingSetupDestinationModel(persistence: storage)

        model.choose(folder)

        #expect(model.state == .available(.init(url: folder, origin: .chosen)))
        #expect(storage.savedURLs == [folder])
        #expect(!model.isRestored)
    }

    @Test("Choosing another folder replaces the first")
    func replacesDestination() {
        let storage = FakeSaveLocation()
        let model = MeetingSetupDestinationModel(persistence: storage)

        model.choose(folder)
        model.choose(otherFolder)

        #expect(model.url == otherFolder)
        #expect(storage.savedURLs == [folder, otherFolder])
    }

    @Test("A folder that cannot be remembered still works for this launch")
    func keepsUnstorableFolderForThisLaunch() {
        let storage = FakeSaveLocation()
        let error = SaveLocationError(.bookmarkCreationFailed)
        storage.saveOutcome = .failure(error)
        let model = MeetingSetupDestinationModel(persistence: storage)

        model.choose(folder)

        #expect(model.state == .persistenceFailed(url: folder, message: error.errorDescription ?? ""))
        #expect(model.url == folder)
        #expect(model.warningMessage == error.errorDescription)
        #expect(model.statusDescription.contains(folder.path(percentEncoded: false)))
        #expect(model.statusDescription.contains(error.errorDescription ?? ""))
    }

    @Test("Clearing forgets the destination")
    func clearsDestination() {
        let storage = FakeSaveLocation()
        let model = MeetingSetupDestinationModel(persistence: storage)
        model.choose(folder)

        model.clear()

        #expect(model.state == .none)
        #expect(model.url == nil)
        #expect(storage.clearCount == 1)
        #expect(!model.canClear)
    }

    @Test("A destination that cannot be forgotten is reported")
    func reportsFailureToClear() {
        let storage = FakeSaveLocation()
        let error = SaveLocationError(.malformedStoredData)
        storage.clearOutcome = .failure(error)
        let model = MeetingSetupDestinationModel(persistence: storage)
        model.choose(folder)

        model.clear()

        #expect(model.state == .persistenceFailed(url: nil, message: error.errorDescription ?? ""))
        #expect(model.url == nil)
        #expect(model.canClear)
    }

    @Test("An unusable stored destination can be replaced by choosing another")
    func recoversFromUnusableDestination() {
        let storage = FakeSaveLocation()
        storage.restoreOutcome = .failure(SaveLocationError(.accessDenied))
        let model = MeetingSetupDestinationModel(persistence: storage)
        model.restore()

        model.choose(folder)

        #expect(model.state == .available(.init(url: folder, origin: .chosen)))
        #expect(model.warningMessage == nil)
    }

    @Test("Every failure reason explains itself in words")
    func describesEveryReason() {
        let reasons: [SaveLocationError.Reason] = [
            .bookmarkCreationFailed, .bookmarkResolutionFailed, .staleBookmarkNotRefreshed,
            .accessDenied, .directoryUnavailable, .malformedStoredData
        ]
        for reason in reasons {
            let description = SaveLocationError(reason).errorDescription
            #expect(description?.isEmpty == false)
        }
    }

    @Test("The underlying system error is kept for diagnostics without leaking into the message")
    func preservesUnderlyingError() {
        let underlying = CocoaError(.fileNoSuchFile)
        let error = SaveLocationError(.bookmarkResolutionFailed, underlying: underlying)

        #expect(error.underlying != nil)
        #expect(error.errorDescription?.contains("could not be found") == true)
    }
}
