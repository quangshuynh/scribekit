//
//  FakeMeetingActivity.swift
//  ScribeKitTests
//

@testable import ScribeKit

/// An activity assertion that counts rather than asserting, so the assertion's
/// lifetime is testable without touching the real process.
@MainActor
final class FakeMeetingActivity: MeetingActivityAsserting {

    /// How many times an assertion was actually taken.
    private(set) var beginCount = 0

    /// How many times a held assertion was actually released.
    private(set) var endCount = 0

    private(set) var isAsserted = false

    /// Creates an asserter holding nothing.
    init() {}

    func begin() {
        guard !isAsserted else { return }
        isAsserted = true
        beginCount += 1
    }

    func end() {
        guard isAsserted else { return }
        isAsserted = false
        endCount += 1
    }
}
