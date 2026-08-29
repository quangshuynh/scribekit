//
//  ScribeKitApp.swift
//  ScribeKit
//

import SwiftUI

/// The ScribeKit application entry point.
@main
struct ScribeKitApp: App {
    var body: some Scene {
        WindowGroup {
            MeetingSetupView()
        }
        .windowResizability(.contentMinSize)
    }
}
