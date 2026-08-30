//
//  MeetingMenuBarView.swift
//  ScribeKit
//

import AppKit
import SwiftUI

/// The menu behind ScribeKit's menu bar item.
///
/// It exists so a meeting can be watched and ended without the main window,
/// and it is deliberately not a second interface to the application: it shows
/// what is running and offers Stop, the two Finder reveals the main window
/// already offers, a way back to the window, and Quit. Configuration stays in
/// the window, because a meeting's configuration is fixed once it starts.
///
/// There is no Pause item. Pause is not implemented, and a control that looked
/// like one would be a claim ScribeKit cannot keep.
struct MeetingMenuBarView: View {

    /// The one meeting owner, shared with the main window.
    let runtime: MeetingRuntime

    /// The identifier of the main window scene, used to bring it back.
    let mainWindowID: String

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let presentation = presentation

        if let title = presentation.title, presentation.showsElapsed {
            Text(title)
            Text("\(presentation.statusLine) · \(MeetingElapsedClock.description(of: runtime.elapsed.elapsed))")
        } else {
            Text(presentation.statusLine)
        }

        ForEach(presentation.details, id: \.self) { detail in
            Text(detail)
        }

        if let message = presentation.failureMessage {
            Text(message)
        }

        Divider()

        if presentation.canStop {
            Button("Stop Meeting") {
                Task { await runtime.stop() }
            }
        }

        if let url = presentation.transcriptURL {
            Button("Show Transcript in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }

        if let url = presentation.audioURL {
            Button("Show Audio in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }

        Divider()

        Button("Open ScribeKit") { showMainWindow() }

        Button("Quit ScribeKit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// What the menu currently has to say.
    private var presentation: MeetingMenuBarPresentation {
        MeetingMenuBarPresentation(
            status: runtime.status,
            meeting: runtime.meeting,
            transcript: runtime.persistenceState.layout?.transcriptURL,
            audio: runtime.audioRetentionState.url,
            canStop: runtime.canStop
        )
    }

    /// Brings the main window forward, opening it again if it was closed.
    ///
    /// The scene is a single `Window` rather than a `WindowGroup`, so asking
    /// for it repeatedly reuses the one that exists instead of stacking up
    /// copies of the application.
    private func showMainWindow() {
        NSApplication.shared.activate()
        openWindow(id: mainWindowID)
    }
}
