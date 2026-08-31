//
//  SoakSampleSchedule.swift
//  SoakValidation
//

import Foundation

/// When a soak run stops to observe itself.
///
/// A soak is a measurement of a workload, so the measurement must not become
/// part of it. The schedule is therefore sparse and fixed in advance: an
/// observation at the start, one every ``interval`` after it, and one at the
/// end whatever the interval divides into. Offsets are seconds from the moment
/// capture started.
nonisolated struct SoakSampleSchedule: Equatable, Sendable {

    /// The gap between periodic observations, in seconds.
    let interval: TimeInterval

    /// How long the run lasts, in seconds.
    let duration: TimeInterval

    /// Creates a schedule.
    ///
    /// - Parameters:
    ///   - interval: Seconds between periodic observations. Values of zero or
    ///     less collapse to a schedule of the two endpoints.
    ///   - duration: Seconds the run lasts.
    init(interval: TimeInterval, duration: TimeInterval) {
        self.interval = interval
        self.duration = duration
    }

    /// The offsets, in seconds from the start of capture, at which to observe.
    ///
    /// Always begins at zero, never exceeds ``duration``, and always ends with
    /// it. Consecutive offsets are distinct, so a duration that is a multiple
    /// of the interval does not observe twice at the end.
    var offsets: [TimeInterval] {
        guard duration > 0 else { return [0] }
        var result: [TimeInterval] = [0]
        if interval > 0 {
            var next = interval
            while next < duration {
                result.append(next)
                next += interval
            }
        }
        result.append(duration)
        return result
    }

    /// How long to wait before the observation after a given one.
    ///
    /// - Parameter offset: The offset just observed.
    /// - Returns: Seconds to wait, or `nil` when nothing follows.
    func secondsAfter(_ offset: TimeInterval) -> TimeInterval? {
        guard let next = offsets.first(where: { $0 > offset }) else { return nil }
        return next - offset
    }
}
