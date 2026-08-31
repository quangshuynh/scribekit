//
//  HistorySearchFocus.swift
//  ScribeKit
//

import SwiftUI

/// A standing request to put the keyboard in History's search field.
///
/// The Find menu item lives in the application's menus and the search field
/// lives inside one screen of one window, so the two cannot reach each other
/// directly. Rather than a coordinator that both look up, History publishes
/// this object as SwiftUI's own scene-focus value: the menu item reads
/// whatever the focused scene offers, which is nothing at all when History is
/// not on screen, and the item disables itself accordingly.
///
/// It carries a count rather than a flag because the same request may be made
/// repeatedly — ⌘F while the field already has focus is still ⌘F — and a
/// count changes every time where a flag would only change once.
@MainActor
@Observable
final class HistorySearchFocus {

    /// How many times the search field has been asked for.
    private(set) var requestCount = 0

    /// Creates a request holder.
    init() {}

    /// Asks for the keyboard to move to the search field.
    func request() {
        requestCount += 1
    }
}

extension HistorySearchFocus: Equatable {

    /// Identity, because there is one of these per History screen and what
    /// matters to the menu is which screen is offering it.
    nonisolated static func == (lhs: HistorySearchFocus, rhs: HistorySearchFocus) -> Bool {
        lhs === rhs
    }
}

/// The scene-focus key History publishes its search request under.
private struct HistorySearchFocusKey: FocusedValueKey {
    typealias Value = HistorySearchFocus
}

extension FocusedValues {

    /// The focused scene's History search request, when a History screen is on
    /// screen to offer one.
    var historySearchFocus: HistorySearchFocus? {
        get { self[HistorySearchFocusKey.self] }
        set { self[HistorySearchFocusKey.self] = newValue }
    }
}
