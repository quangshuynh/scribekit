//
//  MeetingActivityAsserting.swift
//  ScribeKit
//

import Foundation

/// Tells the system that a meeting is user-initiated work that must keep
/// running while ScribeKit is not the frontmost application.
///
/// macOS puts an application into App Nap when it has no visible windows and
/// nothing is obviously happening in it, which throttles its timers and lowers
/// its priority. That is the exact situation this feature creates on purpose:
/// a meeting whose window the user minimised, hid or closed. Capture and
/// recognition are user-initiated work with a deadline attached — audio that
/// arrives late is audio that was not transcribed — so the meeting holds an
/// activity assertion for as long as it runs, and never a moment longer.
@MainActor
protocol MeetingActivityAsserting: AnyObject {
    /// Whether an assertion is currently held.
    var isAsserted: Bool { get }

    /// Asserts that a meeting is running. Asserting twice does nothing.
    func begin()

    /// Releases the assertion. Releasing without one does nothing.
    func end()
}

/// The activity assertion, made against the real process.
///
/// The options are the narrowest ones that address App Nap:
/// `userInitiatedAllowingIdleSystemSleep` opts the process out of App Nap and
/// out of automatic and sudden termination while the meeting runs, and
/// deliberately does *not* prevent the Mac from sleeping when the user leaves
/// it idle. Preventing sleep is a separate promise ScribeKit does not make,
/// and `latencyCritical` is for realtime media pipelines rather than for a
/// capture stream the system already schedules.
@MainActor
final class ProcessMeetingActivity: MeetingActivityAsserting {

    /// Why the assertion exists, as the system reports it.
    ///
    /// Deliberately generic: this string is visible outside the process, and
    /// no meeting title belongs in it.
    static let reason = "Transcribing a meeting"

    private var token: (any NSObjectProtocol)?

    /// Creates an asserter that holds nothing yet.
    init() {}

    var isAsserted: Bool { token != nil }

    func begin() {
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: Self.reason
        )
    }

    func end() {
        guard let token else { return }
        ProcessInfo.processInfo.endActivity(token)
        self.token = nil
    }
}
