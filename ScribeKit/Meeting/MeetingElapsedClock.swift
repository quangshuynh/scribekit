//
//  MeetingElapsedClock.swift
//  ScribeKit
//

import Foundation

/// How long the current meeting has been running.
///
/// One clock exists for the whole application, owned by ``MeetingRuntime``, so
/// a meeting that is shown in the menu bar and in the main window at the same
/// time is timed once rather than twice. It ticks at most once a second and
/// only while a meeting is running; nothing here is written to disk, and the
/// meeting's own timestamps — the ones in the transcript and the session
/// record — remain the authoritative account of when it ran.
@MainActor
@Observable
final class MeetingElapsedClock {

    /// How long the meeting has been running, in seconds.
    private(set) var elapsed: TimeInterval = 0

    /// When the meeting being timed started, or `nil` before the first one.
    private(set) var startedAt: Date?

    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let interval: Duration?

    /// Creates a clock.
    ///
    /// - Parameters:
    ///   - now: Reads the current time. Tests substitute a controllable one.
    ///   - interval: How often the clock refreshes itself. `nil` refreshes
    ///     only when ``refresh()`` is called, which is how tests advance it
    ///     without waiting for real time to pass.
    init(now: @escaping () -> Date = { Date() }, interval: Duration? = .seconds(1)) {
        self.now = now
        self.interval = interval
    }

    /// Whether a tick task is running.
    ///
    /// At most one ever is: ``start(at:)`` cancels the previous one before
    /// starting another, so recreating the interface cannot leave a second
    /// timer behind.
    var isTicking: Bool { ticker != nil }

    /// Begins timing a meeting.
    ///
    /// - Parameter date: When the meeting started.
    func start(at date: Date) {
        stop()
        startedAt = date
        elapsed = 0
        guard let interval else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    /// Stops timing, leaving the final elapsed time in place.
    ///
    /// The last value is kept deliberately: a meeting that has just finished
    /// still has a length worth showing, and zeroing it would replace a fact
    /// with a blank.
    func stop() {
        refresh()
        ticker?.cancel()
        ticker = nil
    }

    /// Recomputes the elapsed time from the start date.
    func refresh() {
        guard let startedAt else { return }
        elapsed = max(0, now().timeIntervalSince(startedAt))
    }

    /// Formats a duration for display.
    ///
    /// Hours appear only once there are some, so a short meeting reads as
    /// `12:34` rather than `00:12:34`.
    ///
    /// - Parameter seconds: The duration to format.
    /// - Returns: A `mm:ss` or `h:mm:ss` string.
    static func description(of seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }
}
