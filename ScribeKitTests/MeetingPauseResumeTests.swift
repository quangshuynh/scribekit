//
//  MeetingPauseResumeTests.swift
//  ScribeKitTests
//

import Foundation
import Synchronization
import Testing
@testable import ScribeKit

/// Pausing and resuming one meeting, and the two timelines that have to stay
/// truthful across it: captured media time, which the transcript's offsets and
/// the retained recording share, and wall-clock time, which keeps running while
/// the meeting is paused.
@MainActor
@Suite("Pause and resume")
struct MeetingPauseResumeTests {

    private let meet = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")

    private let format = CapturedAudioFormat(
        sampleRate: 48_000,
        channelCount: 1,
        bitsPerChannel: 32,
        isFloat: true,
        isInterleaved: false
    )

    private let destination = URL(filePath: "/tmp/scribekit-tests", directoryHint: .isDirectory)

    /// A wall clock a test moves by hand, so a pause can last minutes without
    /// anything sleeping.
    private final class TestClock: @unchecked Sendable {
        private let value = Mutex(Date(timeIntervalSinceReferenceDate: 0))

        var now: Date { value.withLock { $0 } }

        func advance(_ seconds: TimeInterval) {
            value.withLock { $0 += seconds }
        }
    }

    private struct Meeting {
        let runtime: MeetingRuntime
        let capturer: FakeCapturer
        let transcriber: FakeSpeechTranscriber
        let persistence: FakeTranscriptPersistence
        let audio: FakeAudioRetention
        let clock: TestClock
    }

    /// Builds a meeting over doubles, with a clock the test drives.
    ///
    /// - Parameter retention: What the meeting is asked to keep of its audio.
    /// - Returns: The runtime and everything behind it.
    private func makeMeeting(retention: AudioRetentionMode = .none) async -> Meeting {
        let clock = TestClock()
        let transcriber = FakeSpeechTranscriber()
        let persistence = FakeTranscriptPersistence()
        let audio = FakeAudioRetention()
        var capturer: FakeCapturer!
        let runtime = MeetingRuntime(
            monitor: AudioCaptureActivityMonitor(minimumPublishInterval: .zero),
            transcriber: transcriber,
            persistence: persistence,
            audio: audio,
            elapsed: MeetingElapsedClock(now: { clock.now }, interval: nil),
            now: { clock.now },
            makeCapturer: { consumer in
                capturer = FakeCapturer(consumer: consumer)
                return capturer
            }
        )
        await runtime.prepare()
        await runtime.start(MeetingStartRequest(
            title: "Interval Twelve",
            sources: [meet],
            destination: destination,
            audioRetention: retention
        ))
        return Meeting(
            runtime: runtime,
            capturer: capturer,
            transcriber: transcriber,
            persistence: persistence,
            audio: audio,
            clock: clock
        )
    }

    /// A synthetic buffer of the shape ScreenCaptureKit delivers.
    ///
    /// - Parameter seconds: How much audio it carries.
    /// - Returns: A buffer ready to deliver.
    private func buffer(seconds: Double) -> CapturedPCMBuffer {
        let frames = Int(seconds * format.sampleRate)
        return CapturedPCMBuffer(
            format: format,
            frameCount: frames,
            presentationTime: 0,
            peakAmplitude: 0.25,
            samples: [Float](repeating: 0.25, count: frames)
        )
    }

    /// A finalised span, timed against the recognition run that reported it.
    ///
    /// - Parameters:
    ///   - text: The recognised text.
    ///   - start: Seconds from the start of the run, not of the meeting.
    /// - Returns: The segment.
    private func segment(_ text: String, start: Double) -> TranscriptSegment {
        TranscriptSegment(
            text: text,
            startTime: start,
            endTime: start + 1,
            state: .final,
            localeIdentifier: "en-US"
        )
    }

    /// Waits for a main-actor condition a background delivery will satisfy.
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

    /// The offsets of every finalised span the writer accepted.
    ///
    /// - Parameter persistence: The writer double.
    /// - Returns: The start offsets, in the order they were written.
    private func writtenOffsets(_ persistence: FakeTranscriptPersistence) -> [Double] {
        persistence.entries.compactMap {
            if case let .segment(segment) = $0 { segment.startTime } else { nil }
        }
    }

