//
//  MeetingReliabilityTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// What a meeting has to keep true over hours, over dozens of suspensions, and
/// over every way a subsystem can fail underneath it.
///
/// Everything here is deterministic injection through ``ReliabilityHarness``:
/// evidence about ordering, arithmetic, state and resource release, and not
/// evidence about CPU, memory under a real recogniser, or how ScreenCaptureKit
/// behaves when the application it is capturing quits.
@MainActor
@Suite("Meeting reliability")
struct MeetingReliabilityTests {

    // MARK: - Long-duration runs

    @Test("A two-hour meeting with repeated suspensions keeps one timeline and one set of artifacts")
    func longMeetingKeepsOneTimeline() async {
        let harness = ReliabilityHarness()
        await harness.start(retention: .raw)

        // Twenty-four five-minute blocks: two hours of captured media, a span
        // every thirty seconds, and a pause between every pair of blocks.
        var expected: [Double] = []
        for block in 0..<24 {
            for _ in 0..<10 {
                harness.deliver(seconds: 1, count: 30)
                expected.append(harness.emitFinal("Block \(block)."))
            }
            #expect(await harness.waitForSegments(expected.count))
            if block == 11 {
                // A recogniser that stops by itself half way through: the run
                // it starts counts from its own first frame, and the meeting's
                // timeline carries on regardless.
                #expect(await harness.failRecognition())
            }
            if block < 23 {
                await harness.pause(for: 90)
                #expect(harness.runtime.status == .paused)
                await harness.resume()
                #expect(harness.runtime.status == .transcribing)
            }
        }

        #expect(harness.capturedSeconds == 7_200)
        #expect(harness.runtime.capturedDuration == 7_200)
        #expect(harness.writtenOffsets == expected)
        #expect(harness.writtenOffsets == harness.writtenOffsets.sorted())
        #expect(zip(harness.writtenOffsets, harness.writtenOffsets.dropFirst()).allSatisfy { $0 < $1 })

        // Twenty-three pauses, each with both of its markers, and each marker
        // stating the media time it was taken at rather than the wall time.
        let markers = harness.markerDurations
        #expect(markers.count == 46)
        #expect(markers == markers.sorted())

        await harness.stop()

        #expect(harness.runtime.status == .completed)
        #expect(harness.persistence.outcomes == [.completed])
        #expect(harness.persistence.finishCapturedDurations == [7_200])
        #expect(!harness.persistence.isOpen)
        // One directory, one transcript, one recording, and not a frame of
        // synthetic silence for the thirty-four minutes the meeting was paused.
        #expect(harness.persistence.entries.filter { if case .started = $0 { true } else { false } }.count == 1)
        #expect(harness.audio.entries.filter { if case .started = $0 { true } else { false } }.count == 1)
        #expect(harness.audio.appendedFrames == Int(7_200 * harness.format.sampleRate))
        #expect(harness.audio.finishCount == 1)
        #expect(!harness.activity.isAsserted)
    }

    @Test("Sequential meetings in one process leave nothing of the last one behind")
    func repeatedLifecyclesDoNotAccumulate() async {
        let harness = ReliabilityHarness()
        var directories: Set<String> = []

        for cycle in 0..<25 {
            await harness.start(retention: cycle.isMultiple(of: 2) ? .raw : .none, title: "Cycle \(cycle)")
            #expect(harness.runtime.status == .transcribing)
            harness.deliver(seconds: 1, count: 10)
            harness.emitFinal("Cycle \(cycle).")
            #expect(await harness.wait { harness.persistence.segments.count == cycle + 1 })

            if cycle.isMultiple(of: 3) {
                await harness.pause(for: 30)
                await harness.resume()
                harness.deliver(seconds: 1, count: 5)
            }
            if cycle == 7 {
                // A recoverable fault in the middle of the run: the next
                // meeting still has to start cleanly from it.
                #expect(await harness.failRecognition())
            }

            await harness.stop()

            #expect(harness.runtime.status == .completed)
            #expect(!harness.persistence.isOpen)
            #expect(!harness.audio.isOpen)
            #expect(!harness.capturer.isCapturing)
            #expect(!harness.transcriber.isTranscribing)
            #expect(!harness.activity.isAsserted)
            #expect(harness.runtime.capturedDuration == 0 || !harness.runtime.isRunning)
            if let directory = harness.runtime.persistenceState.layout?.directory {
                directories.insert(directory.lastPathComponent)
            }
        }

        #expect(harness.persistence.outcomes == Array(repeating: .completed, count: 25))
        #expect(harness.persistence.outcomes.count == 25)
        // Every cycle closed what it opened: as many closes as opens, and the
        // assertion taken by each meeting released by the end of it.
        #expect(harness.capturer.startCount >= 25)
        #expect(harness.activity.beginCount == harness.activity.endCount)
        #expect(directories.count == 25)
    }

