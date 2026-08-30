//
//  ScribeKitApp.swift
//  ScribeKit
//

import SwiftUI

/// The ScribeKit application entry point.
///
/// Two scenes observe one meeting: the main window, which configures and
/// displays it, and the menu bar item, which watches and ends it. Neither owns
/// it — ``ScribeKitAppDelegate`` does — so closing the window changes what is
/// visible and nothing else.
///
/// The main window is a `Window` rather than a `WindowGroup` deliberately.
/// There is one meeting, so there is one window for it, and asking for it from
/// the menu bar reopens or fronts that window instead of adding another copy of
/// the application beside the first.
@main
struct ScribeKitApp: App {

    /// The identifier the menu bar uses to bring the main window back.
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(ScribeKitAppDelegate.self) private var delegate

    var body: some Scene {
        Window("ScribeKit", id: Self.mainWindowID) {
            MeetingSetupView(runtime: delegate.runtime)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MeetingMenuBarView(runtime: delegate.runtime, mainWindowID: Self.mainWindowID)
        } label: {
            let presentation = MeetingMenuBarPresentation(
                status: delegate.runtime.status,
                meeting: delegate.runtime.meeting,
                transcript: nil,
                audio: nil,
                canStop: false
            )
            Image(systemName: presentation.symbolName)
                .accessibilityLabel(presentation.accessibilityLabel)
        }
        .menuBarExtraStyle(.menu)
    }
}
