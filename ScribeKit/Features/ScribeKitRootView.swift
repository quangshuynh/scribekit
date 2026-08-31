//
//  ScribeKitRootView.swift
//  ScribeKit
//

import SwiftUI

/// The main window's two screens: the meeting, and the meetings that are
/// already on disk.
///
/// The split is by what the user is doing rather than by what ScribeKit owns.
/// Both tabs read the same application-scoped ``MeetingRuntime``; neither owns
/// it, so moving between them starts, stops and duplicates nothing. A meeting
/// running on the Meeting tab keeps capturing, recognising and writing while
/// History is on screen.
///
/// Which screen is showing is published as a scene-focus value so the View
/// menu can change it, because a tab bar is a click target and the menu is how
/// the same move is made from the keyboard.
struct ScribeKitRootView: View {

    /// The application's meeting owner, shared with the menu bar.
    let runtime: MeetingRuntime

    @State private var selection = ScribeKitTabSelection()

    /// Creates the window's content.
    ///
    /// - Parameter runtime: The application's meeting owner.
    init(runtime: MeetingRuntime) {
        self.runtime = runtime
    }

    var body: some View {
        TabView(selection: Bindable(selection).tab) {
            MeetingSetupView(runtime: runtime)
                .tabItem { Label(ScribeKitTab.meeting.title, systemImage: ScribeKitTab.meeting.systemImage) }
                .accessibilityLabel(ScribeKitTab.meeting.title)
                .tag(ScribeKitTab.meeting)
            HistoryView(runtime: runtime)
                .tabItem { Label(ScribeKitTab.history.title, systemImage: ScribeKitTab.history.systemImage) }
                .accessibilityLabel(ScribeKitTab.history.title)
                .tag(ScribeKitTab.history)
        }
        .frame(minWidth: 620, minHeight: 560)
        .focusedSceneValue(\.scribeKitTabSelection, selection)
    }
}

#Preview {
    ScribeKitRootView(runtime: MeetingRuntime())
}
