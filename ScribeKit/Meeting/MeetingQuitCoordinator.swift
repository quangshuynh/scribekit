//
//  MeetingQuitCoordinator.swift
//  ScribeKit
//

import Foundation

/// Decides what a deliberate Quit does while a meeting is running.
///
/// Quitting is not a crash and must not be treated as one. A meeting that is
/// still capturing has an open transcript, possibly an open recording, and a
/// session record that still says the meeting is in progress; letting the
/// process vanish would leave all three for the next launch's recovery to
/// report, when ScribeKit was running and could simply have finished them.
///
/// So the user is asked, once, and the answer decides. Stopping runs the
/// ordinary stop — the same ordering, the same finalisation, the same
/// completion record — and only then is termination allowed to continue.
///
/// The coordinator holds no AppKit: the question is asked through a closure
/// and the answer is delivered through another, so the policy is testable
/// without a modal alert or a running application.
@MainActor
final class MeetingQuitCoordinator {

    /// What the application should do about the termination request.
    enum Reply: Equatable {
        /// Nothing is running; terminate.
        case terminateNow

        /// The user chose to keep the meeting; do not terminate.
        case cancel

        /// The meeting is being stopped; terminate once ``finish`` is called.
        case terminateLater
    }

    /// The stop started by a termination request, kept so it can be awaited.
    private(set) var stopTask: Task<Void, Never>?

    private let runtime: MeetingRuntime
    private let confirmStop: () -> Bool
    private let finish: (Bool) -> Void

    /// Creates a coordinator.
    ///
    /// - Parameters:
    ///   - runtime: The meeting owner asked whether anything is running, and
    ///     asked to stop when the user says so.
    ///   - confirmStop: Asks the user whether to stop the meeting and quit.
    ///     Returns `true` to stop and quit, `false` to stay.
    ///   - finish: Reports the outcome of a deferred termination.
    init(
        runtime: MeetingRuntime,
        confirmStop: @escaping () -> Bool,
        finish: @escaping (Bool) -> Void
    ) {
        self.runtime = runtime
        self.confirmStop = confirmStop
        self.finish = finish
    }

    /// Answers a termination request.
    ///
    /// The stop is not raced against a deadline. A stop that is still running
    /// is flushing and closing the meeting's artifacts, and terminating out
    /// from under it would produce exactly the half-written files this exists
    /// to prevent; the stop itself is bounded, because every step in it is.
    ///
    /// - Returns: What the application should do.
    func applicationShouldTerminate() -> Reply {
        guard runtime.status.isActive else { return .terminateNow }
        guard confirmStop() else { return .cancel }
        stopTask = Task { [runtime, finish] in
            await runtime.stop()
            finish(true)
        }
        return .terminateLater
    }
}
