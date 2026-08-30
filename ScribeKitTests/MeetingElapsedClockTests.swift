//
//  MeetingElapsedClockTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@MainActor
@Suite("MeetingElapsedClock")
struct MeetingElapsedClockTests {

    /// A clock over a time the test moves itself, and the handle that moves it.
    ///
    /// - Parameter start: The moment the clock reads before it is advanced.
    /// - Returns: The clock and a function that sets the current time.
    private func makeClock(start: Date) -> (MeetingElapsedClock, (TimeInterval) -> Void) {
        final class Now { var date: Date; init(_ date: Date) { self.date = date } }
        let now = Now(start)
        let clock = MeetingElapsedClock(now: { now.date }, interval: nil)
        return (clock, { now.date = start.addingTimeInterval($0) })
    }

    @Test("A clock that has not been started has no meeting to time")
    func idle() {
        let (clock, _) = makeClock(start: Date(timeIntervalSince1970: 1_000))
        #expect(clock.startedAt == nil)
        #expect(clock.elapsed == 0)
        #expect(!clock.isTicking)
    }

    @Test("Elapsed time is measured from the start date")
    func measuresFromStart() {
        let start = Date(timeIntervalSince1970: 1_000)
        let (clock, advance) = makeClock(start: start)
        clock.start(at: start)
        #expect(clock.elapsed == 0)

        advance(90)
        clock.refresh()
        #expect(clock.elapsed == 90)
    }

    @Test("Stopping takes a last reading and keeps it")
    func stopKeepsTheFinalReading() {
        let start = Date(timeIntervalSince1970: 1_000)
        let (clock, advance) = makeClock(start: start)
        clock.start(at: start)

        advance(42)
        clock.stop()
        #expect(clock.elapsed == 42)

        advance(500)
        clock.refresh()
        #expect(clock.elapsed == 500, "refresh reads the clock; stopping only decides when it stops reading itself")
    }

    @Test("A second start replaces the first timer rather than adding one")
    func oneTimerAtATime() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = MeetingElapsedClock(now: { start }, interval: .milliseconds(10))
        clock.start(at: start)
        #expect(clock.isTicking)

        clock.start(at: start)
        #expect(clock.isTicking)

        clock.stop()
        #expect(!clock.isTicking)
    }

    @Test("A running clock refreshes itself without being asked")
    func ticks() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        final class Now: @unchecked Sendable { var date: Date; init(_ date: Date) { self.date = date } }
        let now = Now(start)
        let clock = MeetingElapsedClock(now: { now.date }, interval: .milliseconds(5))
        clock.start(at: start)
        now.date = start.addingTimeInterval(7)

        var observed = false
        for _ in 0..<200 where !observed {
            try await Task.sleep(for: .milliseconds(5))
            observed = clock.elapsed == 7
        }
        #expect(observed)
        clock.stop()
    }

    @Test("Durations read as minutes until there are hours")
    func formatting() {
        #expect(MeetingElapsedClock.description(of: 0) == "00:00")
        #expect(MeetingElapsedClock.description(of: 9.9) == "00:09")
        #expect(MeetingElapsedClock.description(of: 754) == "12:34")
        #expect(MeetingElapsedClock.description(of: 3_600) == "1:00:00")
        #expect(MeetingElapsedClock.description(of: 7_384) == "2:03:04")
        #expect(MeetingElapsedClock.description(of: -5) == "00:00")
    }
}