    // MARK: - Lifecycle

    @Test("A meeting moves from transcribing to paused and back to transcribing")
    func pauseAndResumeCycle() async {
        let meeting = await makeMeeting()
        #expect(meeting.runtime.status == .transcribing)
        #expect(meeting.runtime.canPause)

        await meeting.runtime.pause()
        #expect(meeting.runtime.status == .paused)
        #expect(meeting.runtime.captureState == .paused)
        #expect(meeting.runtime.canResume)
        #expect(!meeting.runtime.canPause)

        await meeting.runtime.resume()
        #expect(meeting.runtime.status == .transcribing)
        #expect(meeting.runtime.captureState == .capturing)
        #expect(meeting.runtime.canPause)
    }

    @Test("Pausing stops capture without finishing the meeting")
    func pauseStopsCaptureAndKeepsSessionOpen() async {
        let meeting = await makeMeeting(retention: .raw)
        await meeting.runtime.pause()

        #expect(meeting.capturer.stopCount == 1)
        #expect(!meeting.capturer.isCapturing)
        #expect(meeting.persistence.isOpen)
        #expect(meeting.persistence.outcomes.isEmpty)
        #expect(meeting.audio.isOpen)
        #expect(meeting.runtime.status.isActive)
    }

    @Test("Resuming continues the same session, transcript and recording")
    func resumeKeepsOneSetOfArtifacts() async {
        let meeting = await makeMeeting(retention: .raw)
        let layout = meeting.runtime.persistenceState.layout

        await meeting.runtime.pause()
        await meeting.runtime.resume()

        #expect(meeting.runtime.persistenceState.layout?.directory == layout?.directory)
        // One start each: nothing reopened a transcript or a recording.
        let starts = meeting.persistence.entries.filter { if case .started = $0 { true } else { false } }
        #expect(starts.count == 1)
        #expect(meeting.audio.entries.filter { if case .started = $0 { true } else { false } }.count == 1)
        #expect(meeting.capturer.configurations.count == 2)
        #expect(meeting.capturer.configurations[0] == meeting.capturer.configurations[1])
    }

    @Test("Resume captures the sources the meeting started with, not the current selection")
    func resumeUsesTheStartingSourceSet() async {
        let meeting = await makeMeeting()
        await meeting.runtime.pause()
        await meeting.runtime.resume()

        #expect(meeting.capturer.configurations.last?.sourceIDs == Set([meet.id]))
    }

    // MARK: - Media offsets

    @Test("Offsets continue from the captured duration rather than resetting to zero")
    func mediaOffsetsContinueAfterResume() async {
        let meeting = await makeMeeting()
        meeting.capturer.deliver(buffer(seconds: 132.4))
        meeting.transcriber.emit(.final(segment("Phrase A.", start: 130)))
        _ = await wait { writtenOffsets(meeting.persistence).count == 1 }

        await meeting.runtime.pause()
        meeting.clock.advance(300)
        await meeting.runtime.resume()

        // The resumed recogniser counts from its own first frame again.
        meeting.transcriber.emit(.final(segment("Phrase B.", start: 0.8)))
        _ = await wait { writtenOffsets(meeting.persistence).count == 2 }

        let offsets = writtenOffsets(meeting.persistence)
        #expect(offsets[0] == 130)
        #expect(abs(offsets[1] - 133.2) < 0.001)
        #expect(offsets[1] > offsets[0])
    }

    @Test("Repeated pauses keep media offsets monotonic and free of wall-clock time")
    func repeatedCyclesStayMonotonic() async {
        let meeting = await makeMeeting()
        for cycle in 0..<3 {
            meeting.capturer.deliver(buffer(seconds: 10))
            meeting.transcriber.emit(.final(segment("Cycle \(cycle).", start: 5)))
            _ = await wait { writtenOffsets(meeting.persistence).count == cycle + 1 }
            await meeting.runtime.pause()
            meeting.clock.advance(600)
            await meeting.runtime.resume()
        }

        let offsets = writtenOffsets(meeting.persistence)
        #expect(offsets == [5, 15, 25])
        #expect(zip(offsets, offsets.dropFirst()).allSatisfy { $0 < $1 })
        #expect(abs(meeting.runtime.capturedDuration - 30) < 0.001)
    }

