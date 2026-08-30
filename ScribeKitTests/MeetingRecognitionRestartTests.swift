//
//  MeetingRecognitionRestartTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// What a recogniser that stops by itself may and may not do to a meeting.
///
/// A restart is a new recognition run, and a new run counts its own offsets
/// from its own first frame. The meeting's timeline does not restart with it,
/// and a recogniser that cannot be brought back is the end of the meeting
/// rather than a quiet subsystem death underneath a capture stream that keeps
/// running.
///
/// Deterministic injection throughout: the recogniser is a double, and the
/// failures are the ones it is told to report.
@MainActor
@Suite("Recogniser restarts")
struct MeetingRecognitionRestartTests {


    @Test("A recogniser restart continues the meeting's own media timeline")
    func restartKeepsOffsetsOnTheMeetingTimeline() async {
        let harness = ReliabilityHarness()
        await harness.start()

        harness.deliver(seconds: 1, count: 60)
        let before = harness.emitFinal("Before the restart.")
        #expect(await harness.waitForSegments(1))

        #expect(await harness.failRecognition())
        #expect(harness.runtime.transcriptionState == .transcribing)
        #expect(harness.runtime.captureState == .capturing)

        harness.deliver(seconds: 1, count: 60)
        let after = harness.emitFinal("After the restart.")
        #expect(await harness.waitForSegments(2))

        #expect(before == 60)
        #expect(after == 120)
        // The recogniser's own run started again at zero. The transcript's
        // offsets may not: offset t still has to name second t of the audio.
        #expect(harness.writtenOffsets == [60, 120])
        #expect(harness.persistence.gaps.contains { $0.reason == .recognizerRestarted })
    }

    @Test("Text finalised before a restart stays durable, once, in order")
    func restartDoesNotDuplicateOrLoseDurableText() async {
        let harness = ReliabilityHarness()
        await harness.start()

        harness.deliver(seconds: 1, count: 10)
        harness.emitFinal("First.")
        harness.deliver(seconds: 1, count: 10)
        harness.emitFinal("Second.")
        #expect(await harness.waitForSegments(2))

        #expect(await harness.failRecognition())
        harness.deliver(seconds: 1, count: 10)
        harness.emitFinal("Third.")
        #expect(await harness.waitForSegments(3))

        #expect(harness.persistence.segments.map(\.text) == ["First.", "Second.", "Third."])
        #expect(harness.writtenOffsets == [10, 20, 30])
    }

    @Test("A recogniser that will not come back ends the meeting instead of capturing into nothing")
    func terminalRecognitionFailureEndsTheMeeting() async {
        let harness = ReliabilityHarness()
        await harness.start(retention: .raw)
        harness.deliver(seconds: 1, count: 30)
        harness.emitFinal("Durable.")
        #expect(await harness.waitForSegments(1))

        var restarts = 0
        for _ in 0...MeetingRuntime.maximumRecoveryAttempts {
            guard await harness.failRecognition() else { break }
            restarts += 1
            harness.deliver(seconds: 1, count: 5)
        }

        #expect(restarts == MeetingRuntime.maximumRecoveryAttempts)
        #expect(await harness.wait {
            if case .failed = harness.runtime.transcriptionState { return true }
            return false
        })
        #expect(await harness.wait { !harness.runtime.isRunning })

        // Nothing is left running: no capture, no recogniser, no open
        // transcript, no open recording, and no power assertion.
        #expect(!harness.capturer.isCapturing)
        #expect(!harness.transcriber.isTranscribing)
        #expect(!harness.persistence.isOpen)
        #expect(!harness.audio.isOpen)
        #expect(!harness.activity.isAsserted)
        // And the meeting says what happened rather than claiming it finished.
        #expect(harness.runtime.status.failureMessage != nil)
        #expect(harness.persistence.outcomes == [.failed])
        #expect(harness.persistence.segments.map(\.text) == ["Durable."])
    }

    @Test("A restart that cannot start recognition again ends the meeting the same way")
    func failedRestartEndsTheMeeting() async {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 10)

        harness.transcriber.startError = .unavailable(.unsupportedLocale(localeIdentifier: "en-US"))
        harness.transcriber.emit(.interrupted(.recognitionFailed(message: "resources")))

        #expect(await harness.wait { !harness.runtime.isRunning })
        #expect(harness.runtime.status.failureMessage != nil)
        #expect(!harness.capturer.isCapturing)
        #expect(!harness.persistence.isOpen)
        #expect(harness.persistence.outcomes == [.failed])
        #expect(!harness.activity.isAsserted)
    }
}
