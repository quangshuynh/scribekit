//
//  ScribeKitApp.swift
//  ScribeKit
//

import SwiftUI

/// The ScribeKit application entry point.
///
/// The main window displays the meeting; it does not own it.
/// ``ScribeKitAppDelegate`` does, so closing the window changes what is visible
/// and nothing else.
///
/// The window is a `Window` rather than a `WindowGroup` deliberately. There is
/// one meeting, so there is one window for it, and asking for that window again
/// reuses the one that exists instead of adding another copy of the application
/// beside the first.
@main
struct ScribeKitApp: App {

    /// The main window's scene identifier.
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(ScribeKitAppDelegate.self) private var delegate

    var body: some Scene {
        Window("ScribeKit", id: Self.mainWindowID) {
            MeetingSetupView(runtime: delegate.runtime)
        }
        .windowResizability(.contentMinSize)
    }
}