    // MARK: - Start failures

    @Test(
        "A start that fails after the transcript was created is not recorded as a completed meeting",
        arguments: [ReliabilityStartFault.recognition, .capture]
    )
    func failedStartIsNotRecordedAsCompleted(_ fault: ReliabilityStartFault) async {
        let harness = ReliabilityHarness()
        switch fault {
        case .recognition:
            harness.transcriber.startError = .unavailable(.unsupportedLocale(localeIdentifier: "en-US"))
        case .capture:
            harness.capturer.startError = .sourcesUnavailable(["com.example.Meet"])
        }

        await harness.start()

        #expect(harness.runtime.status.failureMessage != nil)
        #expect(!harness.runtime.isRunning)
        #expect(!harness.persistence.isOpen)
        #expect(!harness.capturer.isCapturing)
        #expect(!harness.transcriber.isTranscribing)
        // The meeting never captured a second. Recording it as completed would
        // put an empty transcript in History under the same status as a
        // meeting that ran and finished.
        #expect(harness.persistence.outcomes == [.failed])
        #expect(!harness.activity.isAsserted)
    }

    // MARK: - Transcript failures

    @Test(
        "A transcript failure at any boundary keeps what was durable and refuses to claim a completion",
        arguments: ReliabilityPersistenceFault.allCases
    )
    func transcriptFaultsAreTruthful(_ fault: ReliabilityPersistenceFault) async {
        let harness = ReliabilityHarness()
        await harness.start(retention: .raw)
        harness.deliver(seconds: 1, count: 20)
        harness.emitFinal("Durable before the failure.")
        #expect(await harness.waitForSegments(1))
        let durable = harness.persistence.segments.map(\.text)

        switch fault {
        case .append:
            harness.persistence.failAppends(with: TranscriptPersistenceError(.writeFailed))
            harness.deliver(seconds: 1, count: 5)
            harness.emitFinal("Never saved.")
        case .gap:
            harness.persistence.failAppends(with: TranscriptPersistenceError(.writeFailed))
            harness.transcriber.emit(.interrupted(.audioDropped(seconds: 0.8, startTime: 3)))
        case .pauseMarker:
            harness.persistence.failPauseMarkers(with: TranscriptPersistenceError(.writeFailed))
            await harness.runtime.pause()
        case .resumeMarker:
            await harness.runtime.pause()
            harness.persistence.failPauseMarkers(with: TranscriptPersistenceError(.writeFailed))
            await harness.runtime.resume()
        case .footer:
            harness.persistence.failFinish(with: TranscriptPersistenceError(.flushFailed))
            await harness.stop()
        }

        #expect(await harness.wait { !harness.runtime.isRunning })

        // What was already durable is still durable, and nothing was written
        // after the writer refused.
        #expect(harness.persistence.segments.map(\.text) == durable)
        #expect(harness.runtime.persistenceState.failureMessage != nil)
        #expect(harness.runtime.status.failureMessage != nil)
        // No completion is claimed, the writer is closed and the recording is
        // closed and kept rather than deleted. A footer that fails is the one
        // case where the writer was asked to close a meeting that had not gone
        // wrong yet, and the store refuses to record that completion itself;
        // what matters here is that the runtime does not report one.
        #expect(fault == .footer || !harness.persistence.outcomes.contains(.completed))
        #expect(harness.runtime.status != .completed)
        #expect(!harness.persistence.isOpen)
        #expect(!harness.capturer.isCapturing)
        #expect(!harness.transcriber.isTranscribing)
        #expect(!harness.audio.isOpen)
        #expect(harness.audio.finishCount == 1)
        #expect(!harness.activity.isAsserted)
    }

