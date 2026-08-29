//
//  AudioCaptureActivityMonitorTests.swift
//  ScribeKitTests
//

import Synchronization
import Testing
@testable import ScribeKit

/// Collects published snapshots from a monitor, which delivers them on the
/// capture queue rather than on the test's thread.
private nonisolated final class SnapshotRecorder: Sendable {
    private let snapshots = Mutex<[AudioCaptureActivity]>([])

    var all: [AudioCaptureActivity] { snapshots.withLock { $0 } }

    func record(_ activity: AudioCaptureActivity) {
        snapshots.withLock { $0.append(activity) }
    }
}

@Suite("AudioCaptureActivityMonitor")
struct AudioCaptureActivityMonitorTests {

    private let format = CapturedAudioFormat(
        sampleRate: 48_000,
        channelCount: 1,
        bitsPerChannel: 32,
        isFloat: true,
        isInterleaved: false
    )

    private func sample(frames: Int, peak: Float = 0.5) -> CapturedAudioSample {
        CapturedAudioSample(
            format: format,
            frameCount: frames,
            presentationTime: 1,
            peakAmplitude: peak
        )
    }

    @Test("Consumed samples accumulate into bounded counters")
    func accumulatesSamples() {
        let monitor = AudioCaptureActivityMonitor(minimumPublishInterval: .zero)

        monitor.consume(sample(frames: 480))
        monitor.consume(sample(frames: 960, peak: 0.75))

        let activity = monitor.activity
        #expect(activity.sampleCount == 2)
        #expect(activity.frameCount == 1_440)
        #expect(activity.format == format)
        #expect(activity.peakAmplitude == 0.75)
        #expect(activity.capturedDuration == 1_440 / 48_000.0)
    }

    @Test("Unreadable buffers are counted rather than ignored")
    func countsUnreadableSamples() {
        let monitor = AudioCaptureActivityMonitor(minimumPublishInterval: .zero)

        monitor.consume(sample(frames: 480))
        monitor.recordUnreadableSample()
        monitor.recordUnreadableSample()

        #expect(monitor.activity.sampleCount == 1)
        #expect(monitor.activity.unreadableSampleCount == 2)
    }

    @Test("Every sample publishes when no interval is imposed")
    func publishesEverySample() {
        let monitor = AudioCaptureActivityMonitor(minimumPublishInterval: .zero)
        let recorder = SnapshotRecorder()
        monitor.onUpdate = { recorder.record($0) }

        monitor.consume(sample(frames: 480))
        monitor.consume(sample(frames: 480))
        monitor.consume(sample(frames: 480))

        #expect(recorder.all.count == 3)
        #expect(recorder.all.last?.frameCount == 1_440)
    }

    @Test("Publishing is coalesced, so delivery rate does not become update rate")
    func coalescesUpdates() {
        let monitor = AudioCaptureActivityMonitor(minimumPublishInterval: .seconds(60))
        let recorder = SnapshotRecorder()
        monitor.onUpdate = { recorder.record($0) }

        for _ in 0..<500 {
            monitor.consume(sample(frames: 480))
        }

        #expect(recorder.all.count == 1)
        #expect(recorder.all.first?.sampleCount == 1)
        #expect(monitor.activity.sampleCount == 500)
        #expect(monitor.activity.frameCount == 240_000)
    }

    @Test("Resetting clears the counters and publishes the empty state")
    func resetClearsCounters() {
        let monitor = AudioCaptureActivityMonitor(minimumPublishInterval: .seconds(60))
        monitor.consume(sample(frames: 480))
        let recorder = SnapshotRecorder()
        monitor.onUpdate = { recorder.record($0) }

        monitor.reset()

        #expect(monitor.activity == .none)
        #expect(recorder.all == [.none])

        monitor.consume(sample(frames: 240))
        #expect(recorder.all.count == 2)
        #expect(recorder.all.last?.frameCount == 240)
    }

    @Test("Duration is unknown until a format has been observed")
    func durationNeedsFormat() {
        #expect(AudioCaptureActivity.none.capturedDuration == nil)
    }
}
