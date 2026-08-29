//
//  MeetingSetupSourcesModelTests.swift
//  ScribeKitTests
//

import Testing
@testable import ScribeKit

/// A provider returning scripted results, so discovery states can be tested
/// without ScreenCaptureKit, real applications or system permission.
private final class StubSourceProvider: CaptureSourceProviding, @unchecked Sendable {
    private var results: [Result<[CaptureSource], Error>]

    /// - Parameter results: One result per expected discovery pass. The last
    ///   result is reused once the script is exhausted.
    init(_ results: [Result<[CaptureSource], Error>]) {
        self.results = results
    }

    func availableSources() async throws -> [CaptureSource] {
        let result = results.count > 1 ? results.removeFirst() : results[0]
        return try result.get()
    }
}

@MainActor
@Suite("MeetingSetupSourcesModel")
struct MeetingSetupSourcesModelTests {

    private let meet = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")
    private let browser = CaptureSource.application(bundleIdentifier: "com.example.Browser", displayName: "Browser")

    private func model(_ results: [Result<[CaptureSource], Error>]) -> MeetingSetupSourcesModel {
        MeetingSetupSourcesModel(provider: StubSourceProvider(results))
    }

    @Test("Discovery exposes the provider's sources")
    func exposesDiscoveredSources() async {
        let model = model([.success([meet, browser])])
        #expect(model.discoveryState == .idle)

        await model.refresh()

        #expect(model.discoveryState == .loaded([meet, browser]))
        #expect(model.availableSources == [meet, browser])
    }

    @Test("Discovering nothing produces an empty loaded state")
    func emptyDiscovery() async {
        let model = model([.success([])])
        await model.refresh()
        #expect(model.discoveryState == .loaded([]))
        #expect(model.availableSources.isEmpty)
    }

    @Test("Provider failure produces an error state without crashing")
    func failedDiscovery() async {
        let model = model([.failure(CaptureSourceDiscoveryError.permissionDenied)])
        await model.refresh()

        guard case let .failed(message) = model.discoveryState else {
            Issue.record("Expected a failed state, got \(model.discoveryState)")
            return
        }
        #expect(message.contains("Screen Recording"))
        #expect(model.availableSources.isEmpty)
    }

    @Test("Several applications can be selected at once")
    func multipleSelection() async {
        let model = model([.success([meet, browser])])
        await model.refresh()

        model.setSelection(true, for: meet)
        model.setSelection(true, for: browser)
        #expect(model.selectedSources == [meet, browser])
        #expect(model.isSelected(meet))

        model.setSelection(false, for: meet)
        #expect(model.selectedSources == [browser])
        #expect(!model.isSelected(meet))
    }

    @Test("Refresh keeps selections that are still available")
    func refreshPreservesSelection() async {
        let model = model([.success([meet, browser]), .success([browser, meet])])
        await model.refresh()
        model.setSelection(true, for: browser)

        await model.refresh()

        #expect(model.selectedSourceIDs == [browser.id])
        #expect(model.unavailableSelectionNames.isEmpty)
    }

    @Test("Refresh drops selections whose application disappeared")
    func refreshDropsUnavailableSelection() async {
        let model = model([.success([meet, browser]), .success([browser])])
        await model.refresh()
        model.setSelection(true, for: meet)
        model.setSelection(true, for: browser)

        await model.refresh()

        #expect(model.selectedSourceIDs == [browser.id])
        #expect(model.unavailableSelectionNames == ["Meet"])
    }

    @Test("A failed refresh leaves the existing selection alone")
    func failedRefreshKeepsSelection() async {
        let model = model([
            .success([meet, browser]),
            .failure(CaptureSourceDiscoveryError.systemFailure("content unavailable"))
        ])
        await model.refresh()
        model.setSelection(true, for: meet)

        await model.refresh()

        #expect(model.selectedSourceIDs == [meet.id])
        #expect(model.unavailableSelectionNames.isEmpty)
    }
}