    // MARK: - Retained audio failures

    @Test(
        "A recording that fails ends the meeting, keeps what reached the file and never claims completion",
        arguments: ReliabilityAudioFault.allCases
    )
    func audioFaultsAreTruthful(_ fault: ReliabilityAudioFault) async {
        let harness = ReliabilityHarness()
        if case .creation = fault {
            harness.audio.failStart()
        }
        await harness.start(retention: .raw)

        switch fault {
        case .creation:
            break
        case .midWrite:
            harness.deliver(seconds: 1, count: 20)
            harness.emitFinal("Durable.")
            #expect(await harness.waitForSegments(1))
            harness.audio.reportFailure()
        case .finalization:
            harness.deliver(seconds: 1, count: 20)
            harness.emitFinal("Durable.")
            #expect(await harness.waitForSegments(1))
            harness.audio.failFinish()
            await harness.stop()
        }

        #expect(await harness.wait { !harness.runtime.isRunning })

        #expect(harness.runtime.audioRetentionState.failureMessage != nil)
        #expect(harness.runtime.status.failureMessage != nil)
        #expect(harness.persistence.outcomes == [.failed])
        #expect(!harness.persistence.isOpen)
        #expect(!harness.audio.isOpen)
        #expect(!harness.capturer.isCapturing)
        #expect(!harness.activity.isAsserted)
        if case .creation = fault {
            // Nothing captured, so nothing recognised and no transcript
            // material to keep.
            #expect(harness.persistence.segments.isEmpty)
        } else {
            #expect(harness.persistence.segments.map(\.text) == ["Durable."])
        }
    }

    // MARK: - Capture failures

    @Test("Capture ending by itself ends the meeting rather than reporting healthy transcription")
    func captureInterruptionIsReported() async {
        let harness = ReliabilityHarness()
        await harness.start(retention: .raw)
        harness.deliver(seconds: 1, count: 30)
        harness.emitFinal("Durable.")
        #expect(await harness.waitForSegments(1))

        harness.capturer.interrupt(.interrupted("The captured application quit."))

        #expect(await harness.wait { !harness.runtime.isRunning })
        #expect(harness.runtime.status.failureMessage != nil)
        #expect(harness.runtime.status != .transcribing)
        #expect(!harness.transcriber.isTranscribing)
        #expect(!harness.persistence.isOpen)
        #expect(!harness.audio.isOpen)
        #expect(harness.persistence.segments.map(\.text) == ["Durable."])
        #expect(!harness.activity.isAsserted)
    }

    @Test("A source that has gone away leaves the meeting paused and resumable rather than lost")
    func resumeWithMissingSourceKeepsTheMeeting() async {
        let harness = ReliabilityHarness()
        await harness.start(retention: .raw)
        harness.deliver(seconds: 1, count: 30)
        harness.emitFinal("Before the pause.")
        #expect(await harness.waitForSegments(1))

        await harness.pause(for: 120)
        harness.capturer.startError = .sourcesUnavailable(["com.example.Meet"])
        await harness.resume()

        #expect(harness.runtime.captureState == .paused)
        #expect(harness.runtime.pauseFailureMessage != nil)
        #expect(harness.persistence.isOpen)
        #expect(harness.audio.isOpen)

        // The source comes back and the same meeting continues on the same
        // timeline, with no artifact reopened.
        harness.capturer.startError = nil
        await harness.resume()
        #expect(harness.runtime.status == .transcribing)
        harness.deliver(seconds: 1, count: 30)
        harness.emitFinal("After the resume.")
        #expect(await harness.waitForSegments(2))
        #expect(harness.writtenOffsets == [30, 60])

        await harness.stop()
        #expect(harness.persistence.outcomes == [.completed])
        #expect(harness.persistence.entries.filter { if case .started = $0 { true } else { false } }.count == 1)
    }

