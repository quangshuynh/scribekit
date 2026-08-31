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

        /// ScribeKit was refused the access discovery needs; the message
        /// says what to do about it.
        ///
        /// Kept apart from ``failed(_:)`` because the two need different
        /// answers from the user: one is a permission to grant, the other is
        /// something that went wrong.
        case accessUnavailable(String)

        /// Discovery failed for another reason, with a message describing why.
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
    private let preferences: MeetingSetupPreferencesStoring?
    private var hasAppliedRememberedSelection = false

    /// Creates a model backed by a discovery provider.
    ///
    /// - Parameters:
    ///   - provider: The source of application discovery results.
    ///   - preferences: Store holding the applications the user selected last
    ///     time. When given, those identifiers seed the selection on the first
    ///     successful discovery. Pass `nil` for a model that starts empty.
    init(provider: CaptureSourceProviding, preferences: MeetingSetupPreferencesStoring? = nil) {
        self.provider = provider
        self.preferences = preferences
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

    /// What the source part of start readiness knows, in the terms
    /// ``MeetingStartReadiness`` is derived from.
    ///
    /// Derived rather than stored, so a discovery that succeeds after a
    /// failure leaves nothing of the failure behind.
    var readiness: CaptureSourceReadiness {
        switch discoveryState {
        case .idle:
            .notAttempted
        case .loading:
            .discovering
        case let .accessUnavailable(message):
            .accessUnavailable(message: message)
        case let .failed(message):
            .discoveryFailed(message: message)
        case let .loaded(sources) where sources.isEmpty:
            .noApplicationsFound
        case let .loaded(sources):
            .discovered(
                available: sources.count,
                selected: selectedSourceIDs.count,
                droppedSelections: unavailableSelectionNames
            )
        }
    }

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
        preferences?.rememberedSourceIDs = selectedSourceIDs.sorted()
    }

    /// Runs discovery and reconciles the current selection with the result.
    ///
    /// The first successful discovery also seeds the selection from the
    /// remembered identifiers, keeping only those that were actually found.
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
            applyRememberedSelectionIfNeeded()
            reconcileSelection(with: sources, previousSources: previousSources)
        } catch CaptureSourceDiscoveryError.accessUnavailable {
            discoveryState = .accessUnavailable(
                message(for: CaptureSourceDiscoveryError.accessUnavailable)
            )
            unavailableSelectionNames = []
        } catch {
            discoveryState = .failed(message(for: error))
            unavailableSelectionNames = []
        }
    }

    /// Seeds the selection from remembered identifiers, once.
    ///
    /// Remembered identifiers are preferences, not evidence: they are matched
    /// against what discovery actually found, and the ones whose application is
    /// not running are simply not selected. They stay remembered, so an
    /// application that was merely closed today is selected again once it runs.
    private func applyRememberedSelectionIfNeeded() {
        guard !hasAppliedRememberedSelection, let preferences else { return }
        hasAppliedRememberedSelection = true
        selectedSourceIDs = Set(preferences.rememberedSourceIDs)
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
