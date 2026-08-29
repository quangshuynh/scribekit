//
//  AudioCaptureActivityMonitor.swift
//  ScribeKit
//

import Foundation
import Synchronization

/// What capture has delivered so far.
///
/// Every field is an aggregate. Nothing here grows with the length of a
/// meeting, so the value can be published continuously without the interface
/// becoming a reason to retain audio.
nonisolated struct AudioCaptureActivity: Equatable, Sendable {
    /// Buffers received since capture started.
    var sampleCount = 0

    /// Audio frames received since capture started.
    var frameCount = 0

    /// Buffers that arrived but could not be described.
    var unreadableSampleCount = 0

    /// The format of the most recent buffer.
    var format: CapturedAudioFormat?

    /// The peak level of the most recent buffer, when it could be read.
    var peakAmplitude: Float?

    /// Nothing received yet.
    static let none = AudioCaptureActivity()

    /// Seconds of audio received, derived from the frame count and the format
    /// that was actually delivered.
    var capturedDuration: Double? {
        guard let format, format.sampleRate > 0 else { return nil }
        return Double(frameCount) / format.sampleRate
    }
}

/// Accumulates capture activity on the delivery queue and publishes coalesced
/// snapshots.
///
/// Audio arrives far more often than a view needs to change, so the monitor
/// keeps counters behind a lock and forwards a snapshot at most once per
/// ``minimumPublishInterval``. Updates are therefore driven by audio actually
/// arriving — there is no timer and no polling — while the interface is spared
/// the delivery rate.
nonisolated final class AudioCaptureActivityMonitor: AudioSampleConsuming {

    /// Called with a snapshot when one is due, on the delivery queue.
    ///
    /// Set before capture starts. The handler runs off the main actor and is
    /// responsible for its own hop.
    var onUpdate: (@Sendable (AudioCaptureActivity) -> Void)? {
        get { handler.withLock { $0 } }
        set { handler.withLock { $0 = newValue } }
    }

    /// The shortest gap between two published snapshots.
    let minimumPublishInterval: Duration

    private struct State {
        var activity = AudioCaptureActivity.none
        var lastPublished: ContinuousClock.Instant?
    }

    private let state = Mutex(State())
    private let handler = Mutex<(@Sendable (AudioCaptureActivity) -> Void)?>(nil)
    private let clock = ContinuousClock()

    /// Creates a monitor.
    ///
    /// - Parameter minimumPublishInterval: The shortest gap between published
    ///   snapshots. The default keeps interface updates at a human rate
    ///   regardless of how fast audio arrives; tests pass `.zero` to observe
    ///   every buffer.
    init(minimumPublishInterval: Duration = .milliseconds(500)) {
        self.minimumPublishInterval = minimumPublishInterval
    }

    /// The counters as they stand.
    var activity: AudioCaptureActivity {
        state.withLock { $0.activity }
    }

    /// Clears the counters, so a new capture starts from zero.
    ///
    /// The next buffer publishes immediately rather than waiting out the
    /// interval left over from the previous capture.
    func reset() {
        state.withLock { $0 = State() }
        publish(activity: .none)
    }

    func consume(_ buffer: CapturedPCMBuffer) {
        record { activity in
            activity.sampleCount += 1
            activity.frameCount += buffer.frameCount
            activity.format = buffer.format
            activity.peakAmplitude = buffer.peakAmplitude
        }
    }

    func recordUnreadableSample() {
        record { $0.unreadableSampleCount += 1 }
    }

    /// Applies a change and publishes the result when one is due.
    ///
    /// - Parameter change: The mutation to apply under the lock.
    private func record(_ change: (inout AudioCaptureActivity) -> Void) {
        let now = clock.now
        let due: AudioCaptureActivity? = state.withLock { state in
            change(&state.activity)
            let isDue = state.lastPublished.map { now - $0 >= minimumPublishInterval } ?? true
            guard isDue else { return nil }
            state.lastPublished = now
            return state.activity
        }
        if let due { publish(activity: due) }
    }

    /// Delivers a snapshot outside the lock, so a slow observer cannot block
    /// the delivery queue's next buffer on this monitor's state.
    ///
    /// - Parameter activity: The snapshot to publish.
    private func publish(activity: AudioCaptureActivity) {
        handler.withLock { $0 }?(activity)
    }
}
