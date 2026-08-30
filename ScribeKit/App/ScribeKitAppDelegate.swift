//
//  ScribeKitAppDelegate.swift
//  ScribeKit
//

import AppKit

/// The application's own scope: it owns the meeting for as long as ScribeKit
/// runs.
///
/// The meeting owner lives here rather than in a scene's `@State` because a
/// scene can go away — the main window is closable and a menu bar item is not a
/// window at all — and a meeting must not. This is the application object, so
/// its lifetime is the application's lifetime by definition, which is the
/// property the meeting needs and the only reason the delegate exists.
@MainActor
final class ScribeKitAppDelegate: NSObject, NSApplicationDelegate {

    /// The one meeting the application can be running.
    let runtime = MeetingRuntime()

    /// Keeps the application running when its window closes.
    ///
    /// Closing the window is not quitting. A meeting keeps capturing,
    /// transcribing and writing, and the window can be opened again. The
    /// application stays with no meeting running too, because whether it is
    /// still there should not depend on whether a window happens to be open.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
