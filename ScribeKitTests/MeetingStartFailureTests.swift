//
//  MeetingStartFailureTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// What a start that fails leaves behind.
///
/// The interest is not the message: it is that nothing stays running, the
/// process assertion is released, the interface is told something it can act
/// on, and the next start works once the dependency is corrected. A start that
/// half-failed and stayed active would stop every later meeting, because the
/// runtime allows one.
@MainActor
@Suite("Meeting start failures")
struct MeetingStartFailureTests {

    private let meet = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")
    private let destination = URL(filePath: "/tmp/scribekit-tests", directoryHint: .isDirectory)

    private struct Harness {
        let runtime: MeetingRuntime
        let capturer: FakeCapturer
        let transcriber: FakeSpeechTranscriber
        let persistence: FakeTranscriptPersistence
        let audio: FakeAudioRetention
        let activity: FakeMeetingActivity
    }

    /// Builds a runtime over doubles, prepared as the screen prepares it.
    private func makeHarness(
        availability: SpeechRecognitionAvailability = .available(localeIdentifier: "en-US")
    ) async -> Harness {
        let transcriber = FakeSpeechTranscriber()
        transcriber.availabilityResult = availability
        let persistence = FakeTranscriptPersistence()
        let audio = FakeAudioRetention()
        let activity = FakeMeetingActivity()
        var capturer: FakeCapturer!
        let runtime = MeetingRuntime(
            monitor: AudioCaptureActivityMonitor(minimumPublishInterval: .zero),
            transcriber: transcriber,
            persistence: persistence,
            audio: audio,
            processActivity: activity,
            makeCapturer: { consumer in
                capturer = FakeCapturer(consumer: consumer)
                return capturer
            }
        )
        await runtime.prepare()
        return Harness(
            runtime: runtime,
            capturer: capturer,
            transcriber: transcriber,
            persistence: persistence,
            audio: audio,
            activity: activity
        )
    }

    private func request(retention: AudioRetentionMode = .none) -> MeetingStartRequest {
        MeetingStartRequest(
            title: "Interval Twenty",
            sources: [meet],
            destination: destination,
            audioRetention: retention
        )
    }

    /// Asserts the runtime is holding nothing after a failed start.
    private func expectNothingHeld(_ harness: Harness) {
        #expect(!harness.runtime.isRunning)
        #expect(!harness.runtime.canStop)
        #expect(!harness.activity.isAsserted)
        #expect(harness.activity.beginCount == harness.activity.endCount)
        #expect(!harness.capturer.isCapturing)
        #expect(!harness.persistence.isOpen)
        #expect(!harness.audio.isOpen)
    }

    @Test("A session that cannot be created leaves nothing running and is explained")
    func sessionCreationFailure() async {
        let harness = await makeHarness()
        harness.persistence.failStart(with: TranscriptPersistenceError(.directoryCreationFailed))
        await harness.runtime.start(request())

        expectNothingHeld(harness)
        #expect(harness.runtime.persistenceState.failureMessage != nil)
        #expect(harness.runtime.outcome?.category == .startFailure)
        #expect(harness.runtime.outcome?.detail != nil)

        await harness.runtime.start(request())
        #expect(harness.runtime.isRunning)
        #expect(harness.runtime.captureState == .capturing)
        #expect(harness.runtime.outcome == nil)
        await harness.runtime.stop()
        #expect(harness.runtime.outcome?.category == .completed)
    }

    @Test("An audio file that cannot be created closes the transcript as a failure")
    func audioCreationFailure() async {
        let harness = await makeHarness()
        harness.audio.failStart(with: AudioRetentionError(.cannotCreateAudioFile))
        await harness.runtime.start(request(retention: .compressed))

        expectNothingHeld(harness)
        #expect(harness.persistence.outcomes.last == .failed)
        #expect(harness.runtime.outcome?.category == .startFailure)
    }

    @Test("A recogniser that will not start closes the transcript and rechecks availability")
    func recognitionStartFailure() async {
        let harness = await makeHarness()
        harness.transcriber.startError = .systemFailure("the recogniser refused")
        await harness.runtime.start(request())

        expectNothingHeld(harness)
        #expect(harness.persistence.outcomes.last == .failed)
        #expect(harness.runtime.transcriptionState.failureMessage?.contains("the recogniser refused") == true)
        #expect(harness.runtime.outcome?.category == .startFailure)

        await harness.runtime.start(request())
        #expect(harness.runtime.captureState == .capturing)
        await harness.runtime.stop()
    }

    @Test("Capture that will not start is a start failure, not an interruption")
    func captureStartFailure() async {
        let harness = await makeHarness()
        harness.capturer.startError = .permissionDenied
        await harness.runtime.start(request())

        expectNothingHeld(harness)
        #expect(harness.persistence.outcomes.last == .failed)
        #expect(harness.runtime.outcome?.category == .startFailure)
        #expect(harness.runtime.outcome?.detail?.contains("Screen & System Audio Recording") == true)
    }

    @Test("A remembered application that is no longer running is a retryable start failure")
    func unavailableSourceAtStart() async {
        let harness = await makeHarness()
        harness.capturer.startError = .sourcesUnavailable(["com.example.Meet"])
        await harness.runtime.start(request())

        expectNothingHeld(harness)
        #expect(harness.runtime.outcome?.category == .startFailure)
        #expect(harness.runtime.outcome?.detail?.contains("Meet") == true)

        harness.capturer.startError = nil
        await harness.runtime.start(request())
        #expect(harness.runtime.captureState == .capturing)
        await harness.runtime.stop()
        #expect(harness.runtime.outcome?.category == .completed)
    }

    @Test("A meeting refused for an uninstalled model leaves the runtime idle")
    func speechUnavailable() async {
        let harness = await makeHarness(availability: .modelNotInstalled(localeIdentifier: "fr-FR"))
        await harness.runtime.start(request())

        expectNothingHeld(harness)
        #expect(!harness.persistence.isOpen)
        #expect(harness.runtime.outcome == nil)
        #expect(harness.runtime.transcriptionState.failureMessage != nil)
    }

    @Test("An interrupted meeting is recorded as interrupted and allows another start")
    func interruptionIsNotAFailedStart() async {
        let harness = await makeHarness()
        await harness.runtime.start(request())
        #expect(harness.runtime.captureState == .capturing)

        harness.capturer.interrupt(.interrupted("the stream ended"))
        _ = await wait { !harness.runtime.isRunning }

        expectNothingHeld(harness)
        #expect(harness.persistence.outcomes.last == .interrupted)
        #expect(harness.runtime.outcome?.category == .interrupted)

        await harness.runtime.start(request())
        #expect(harness.runtime.captureState == .capturing)
        await harness.runtime.stop()
    }

    /// Waits briefly for a condition the runtime reaches on its own tasks.
    private func wait(for condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}
