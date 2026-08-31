//
//  MainWindowPresence.swift
//  ScribeKit
//

import AppKit
import Observation

/// Whether the main window is on screen, so the expensive presentation under
/// it can be built when it is and released when it is not.
///
/// A closed SwiftUI window is not an idle one. The scene outlives the window,
/// so its view graph stays installed, keeps observing the meeting and keeps
/// being laid out on the display cycle — measured in Interval 17 as roughly
/// the same cost as a visible window, and confirmed in Interval 18 to be
/// almost entirely SwiftUI layout rather than ScribeKit's own work. Taking the
/// hierarchy down is the only thing that returned the process to its headless
/// floor, so that is what this drives: the window's content is present only
/// while the window is.
///
/// This is a presentation fact and nothing else. It says where the interface
/// is, never what the meeting is doing, and nothing in the meeting reads it.
@MainActor
@Observable
final class MainWindowPresence {

    /// Whether the main window's content should exist right now.
    ///
    /// `false` before a window has ever been attached, so a scene that is
    /// built before its window exists starts detached rather than building a
    /// hierarchy it is about to throw away.
    private(set) var isPresenting = false

    /// The window being watched, held weakly because AppKit owns it.
    @ObservationIgnored private weak var window: NSWindow?

    /// The key-value observations registered for ``window``.
    @ObservationIgnored private var observers: [NSKeyValueObservation] = []

    /// How many observations are registered.
    ///
    /// The only resource this type owns, exposed so a test can prove that
    /// opening and closing the window repeatedly does not accumulate them.
    var observerCount: Int { observers.count }

    /// Whether a re-read of the window is already scheduled.
    @ObservationIgnored private var isRefreshScheduled = false

    /// Starts watching a window, or stops watching when there is none.
    ///
    /// The two properties are observed rather than the window notifications
    /// that usually accompany them, because a window can be ordered on screen
    /// without becoming key — which posts nothing — and an interface that
    /// missed that would leave an empty window in front of the user. `visible`
    /// and `miniaturized` are the state itself, so nothing can change one
    /// without this being told.
    ///
    /// Attaching to the window already attached does nothing, so a view that
    /// reports its window repeatedly registers one pair of observations rather
    /// than one per report.
    ///
    /// - Parameter window: The window the main presentation lives in, or `nil`
    ///   when the view reporting it has left its window.
    func attach(to window: NSWindow?) {
        guard window !== self.window else { return }
        observers = []
        self.window = window

        guard let window else {
            isPresenting = false
            return
        }
        let changed: (NSWindow, Any) -> Void = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        observers = [
            window.observe(\.isVisible) { changed($0, $1) },
            window.observe(\.isMiniaturized) { changed($0, $1) }
        ]
        refresh()
    }

    /// Re-reads the window on the next turn of the main loop.
    ///
    /// Deferred so the answer is read from the window after AppKit has
    /// finished changing it, and coalesced because both properties move
    /// together when a window is closed or opened.
    private func scheduleRefresh() {
        guard !isRefreshScheduled else { return }
        isRefreshScheduled = true
        Task { @MainActor in
            self.isRefreshScheduled = false
            self.refresh()
        }
    }

    /// Reads the window and records whether its content should exist.
    ///
    /// A miniaturised window is not visible, so it detaches for the same
    /// reason a closed one does: nothing is on screen to be laid out.
    func refresh() {
        guard let window else {
            isPresenting = false
            return
        }
        let presenting = window.isVisible && !window.isMiniaturized
        if presenting != isPresenting { isPresenting = presenting }
    }
}