    @Test("A gap's position after a resume is stated on the meeting's timeline")
    func droppedAudioPositionIsRebased() async {
        let meeting = await makeMeeting()
        meeting.capturer.deliver(buffer(seconds: 20))
        await meeting.runtime.pause()
        await meeting.runtime.resume()

        meeting.transcriber.emit(.interrupted(.audioDropped(seconds: 0.6, startTime: 2)))
        _ = await wait {
            meeting.persistence.entries.contains { if case .gap = $0 { true } else { false } }
        }

        let gaps: [TranscriptGap] = meeting.persistence.entries.compactMap {
            if case let .gap(gap) = $0 { gap } else { nil }
        }
        #expect(gaps.first?.startTime == 22)
    }

    // MARK: - Wall clock

    @Test("Wall-clock timestamps after a resume include the time spent paused")
    func wallClockIncludesPauseDuration() async {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var formatter = TranscriptMarkdownFormatter(startedAt: start, timeZone: TimeZone(identifier: "UTC")!)

        // 132.4 s captured, then a five-minute pause, then capture resumes.
        formatter.resume(at: start.addingTimeInterval(132.4 + 300), capturedDuration: 132.4)

        #expect(formatter.wallClock(offset: 130) == start.addingTimeInterval(130))
        let resumedSpan = formatter.wallClock(offset: 133.2)
        #expect(abs(resumedSpan.timeIntervalSince(start) - (133.2 + 300)) < 0.001)
        #expect(formatter.hasPaused)
    }

