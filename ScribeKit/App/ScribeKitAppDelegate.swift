//
//  ScribeKitAppDelegate.swift
//  ScribeKit
//

import AppKit

/// The application's own scope: it owns the meeting for as long as ScribeKit
/// runs, and decides what quitting does while one is under way.
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

    /// What quitting does while a meeting is running.
    private lazy var quit = MeetingQuitCoordinator(
        runtime: runtime,
        confirmStop: { Self.confirmStopAndQuit() },
        finish: { NSApplication.shared.reply(toApplicationShouldTerminate: $0) }
    )

    /// Keeps the application running when its window closes.
    ///
    /// Closing the window is not quitting. A meeting keeps capturing,
    /// transcribing and writing, and the window can be opened again. The
    /// application stays with no meeting running too, because whether it is
    /// still there should not depend on whether a window happens to be open.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Answers a deliberate Quit.
    ///
    /// - Parameter sender: The application being asked to terminate.
    /// - Returns: Whether to terminate now, not at all, or once the meeting
    ///   has been stopped properly.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch quit.applicationShouldTerminate() {
        case .terminateNow: .terminateNow
        case .cancel: .terminateCancel
        case .terminateLater: .terminateLater
        }
    }

    /// Asks whether to end the meeting and quit.
    ///
    /// The meeting is named by what it is rather than by its title: the alert
    /// is about the artifacts, and the title adds nothing the user does not
    /// already know about the meeting they are in.
    ///
    /// - Returns: `true` to stop the meeting and quit.
    private static func confirmStopAndQuit() -> Bool {
        let alert = NSAlert()
        alert.messageText = "A meeting is still being transcribed."
        alert.informativeText = "Quitting now stops the meeting. Its transcript, and its audio file if it "
            + "is keeping one, are finished and closed first."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop Meeting and Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
