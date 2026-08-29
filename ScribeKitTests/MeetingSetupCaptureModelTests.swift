//
//  MeetingSetupCaptureModelTests.swift
//  ScribeKitTests
//

import Synchronization
import Testing
@testable import ScribeKit

/// A capturer that records calls and can be made to fail or to be interrupted,
/// so capture lifecycle is testable without ScreenCaptureKit, a real meeting or
/// screen recording permission.
///
/// Its start/stop rules mirror the real implementation: an empty selection and
/// a second start are refused rather than quietly accepted.
private nonisolated final class FakeCapturer: AudioCapturing, @unchecked Sendable {
    let interruptions: AsyncStream<AudioCaptureError>
    let consumer: AudioSampleConsuming

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var configurations: [AudioCaptureConfiguration] = []
    private(set) var isCapturing = false

    /// Thrown by the next `start`, when set.
    var startError: AudioCaptureError?

    private let continuation: AsyncStream<AudioCaptureError>.Continuation

    init(consumer: AudioSampleConsuming) {
        self.consumer = consumer
        var continuation: AsyncStream<AudioCaptureError>.Continuation!
        interruptions = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start(configuration: AudioCaptureConfiguration) async throws {
        startCount += 1
        configurations.append(configuration)
        if let startError { throw startError }
        guard !configuration.sourceIDs.isEmpty else { throw AudioCaptureError.noSourcesSelected }
        guard !isCapturing else { throw AudioCaptureError.alreadyCapturing }
        isCapturing = true
    }

    func stop() async {
        stopCount += 1
        isCapturing = false
    }

    /// Reports the capture system ending the stream on its own.
    func interrupt(_ error: AudioCaptureError) {
        isCapturing = false
        continuation.yield(error)
    }

    /// Delivers a synthetic buffer the way the real capture queue would.
    func deliver(_ sample: CapturedAudioSample) {
        consumer.consume(sample)
    }
}

@MainActor
@Suite("MeetingSetupCaptureModel")
struct MeetingSetupCaptureModelTests {

    private let meet = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")
    private let browser = CaptureSource.application(bundleIdentifier: "com.example.Browser", displayName: "Browser")

    private let format = CapturedAudioFormat(
        sampleRate: 48_000,
        channelCount: 1,
        bitsPerChannel: 32,
        isFloat: true,
        isInterleaved: false
    )

    /// Builds a model over a fake capturer, returning both.
    private func makeModel() -> (MeetingSetupCaptureModel, FakeCapturer) {
        var capturer: FakeCapturer!
        let model = MeetingSetupCaptureModel(
            monitor: AudioCaptureActivityMonitor(minimumPublishInterval: .zero),
            makeCapturer: { consumer in
                capturer = FakeCapturer(consumer: consumer)
                return capturer
            }
        )
        return (model, capturer)
    }

    /// The state the model should reach when a capture error is reported.
    ///
    /// - Parameter error: The error the capturer raised.
    /// - Returns: The expected failure state.
    private func failure(_ error: AudioCaptureError) -> AudioCaptureState {
        .failed(message: error.errorDescription ?? "")
    }

    /// Waits for a main-actor condition that a background delivery will satisfy.
    ///
    /// - Parameter condition: The condition to wait for.
    /// - Returns: `true` when it became true before the attempts ran out.
    private func wait(for condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test("Starting from idle captures the selected applications")
    func startsFromIdle() async {
        let (model, capturer) = makeModel()
        #expect(model.state == .idle)
        #expect(model.canStart(sources: [meet]))

        await model.start(sources: [meet, browser])

        #expect(model.state == .capturing)
        #expect(capturer.startCount == 1)
        #expect(capturer.configurations.first?.sourceIDs == [meet.id, browser.id])
        #expect(capturer.configurations.first?.sampleRate == AudioCaptureConfiguration.defaultSampleRate)
        #expect(capturer.configurations.first?.channelCount == AudioCaptureConfiguration.defaultChannelCount)
    }

    @Test("Starting is not offered without a selection")
    func startNeedsSelection() async {
        let (model, capturer) = makeModel()

        #expect(!model.canStart(sources: []))

        await model.start(sources: [])

        #expect(model.state == failure(.noSourcesSelected))
        #expect(capturer.isCapturing == false)
    }

    @Test("Starting again while capturing does not reach the capturer")
    func duplicateStartIsIgnored() async {
        let (model, capturer) = makeModel()
        await model.start(sources: [meet])

        #expect(!model.canStart(sources: [meet]))
        await model.start(sources: [meet])

        #expect(model.state == .capturing)
        #expect(capturer.startCount == 1)
    }

    @Test("Stopping while capturing returns to idle")
    func stopsFromCapturing() async {
        let (model, capturer) = makeModel()
        await model.start(sources: [meet])

        #expect(model.canStop)
        await model.stop()

        #expect(model.state == .idle)
        #expect(capturer.stopCount == 1)
        #expect(capturer.isCapturing == false)
    }

    @Test("Stopping while idle does nothing")
    func stopWhileIdleIsHarmless() async {
        let (model, capturer) = makeModel()

        #expect(!model.canStop)
        await model.stop()
        await model.stop()

        #expect(model.state == .idle)
        #expect(capturer.stopCount == 0)
    }

    @Test("Capture can be started again after being stopped")
    func restartsAfterStop() async {
        let (model, capturer) = makeModel()
        await model.start(sources: [meet])
        await model.stop()

        await model.start(sources: [meet])

        #expect(model.state == .capturing)
        #expect(capturer.startCount == 2)
    }

    @Test("A refused start is reported as a failure, not as capture")
    func startFailureIsReported() async {
        let (model, capturer) = makeModel()
        capturer.startError = .permissionDenied

        await model.start(sources: [meet])

        #expect(model.state == failure(.permissionDenied))
        #expect(!model.canStop)
        #expect(model.canStart(sources: [meet]))
    }

    @Test("A selected application that is gone is named in the failure")
    func missingSourceIsNamed() async {
        let (model, capturer) = makeModel()
        capturer.startError = .sourcesUnavailable([meet.id])

        await model.start(sources: [meet, browser])

        #expect(model.state == .failed(message: "No longer running, so capture did not start: Meet"))
    }

    @Test("A stream that stops by itself moves capture into failure")
    func interruptionFailsCapture() async {
        let (model, capturer) = makeModel()
        await model.start(sources: [meet])

        capturer.interrupt(.interrupted("The stream was stopped by the user"))

        #expect(await wait { model.state != .capturing })
        #expect(model.state == .failed(message: "Capture stopped: The stream was stopped by the user"))
    }

    @Test("An interruption after a deliberate stop does not overwrite the idle state")
    func lateInterruptionIsIgnored() async {
        let (model, capturer) = makeModel()
        await model.start(sources: [meet])
        await model.stop()

        capturer.interrupt(.interrupted("The stream was stopped by the user"))
        try? await Task.sleep(for: .milliseconds(50))

        #expect(model.state == .idle)
    }

    @Test("Delivered samples reach the published activity")
    func activityFollowsDeliveredSamples() async {
        let (model, capturer) = makeModel()
        await model.start(sources: [meet])
        #expect(model.activity == .none)

        capturer.deliver(CapturedAudioSample(
            format: format,
            frameCount: 1_024,
            presentationTime: 12,
            peakAmplitude: 0.25
        ))

        #expect(await wait { model.activity.sampleCount == 1 })
        #expect(model.activity.frameCount == 1_024)
        #expect(model.activity.format == format)
        #expect(model.activity.peakAmplitude == 0.25)
    }

    @Test("A new capture starts from empty activity")
    func activityResetsOnStart() async {
        let (model, capturer) = makeModel()
        await model.start(sources: [meet])
        capturer.deliver(CapturedAudioSample(
            format: format,
            frameCount: 512,
            presentationTime: 1,
            peakAmplitude: 0.5
        ))
        #expect(await wait { model.activity.sampleCount == 1 })

        await model.stop()
        await model.start(sources: [meet])

        #expect(await wait { model.activity == .none })
    }
}