    @Test("A meeting that was never paused maps offsets exactly as it always did")
    func wallClockUnchangedWithoutPause() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let formatter = TranscriptMarkdownFormatter(startedAt: start, timeZone: TimeZone(identifier: "UTC")!)
        #expect(formatter.wallClock(offset: 42) == start.addingTimeInterval(42))
        #expect(!formatter.hasPaused)
    }

    @Test("The elapsed time the user sees is wall-clock meeting length, including the pause")
    func elapsedIsWallClock() async {
        let meeting = await makeMeeting()
        meeting.clock.advance(60)
        await meeting.runtime.pause()
        meeting.clock.advance(300)
        await meeting.runtime.resume()
        meeting.clock.advance(60)
        meeting.runtime.elapsed.refresh()

        #expect(meeting.runtime.elapsed.elapsed == 420)
        #expect(meeting.runtime.capturedDuration == 0)
    }

    @Test("Markers name the pause and the resume without calling either a lost recording")
    func markdownMarkersAreStructuralAndTruthful() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let formatter = TranscriptMarkdownFormatter(startedAt: start, timeZone: TimeZone(identifier: "UTC")!)
        let pausedAt = start.addingTimeInterval(130)
        let resumedAt = pausedAt.addingTimeInterval(300)

        let paused = formatter.paused(at: pausedAt)
        let resumed = formatter.resumed(at: resumedAt, pausedAt: pausedAt)

        #expect(paused.hasPrefix("> **Paused:** 12:02:10."))
        #expect(resumed.hasPrefix("> **Resumed:** 12:07:10, after 5 min 0 s paused."))
        for marker in [paused, resumed] {
            #expect(!marker.lowercased().contains("not transcribed"))
            #expect(!marker.lowercased().contains("gap"))
            #expect(marker.hasPrefix(">"))
        }
    }

    // MARK: - Retained audio

    @Test("A pause writes no audio and a resume appends straight after the last frame")
    func retainedAudioHasNoSyntheticSilence() async {
        let meeting = await makeMeeting(retention: .raw)
        meeting.capturer.deliver(buffer(seconds: 2))
        let framesBeforePause = meeting.audio.appendedFrames

        await meeting.runtime.pause()
        meeting.clock.advance(30)
        let framesWhilePaused = meeting.audio.appendedFrames
        await meeting.runtime.resume()
        meeting.capturer.deliver(buffer(seconds: 3))

        #expect(framesWhilePaused == framesBeforePause)
        #expect(meeting.audio.appendedFrames == Int(5 * format.sampleRate))
        #expect(meeting.audio.isOpen)
        #expect(meeting.audio.finishCount == 0)
        #expect(abs(meeting.runtime.capturedDuration - 5) < 0.001)
    }

    @Test("A review candidate's offset after a pause still names the same second of the recording")
    func reviewSeekStaysDirectAcrossAPause() async {
        let meeting = await makeMeeting(retention: .raw)
        meeting.capturer.deliver(buffer(seconds: 12))
        await meeting.runtime.pause()
        meeting.clock.advance(900)
        await meeting.runtime.resume()
        meeting.capturer.deliver(buffer(seconds: 4))

        meeting.transcriber.emit(.final(TranscriptSegment(
            text: "Uncertain phrase.",
            startTime: 1,
            endTime: 2,
            state: .final,
            localeIdentifier: "en-US",
            confidence: 0.2
        )))
        _ = await wait { writtenOffsets(meeting.persistence).count == 1 }

        // The span was recognised one second into the resumed run, which is
        // second 13 of the meeting — and second 13 of a recording that holds
        // 16 seconds of captured audio and not a frame of the 15-minute pause.
        #expect(writtenOffsets(meeting.persistence) == [13])
        #expect(meeting.audio.appendedFrames == Int(16 * format.sampleRate))
    }

    // MARK: - Stopping

    @Test("Stopping while paused finalises the recording, the transcript and the record")
    func stopWhilePausedFinalisesNormally() async {
        let meeting = await makeMeeting(retention: .raw)
        meeting.capturer.deliver(buffer(seconds: 4))
        await meeting.runtime.pause()
        meeting.clock.advance(120)

        await meeting.runtime.stop()

        #expect(meeting.runtime.status == .completed)
        #expect(meeting.persistence.outcomes == [.completed])
        #expect(!meeting.persistence.isOpen)
        #expect(meeting.audio.finishCount == 1)
        #expect(!meeting.audio.isOpen)
    }

    @Test("Quitting while paused goes through the same stop and finalisation")
    func quitWhilePausedStopsTheMeeting() async {
        let meeting = await makeMeeting(retention: .raw)
        meeting.capturer.deliver(buffer(seconds: 2))
        await meeting.runtime.pause()

        let finished = Mutex<Bool?>(nil)
        let coordinator = MeetingQuitCoordinator(
            runtime: meeting.runtime,
            confirmStop: { true },
            finish: { outcome in finished.withLock { $0 = outcome } }
        )
        // A paused meeting is an active one: quitting confirms and stops it
        // rather than terminating out from under an open transcript.
        #expect(coordinator.applicationShouldTerminate() == .terminateLater)
        _ = await wait { finished.withLock { $0 } == true }

        #expect(meeting.persistence.outcomes == [.completed])
        #expect(meeting.audio.finishCount == 1)
        #expect(!meeting.audio.isOpen)
    }

    // MARK: - Failure

    @Test("A resume the capture system refuses leaves the meeting paused and says why")
    func failedResumeStaysPaused() async {
        let meeting = await makeMeeting(retention: .raw)
        meeting.capturer.deliver(buffer(seconds: 3))
        await meeting.runtime.pause()

        meeting.capturer.startError = .sourcesUnavailable([meet.id])
        await meeting.runtime.resume()

        #expect(meeting.runtime.status == .paused)
        #expect(meeting.runtime.captureState == .paused)
        #expect(meeting.runtime.pauseFailureMessage?.contains("Meet") == true)
        #expect(meeting.persistence.isOpen)
        #expect(meeting.persistence.outcomes.isEmpty)
        #expect(meeting.audio.isOpen)
        #expect(meeting.audio.appendedFrames == Int(3 * format.sampleRate))
    }

    @Test("A source that disappeared is named rather than replaced, and a retry still works")
    func failedResumeCanBeRetried() async {
        let meeting = await makeMeeting()
        await meeting.runtime.pause()
        meeting.capturer.startError = .sourcesUnavailable([meet.id])
        await meeting.runtime.resume()
        #expect(meeting.runtime.canResume)

        meeting.capturer.startError = nil
        await meeting.runtime.resume()

        #expect(meeting.runtime.status == .transcribing)
        #expect(meeting.runtime.pauseFailureMessage == nil)
        #expect(meeting.capturer.configurations.allSatisfy { $0.sourceIDs == Set([meet.id]) })
    }

    @Test("A pause whose marker cannot be written fails the meeting rather than claiming a pause")
    func failedPauseMarkerFailsTheMeeting() async {
        let meeting = await makeMeeting()
        meeting.persistence.failPauseMarkers(with: TranscriptPersistenceError(.writeFailed))

        await meeting.runtime.pause()

        #expect(meeting.runtime.captureState != .paused)
        #expect(meeting.runtime.status.failureMessage != nil)
        #expect(meeting.persistence.outcomes == [.failed])
    }

    // MARK: - Recovery metadata

    @Test("A record written while paused says so, and a closed one does not")
    func recoveryMetadataIsHonestAboutPausing() {
        let started = Date(timeIntervalSinceReferenceDate: 0)
        let record = SessionRecoveryMetadata(
            sessionID: UUID(),
            title: "Interval Twelve",
            startedAt: started,
            sourceNames: ["Meet"],
            localeIdentifier: "en-US",
            status: .inProgress
        )
        #expect(!record.wasPausedWhenInterrupted)

        let paused = record.pausing(at: started.addingTimeInterval(132.4), capturedDuration: 132.4)
        #expect(paused.wasPausedWhenInterrupted)
        #expect(paused.status == .inProgress)
        #expect(paused.capturedDuration == 132.4)
        #expect(paused.markingInterruption(recordedAt: started).wasPausedWhenInterrupted)

        let resumed = paused.pausing(at: nil, capturedDuration: 132.4)
        #expect(!resumed.wasPausedWhenInterrupted)

        let closed = paused.closed(.completed, at: started.addingTimeInterval(500))
        #expect(closed.pausedAt == nil)
        #expect(!closed.wasPausedWhenInterrupted)
        #expect(closed.capturedDuration == 132.4)
    }

    @Test("A record from before pausing existed still decodes, with no pause claimed")
    func olderRecordsStillDecode() throws {
        let json = """
        {"schemaVersion":1,"sessionID":"\(UUID().uuidString)","title":"Older",\
        "startedAt":"2026-08-30T12:00:00Z","sourceNames":["Meet"],"localeIdentifier":"en-US",\
        "transcriptPath":"transcript.md","status":"inProgress"}
        """
        let record = try SessionRecoveryMetadata.decoded(from: Data(json.utf8))
        #expect(record.pausedAt == nil)
        #expect(record.capturedDuration == nil)
        #expect(!record.wasPausedWhenInterrupted)
    }

    // MARK: - Menu bar

    @Test("The menu bar offers Resume while paused and Pause while transcribing")
    func menuBarOffersTheRightControl() async {
        let meeting = await makeMeeting()
        let running = MeetingMenuBarPresentation(
            status: meeting.runtime.status,
            meeting: meeting.runtime.meeting,
            transcript: nil,
            audio: nil,
            canStop: meeting.runtime.canStop,
            canPause: meeting.runtime.canPause,
            canResume: meeting.runtime.canResume
        )
        #expect(running.canPause)
        #expect(!running.canResume)
        #expect(running.statusLine == "Transcribing")

        await meeting.runtime.pause()
        let paused = MeetingMenuBarPresentation(
            status: meeting.runtime.status,
            meeting: meeting.runtime.meeting,
            transcript: nil,
            audio: nil,
            canStop: meeting.runtime.canStop,
            canPause: meeting.runtime.canPause,
            canResume: meeting.runtime.canResume
        )
        #expect(paused.canResume)
        #expect(!paused.canPause)
        #expect(paused.canStop)
        #expect(paused.statusLine == "Paused")
        #expect(paused.showsElapsed)
    }

    // MARK: - Media clock

    @Test("The media clock counts captured audio, whatever the capture format is")
    func mediaClockCountsEveryFormatCorrectly() {
        let clock = CapturedMediaClock()
        clock.consume(buffer(seconds: 1.5))
        let sixteen = CapturedAudioFormat(
            sampleRate: 16_000,
            channelCount: 1,
            bitsPerChannel: 32,
            isFloat: true,
            isInterleaved: false
        )
        clock.consume(CapturedPCMBuffer(
            format: sixteen,
            frameCount: 8_000,
            presentationTime: 0,
            peakAmplitude: 0.1,
            samples: [Float](repeating: 0.1, count: 8_000)
        ))
        #expect(abs(clock.seconds - 2.0) < 0.0001)

        clock.reset()
        #expect(clock.seconds == 0)
    }
}
