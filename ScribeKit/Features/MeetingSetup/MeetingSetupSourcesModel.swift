//
//  MeetingSetupSourcesModel.swift
//  ScribeKit
//

import Foundation

/// Owns the application-source part of the meeting setup screen: what
/// discovery returned, what failed, and which applications the user picked.
///
/// The model performs no system discovery itself; it drives a
/// ``CaptureSourceProviding`` value and keeps the resulting state bounded to
/// the current list plus the identifiers the user selected.
@MainActor
@Observable
final class MeetingSetupSourcesModel {

    /// The outcome of the most recent discovery attempt.
    enum DiscoveryState: Equatable {
        /// Discovery has not run yet.
        case idle

        /// Discovery is in progress.
        case loading

        /// Discovery finished; the payload is empty when nothing qualified.
        case loaded([CaptureSource])

        /// Discovery failed, with a message describing why.
        case failed(String)
    }

    /// The current discovery state.
    private(set) var discoveryState: DiscoveryState = .idle

    /// Identifiers of the applications the user selected.
    ///
    /// Only identifiers present in the most recent successful discovery are
    /// kept, so a selection can never refer to an application that has gone.
    private(set) var selectedSourceIDs: Set<CaptureSource.ID> = []

    /// Names of selected applications dropped by the most recent refresh
    /// because they were no longer available.
    ///
    /// Cleared by the next refresh; shown once so the user is not silently
    /// left with fewer sources than they chose.
    private(set) var unavailableSelectionNames: [String] = []

    private let provider: CaptureSourceProviding

    /// Creates a model backed by a discovery provider.
    ///
    /// - Parameter provider: The source of application discovery results.
    init(provider: CaptureSourceProviding) {
        self.provider = provider
    }

    /// The sources from the most recent successful discovery.
    var availableSources: [CaptureSource] {
        if case let .loaded(sources) = discoveryState { sources } else { [] }
    }

    /// The selected sources, in the order they are displayed.
    var selectedSources: [CaptureSource] {
        availableSources.filter { selectedSourceIDs.contains($0.id) }
    }

    /// Whether discovery is currently running.
    var isDiscovering: Bool { discoveryState == .loading }

    /// Whether a source is selected.
    ///
    /// - Parameter source: The source to test.
    /// - Returns: `true` when the user selected it.
    func isSelected(_ source: CaptureSource) -> Bool {
        selectedSourceIDs.contains(source.id)
    }

    /// Selects or deselects a source.
    ///
    /// Selection is additive: any number of applications can be selected.
    ///
    /// - Parameters:
    ///   - isSelected: The desired selection state.
    ///   - source: The source to change.
    func setSelection(_ isSelected: Bool, for source: CaptureSource) {
        if isSelected {
            selectedSourceIDs.insert(source.id)
        } else {
            selectedSourceIDs.remove(source.id)
        }
    }

    /// Runs discovery and reconciles the current selection with the result.
    ///
    /// Selections for applications that are still available are preserved;
    /// selections for applications that disappeared are removed and reported
    /// through ``unavailableSelectionNames``. A failed discovery leaves the
    /// selection untouched, because a failure says nothing about which
    /// applications are still running.
    func refresh() async {
        let previousSources = availableSources
        discoveryState = .loading

        do {
            let sources = try await provider.availableSources()
            discoveryState = .loaded(sources)
            reconcileSelection(with: sources, previousSources: previousSources)
        } catch {
            discoveryState = .failed(message(for: error))
            unavailableSelectionNames = []
        }
    }

    /// Drops selections that the latest discovery no longer contains.
    ///
    /// - Parameters:
    ///   - sources: The sources just discovered.
    ///   - previousSources: The previously displayed sources, used to name the
    ///     selections that disappeared.
    private func reconcileSelection(with sources: [CaptureSource], previousSources: [CaptureSource]) {
        let availableIDs = Set(sources.map(\.id))
        let removedIDs = selectedSourceIDs.subtracting(availableIDs)
        selectedSourceIDs.formIntersection(availableIDs)
        unavailableSelectionNames = previousSources
            .filter { removedIDs.contains($0.id) }
            .map(\.displayName)
    }

    /// Converts a discovery error into a message for the screen.
    ///
    /// - Parameter error: The error thrown by the provider.
    /// - Returns: A user-facing description.
    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
