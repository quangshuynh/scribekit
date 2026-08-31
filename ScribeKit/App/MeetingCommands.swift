//
//  MeetingCommands.swift
//  ScribeKit
//

import AppKit
import SwiftUI

/// ScribeKit's own menu items for the meeting that is running.
///
/// The application's menus are the third place a meeting is shown, after the
/// window and the menu bar item, and they read the same
/// ``MeetingMenuBarPresentation`` derived from the same process-lifetime
/// ``MeetingRuntime``. There is no second copy of what a meeting can currently
/// do, so a menu item cannot offer a pause the menu bar has already withdrawn.
///
/// Only actions that already exist get an item, and only two of them get a
/// shortcut. Stop deliberately has none: it ends a meeting and finalises its
/// files, and that is not something to put one keystroke away from a typo.
struct MeetingCommands: Commands {

    /// The application's meeting owner, shared with both scenes.
    let runtime: MeetingRuntime

    /// The application's diagnostics owner. The menu is the discoverable home
    /// for exporting a report, and the one place that works with no window
    /// open.
    let diagnostics: MeetingDiagnostics

    @FocusedValue(\.historySearchFocus) private var historySearch
    @FocusedValue(\.scribeKitTabSelection) private var tabSelection

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            ForEach(ScribeKitTab.allCases) { tab in
                Button(tab.title) {
                    tabSelection?.tab = tab
                }
                .keyboardShortcut(tab.shortcut, modifiers: .command)
                .disabled(tabSelection == nil)
            }
            Divider()
        }

        CommandMenu("Meeting") {
            Button("Pause Meeting") {
                Task { await runtime.pause() }
            }
            .keyboardShortcut("p", modifiers: [.control, .command])
            .disabled(!presentation.canPause)

            Button("Resume Meeting") {
                Task { await runtime.resume() }
            }
            .keyboardShortcut("r", modifiers: [.control, .command])
            .disabled(!presentation.canResume)

            Button("Stop Meeting") {
                Task { await runtime.stop() }
            }
            .disabled(!presentation.canStop)

            Divider()

            Button("Show Transcript in Finder") {
                reveal(presentation.transcriptURL)
            }
            .disabled(presentation.transcriptURL == nil)

            Button("Show Audio in Finder") {
                reveal(presentation.audioURL)
            }
            .disabled(presentation.audioURL == nil)
        }

        CommandGroup(replacing: .help) {
            // The Help menu is where a Mac application puts the thing you
            // reach for when something has gone wrong, and it is reachable
            // with no window open, which a menu bar application needs. The
            // ellipsis is honest: this opens a save panel and writes nothing
            // until the user picks a destination.
            Button("Export Diagnostics…") { diagnostics.export() }
        }

        CommandGroup(after: .textEditing) {
            Button("Search History") {
                historySearch?.request()
            }
            .keyboardShortcut("f")
            .disabled(historySearch == nil)
        }
    }

    /// What the menus currently have to say, derived exactly as the menu bar
    /// derives it.
    private var presentation: MeetingMenuBarPresentation {
        MeetingMenuBarPresentation(
            status: runtime.status,
            meeting: runtime.meeting,
            transcript: runtime.persistenceState.layout?.transcriptURL,
            audio: runtime.audioRetentionState.url,
            canStop: runtime.canStop,
            canPause: runtime.canPause,
            canResume: runtime.canResume,
            outcome: runtime.outcome
        )
    }

    /// Selects a file in the Finder, when there is one.
    ///
    /// - Parameter url: The artifact to reveal.
    private func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
