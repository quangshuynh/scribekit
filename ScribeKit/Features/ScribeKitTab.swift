//
//  ScribeKitTab.swift
//  ScribeKit
//

import SwiftUI

/// The main window's two screens.
enum ScribeKitTab: String, CaseIterable, Identifiable, Equatable, Sendable {

    /// Configuring a meeting, and watching the one that is running.
    case meeting

    /// The meetings already on disk.
    case history

    var id: String { rawValue }

    /// The name shown on the tab and spoken for it.
    var title: String {
        switch self {
        case .meeting: "Meeting"
        case .history: "History"
        }
    }

    /// The tab's SF Symbol.
    var systemImage: String {
        switch self {
        case .meeting: "waveform"
        case .history: "clock.arrow.circlepath"
        }
    }

    /// The number key that selects the tab, matching its position.
    var shortcut: KeyEquivalent {
        switch self {
        case .meeting: "1"
        case .history: "2"
        }
    }
}

/// Which of the main window's screens is showing.
///
/// The window owns its own selection, and the View menu has to be able to
/// change it. Rather than either reaching for the other, the window publishes
/// this object as SwiftUI's scene-focus value and the menu drives whatever the
/// focused scene offers — nothing at all when no window is open, which is when
/// the menu items correctly do nothing.
@MainActor
@Observable
final class ScribeKitTabSelection {

    /// The screen currently showing.
    var tab: ScribeKitTab

    /// Creates a selection.
    ///
    /// - Parameter tab: The screen to start on.
    init(tab: ScribeKitTab = .meeting) {
        self.tab = tab
    }
}

extension ScribeKitTabSelection: Equatable {

    /// Identity, because there is one of these per window and what matters to
    /// the menu is which window is offering it.
    nonisolated static func == (lhs: ScribeKitTabSelection, rhs: ScribeKitTabSelection) -> Bool {
        lhs === rhs
    }
}

/// The scene-focus key the main window publishes its tab selection under.
private struct ScribeKitTabSelectionKey: FocusedValueKey {
    typealias Value = ScribeKitTabSelection
}

extension FocusedValues {

    /// The focused scene's tab selection, when a main window is open to offer
    /// one.
    var scribeKitTabSelection: ScribeKitTabSelection? {
        get { self[ScribeKitTabSelectionKey.self] }
        set { self[ScribeKitTabSelectionKey.self] = newValue }
    }
}
