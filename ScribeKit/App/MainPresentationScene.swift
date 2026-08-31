//
//  MainPresentationScene.swift
//  ScribeKit
//

import AppKit
import SwiftUI

/// The main window's content, present only while the window is.
///
/// This is the whole of the presentation lifecycle change: the window scene
/// holds a shell that costs nothing, and the interface itself —
/// ``ScribeKitRootView``, the meeting form and the live transcript under it —
/// is a branch of that shell which exists while the window is on screen and is
/// released when it is not. Closing the window therefore takes the view
/// hierarchy down rather than moving it off screen, which is the difference
/// Interval 17 measured between a few points of a core and all of them.
///
/// Nothing about the meeting lives here. The runtime is passed through
/// untouched and is never read by this view, so rebuilding the branch cannot
/// invalidate the shell and detaching cannot stop, pause or duplicate
/// anything. A reopened window builds a fresh ``ScribeKitRootView`` over the
/// runtime that has been running all along, which is why there is no state to
/// carry across the gap: the meeting is the state.
struct MainPresentationScene: View {

    /// The application's meeting owner, shared with the menu bar.
    let runtime: MeetingRuntime

    /// Whether the window is on screen. Owned here rather than by the
    /// application object because it describes this scene's window and nothing
    /// else the application does.
    @State private var presence = MainWindowPresence()

    var body: some View {
        ZStack {
            MainWindowReader(presence: presence)
            if presence.isPresenting {
                ScribeKitRootView(runtime: runtime)
            }
        }
        .frame(minWidth: 620, minHeight: 560)
    }
}

/// Reports the window this scene is in, and stays behind when the interface
/// under it is released.
///
/// It lives in the shell rather than in ``ScribeKitRootView`` deliberately: the
/// thing that notices the window coming back cannot be part of what goes away
/// when the window leaves.
private struct MainWindowReader: NSViewRepresentable {

    /// The presence to keep up to date.
    let presence: MainWindowPresence

    func makeNSView(context: Context) -> NSView { WindowReportingView(presence: presence) }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// A view with no appearance whose only job is to say which window it is in.
private final class WindowReportingView: NSView {

    /// The presence told about this view's window.
    private let presence: MainWindowPresence

    /// Creates the reporter.
    ///
    /// - Parameter presence: The presence to report to.
    init(presence: MainWindowPresence) {
        self.presence = presence
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not created from a nib") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        presence.attach(to: window)
    }
}