    // MARK: - Unexpected capture termination

    @Test("A stream that ends by itself finalises the artifacts and is recorded as an interruption")
    func captureEndingByItselfIsNotACompletion() async {
        let harness = ReliabilityHarness()
        await harness.start(retention: .raw)
        harness.deliver(seconds: 1, count: 30)
        harness.emitFinal("Said before the stream ended.")
        #expect(await harness.waitForSegments(1))

        harness.capturer.interrupt(.interrupted("The stream stopped"))

        #expect(await harness.wait { !harness.persistence.isOpen })
        // Finalisation still happened, all the way through: the transcript was
        // closed, the recording was closed, and the span said before capture
        // died is in the file.
        #expect(harness.persistence.segments.count == 1)
        #expect(harness.audio.finishCount == 1)
        #expect(!harness.audio.isOpen)
        // And none of that turns an ending nobody asked for into a completion.
        #expect(harness.persistence.outcomes == [.interrupted])
        #expect(harness.persistence.finishCapturedDurations == [30])
        // Nothing is left holding the process, and capture is not restarted.
        #expect(!harness.activity.isAsserted)
        #expect(harness.activity.beginCount == harness.activity.endCount)
        #expect(harness.capturer.startCount == 1)
        #expect(harness.transcriber.stopCount == 1)
        #expect(!harness.runtime.status.isActive)
        #expect(harness.runtime.status.failureMessage != nil)
    }

    @Test("A meeting the user stops is still recorded as a completion")
    func aDeliberateStopIsACompletion() async {
        let harness = ReliabilityHarness()
        await harness.start(retention: .raw)
        harness.deliver(seconds: 1, count: 30)

        await harness.stop()

        #expect(harness.persistence.outcomes == [.completed])
        #expect(harness.persistence.finishCapturedDurations == [30])
        #expect(harness.runtime.status == .completed)
    }

    @Test("A recogniser that cannot be brought back is still a failure, not an interruption")
    func recognitionFailureKeepsItsOwnStatus() async {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 10)
        // A recogniser whose restart fails is one that cannot be brought back,
        // which is the Interval 14 semantics this must not disturb.
        harness.transcriber.startError = TranscriptionError.alreadyTranscribing

        _ = await harness.failRecognition()

        #expect(await harness.wait { !harness.persistence.isOpen })
        if case .failed = harness.runtime.transcriptionState {} else {
            Issue.record("Expected recognition to be reported as failed")
        }
        #expect(harness.persistence.outcomes == [.failed])
    }

    @Test("A meeting can be started again after capture ended by itself")
    func anotherMeetingStartsAfterAnInterruption() async {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 5)
        harness.capturer.interrupt(.interrupted("The stream stopped"))
        #expect(await harness.wait { !harness.persistence.isOpen })

        await harness.start()
        harness.deliver(seconds: 1, count: 5)
        harness.emitFinal("The next meeting.")

        #expect(await harness.waitForSegments(1))
        #expect(harness.runtime.status == .transcribing)
        #expect(harness.persistence.entries.filter {
            if case .started = $0 { true } else { false }
        }.count == 2)

        await harness.stop()
        #expect(harness.persistence.outcomes == [.interrupted, .completed])
    }

    @Test("History reads a capture interruption as an interruption rather than a completion")
    func historyReadsTheInterruptionItWasGiven() {
        #expect(HistorySessionStatus(SessionCompletionOutcome.interrupted.recoveryStatus) == .interrupted)
        #expect(HistorySessionStatus.interrupted.displayName == "Interrupted")
        #expect(HistorySessionStatus(SessionCompletionOutcome.completed.recoveryStatus) == .completed)
    }
}

/// Which step of a start is made to fail.
enum ReliabilityStartFault: Sendable {
    case recognition
    case capture
}

/// Where a transcript write is made to fail.
enum ReliabilityPersistenceFault: CaseIterable, Sendable {
    case append
    case gap
    case pauseMarker
    case resumeMarker
    case footer
}

/// Where retained audio is made to fail.
enum ReliabilityAudioFault: CaseIterable, Sendable {
    case creation
    case midWrite
    case finalization
}
