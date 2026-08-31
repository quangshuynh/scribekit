//
//  AudioCaptureActivityMonitorTests.swift
//  ScribeKitTests
//

import Foundation
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

    private func sample(frames: Int, peak: Float = 0.5) -> CapturedPCMBuffer {
        CapturedPCMBuffer(
            format: format,
            frameCount: frames,
            presentationTime: 1,
            peakAmplitude: peak,
            samples: [Float](repeating: peak, count: frames)
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

    @Test("A meeting's worth of publishes does not deepen the capture stack")
    func publishDepthIsConstant() async {
        let monitor = AudioCaptureActivityMonitor(minimumPublishInterval: .zero)
        let buffer = sample(frames: 480)
        let depths = Mutex<[Int]>([])
        let published = Mutex(0)

        // The observer is installed once and never replaced, so every publish
        // must reach it through the same number of frames. A monitor that left
        // a thunk on the stored closure per publish grew this by two frames a
        // time and exhausted the delivery queue's stack part-way through a
        // meeting.
        monitor.onUpdate = { _ in
            let count = published.withLock { $0 += 1; return $0 }
            if count == 1 || count == 3_000 || count == 6_000 {
                depths.withLock { $0.append(Thread.callStackSymbols.count) }
            }
        }

        // 6,000 publishes is fifty minutes at the interval capture actually
        // uses, run on a thread given the same 512 KB stack ScreenCaptureKit's
        // delivery queue has — past the twenty-odd minutes at which the old
        // monitor faulted on its guard page.
        await withCheckedContinuation { continuation in
            let thread = Thread {
                for _ in 0..<6_000 { monitor.consume(buffer) }
                continuation.resume()
            }
            thread.stackSize = 512 * 1_024
            thread.start()
        }

        let observed = depths.withLock { $0 }
        #expect(observed.count == 3)
        #expect(Set(observed).count == 1)
    }
}
