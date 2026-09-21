//
//  MeetingTranscriptionGapTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// How a running meeting turns a stream of dropped-audio observations into
/// transcript material.
///
/// The condition these cover is the one a real meeting produced: recognition
/// fell behind capture and stayed behind for minutes, and the pipeline
/// reported roughly half a second of lost audio every half second for the
/// whole of it. Written out one by one those reports buried the meeting under
/// hundreds of near-identical blockquotes, which is truthful and unreadable.
/// What is checked here is that the document says the same thing once, that it
/// keeps saying separate things separately, and that nothing about the
/// durability of finalised speech changed to buy it.
@MainActor
@Suite("Meeting transcription gaps")
struct MeetingTranscriptionGapTests {

    // MARK: - Coalescing

    @Test("A sustained backlog leaves one gap marker rather than hundreds")
    func sustainedBacklogIsOneMarker() async throws {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 600)

        // 430 observations of half a second each, half a second apart: three
        // and a half minutes of a recogniser that never caught up. This is the
        // shape of the failure the interval exists to fix.
        for step in 0..<430 {
            let start = 600 + Double(step) * 0.5
            harness.dropAudio(seconds: 0.5, from: start, to: start + 0.5)
        }
        harness.reportRecognitionCaughtUp()

        #expect(await harness.wait { harness.writtenGaps.count == 1 })
        let gap = try #require(harness.writtenGaps.first)
        #expect(gap.reason == .audioDropped)
        #expect(gap.startTime == 600)
        #expect(gap.endTime == 815)
        #expect(abs(gap.duration - 215) < 0.001)
        #expect(gap.spansRange)
        #expect(harness.runtime.gapCount == 1)
        // Every note names the same moment, so the record's own comparison
        // turns minutes of observations into one write.
        let outstanding = harness.persistence.openGapNotes.compactMap { $0 }
        #expect(!outstanding.isEmpty)
        #expect(Set(outstanding) == [600])
    }

    @Test("An isolated short gap is still written, as a position rather than a range")
    func isolatedGapIsWritten() async throws {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 60)

        harness.dropAudio(seconds: 0.5, from: 30, to: 30.5, closesIncident: true)

        #expect(await harness.wait { harness.writtenGaps.count == 1 })
        let gap = try #require(harness.writtenGaps.first)
        #expect(gap.duration == 0.5)
        #expect(!gap.spansRange)
    }

    @Test("Two incidents with recognition working in between stay two incidents")
    func separateIncidentsStaySeparate() async {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 300)

        harness.dropAudio(seconds: 0.5, from: 10, to: 10.5)
        harness.dropAudio(seconds: 0.5, from: 10.5, to: 11, closesIncident: true)
        #expect(await harness.wait { harness.writtenGaps.count == 1 })

        harness.emitFinal("Recognition was working again here.")
        #expect(await harness.waitForSegments(1))

        harness.dropAudio(seconds: 0.5, from: 200, to: 200.5)
        harness.dropAudio(seconds: 0.5, from: 200.5, to: 201, closesIncident: true)
        #expect(await harness.wait { harness.writtenGaps.count == 2 })

        #expect(harness.writtenGaps.map(\.startTime) == [10, 200])
        #expect(harness.writtenGaps.map(\.endTime) == [11, 201])
        // The speech that was transcribed between them sits between them in
        // the document, because every marker is appended where it belongs.
        let order: [String] = harness.persistence.entries.compactMap { entry in
            switch entry {
            case .gap: "gap"
            case .segment: "span"
            default: nil
            }
        }
        #expect(order == ["gap", "span", "gap"])
    }

    @Test("Speech finalised during an incident still reaches the file while it is open")
    func speechDuringAnIncidentIsStillDurable() async {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 120)

        for step in 0..<40 {
            let start = 10 + Double(step) * 0.5
            harness.dropAudio(seconds: 0.5, from: start, to: start + 0.5)
        }
        harness.emitFinal("Heard in the middle of the trouble.")
        #expect(await harness.waitForSegments(1))
        #expect(harness.writtenGaps.isEmpty)

        harness.reportRecognitionCaughtUp()
        #expect(await harness.wait { harness.writtenGaps.count == 1 })
        #expect(harness.persistence.segments.map(\.text) == ["Heard in the middle of the trouble."])
    }

    // MARK: - Semantic boundaries

    @Test("A pause closes the incident that was open and never reaches across it")
    func pauseClosesTheIncident() async throws {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 60)
        harness.dropAudio(seconds: 0.5, from: 20, to: 20.5)
        harness.dropAudio(seconds: 0.5, from: 21, to: 21.5)

        await harness.pause(for: 600)
        #expect(await harness.wait { harness.writtenGaps.count == 1 })
        await harness.resume()
        harness.deliver(seconds: 1, count: 30)
        harness.dropAudio(seconds: 0.5, from: 70, to: 70.5, closesIncident: true)

        #expect(await harness.wait { harness.writtenGaps.count == 2 })
        let first = try #require(harness.writtenGaps.first)
        let second = try #require(harness.writtenGaps.last)
        // Media time, so the ten minutes the meeting spent paused are in
        // neither incident: the first ends before the pause and the second
        // begins after it.
        #expect(first.endTime == 21.5)
        #expect(second.startTime == 70)
        #expect(abs(first.duration - 1) < 0.001)
        #expect(second.duration == 0.5)
        // The pause marker sits between the two, where the pause happened.
        let order: [String] = harness.persistence.entries.compactMap { entry in
            switch entry {
            case .gap: "gap"
            case .paused: "pause"
            case .resumed: "resume"
            default: nil
            }
        }
        #expect(order == ["gap", "pause", "resume", "gap"])
    }

    @Test("A recogniser restart closes the incident before its own gap is written")
    func restartClosesTheIncident() async {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 60)
        harness.dropAudio(seconds: 0.5, from: 20, to: 20.5)
        harness.dropAudio(seconds: 0.5, from: 21, to: 21.5)

        #expect(await harness.failRecognition())

        #expect(await harness.wait { harness.writtenGaps.count == 2 })
        #expect(harness.writtenGaps.map(\.reason) == [.audioDropped, .recognizerRestarted])
        #expect(harness.writtenGaps.last?.startTime == nil)
    }

    @Test("Stopping with an incident open writes it once, before the session closes")
    func stopFlushesTheOpenIncident() async throws {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 60)
        for step in 0..<20 {
            let start = 30 + Double(step) * 0.5
            harness.dropAudio(seconds: 0.5, from: start, to: start + 0.5)
        }
        #expect(harness.writtenGaps.isEmpty)

        await harness.stop()

        #expect(harness.writtenGaps.count == 1)
        let gap = try #require(harness.writtenGaps.first)
        #expect(gap.startTime == 30)
        #expect(gap.endTime == 40)
        #expect(abs(gap.duration - 10) < 0.001)
        // The marker is in the document before the session was recorded as
        // finished, not after it.
        let indexOfGap = harness.persistence.entries.firstIndex { if case .gap = $0 { true } else { false } }
        let indexOfFinish = harness.persistence.entries.firstIndex {
            if case .finished = $0 { true } else { false }
        }
        #expect(indexOfGap != nil && indexOfFinish != nil && indexOfGap! < indexOfFinish!)
        #expect(harness.persistence.outcomes == [.completed])
    }

    @Test("Capture ending by itself closes the incident that was open")
    func captureInterruptionClosesTheIncident() async {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 60)
        harness.dropAudio(seconds: 0.5, from: 40, to: 40.5)

        harness.capturer.interrupt(.interrupted("Meet quit"))

        #expect(await harness.wait { !harness.runtime.isRunning })
        #expect(harness.writtenGaps.count == 1)
        #expect(harness.persistence.outcomes == [.interrupted])
    }

    @Test("A marker that cannot be written at stop fails the transcript rather than being claimed")
    func aFailedFlushAtStopIsReported() async {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 60)
        harness.emitFinal("Durable before the failure.")
        #expect(await harness.waitForSegments(1))
        harness.dropAudio(seconds: 0.5, from: 30, to: 30.5)
        #expect(await harness.wait { harness.persistence.hasOpenGapNote })

        harness.persistence.failAppends(with: TranscriptPersistenceError(.writeFailed))
        await harness.stop()

        // The marker did not reach the file, and nothing pretends it did: the
        // transcript is reported as failed and the meeting is not a completion.
        #expect(harness.writtenGaps.isEmpty)
        #expect(harness.runtime.persistenceState.failureMessage != nil)
        #expect(!harness.persistence.outcomes.contains(.completed))
        #expect(harness.persistence.segments.map(\.text) == ["Durable before the failure."])
        #expect(!harness.persistence.isOpen)
    }

    // MARK: - Surviving a ScribeKit that never finishes

    @Test("An open incident is noted in the session record and cleared when it is written")
    func openIncidentIsRecorded() async {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 60)

        harness.dropAudio(seconds: 0.5, from: 12, to: 12.5)
        #expect(await harness.wait { harness.persistence.hasOpenGapNote })
        // The record says where the trouble started and nothing else: the end
        // and the total were still being measured.
        #expect(harness.persistence.openGapNotes == [12])

        harness.dropAudio(seconds: 0.5, from: 13, to: 13.5, closesIncident: true)
        #expect(await harness.wait { harness.writtenGaps.count == 1 })
        #expect(!harness.persistence.hasOpenGapNote)
        #expect(harness.persistence.openGapNotes.count == 2)
    }

    @Test("A meeting that finishes leaves nothing outstanding for recovery to report")
    func finishedMeetingLeavesNoOpenIncident() async {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 60)
        harness.dropAudio(seconds: 0.5, from: 12, to: 12.5)
        #expect(await harness.wait { harness.persistence.hasOpenGapNote })

        await harness.stop()

        #expect(harness.writtenGaps.count == 1)
        #expect(!harness.persistence.hasOpenGapNote)
        // Exactly one marker, and no second one from the flush at the
        // boundary: closing an incident twice would be a duplicate notice.
        #expect(harness.persistence.entries.filter { if case .gap = $0 { true } else { false } }.count == 1)
    }

    @Test("Recognition catching up with nothing outstanding writes no marker at all")
    func catchingUpAloneWritesNothing() async {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 10)

        harness.reportRecognitionCaughtUp()
        harness.emitFinal("Nothing was ever lost here.")

        #expect(await harness.waitForSegments(1))
        #expect(harness.writtenGaps.isEmpty)
        #expect(harness.persistence.openGapNotes.isEmpty)
        #expect(harness.runtime.gapCount == 0)
    }

    // MARK: - The real failure, end to end

    @Test("Hundreds of half-second observations leave one blockquote in the file on disk")
    func sustainedBacklogIsOneBlockquoteInTheDocument() async throws {
        // The real writers against a real file: what a reader would actually
        // open after a meeting that spent three and a half minutes behind.
        let root = URL.temporaryDirectory.appending(
            path: "scribekit-gap-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let zone = TimeZone(identifier: "America/New_York")!
        let clock = ReliabilityHarness.Clock(start: Date(timeIntervalSinceReferenceDate: 0))
        let transcriber = FakeSpeechTranscriber()
        let runtime = MeetingRuntime(
            monitor: AudioCaptureActivityMonitor(minimumPublishInterval: .zero),
            transcriber: transcriber,
            persistence: MarkdownTranscriptStore(access: FakeSecurityScopedAccess(), timeZone: zone),
            audio: FakeAudioRetention(),
            elapsed: MeetingElapsedClock(now: { clock.now }, interval: nil),
            processActivity: FakeMeetingActivity(),
            now: { clock.now },
            makeCapturer: { FakeCapturer(consumer: $0) }
        )
        await runtime.prepare()
        await runtime.start(MeetingStartRequest(
            title: "Gap Regression",
            sources: [ReliabilityHarness.meet],
            destination: root,
            audioRetention: .none
        ))
        let layout = try #require(runtime.persistenceState.layout)

        transcriber.emit(.final(TranscriptSegment(
            text: "Before the trouble started.",
            startTime: 0,
            endTime: 2,
            state: .final,
            localeIdentifier: "en-US"
        )))
        for step in 0..<430 {
            let start = 600 + Double(step) * 0.5
            transcriber.emit(.interrupted(.audioDropped(
                seconds: 0.5,
                startTime: start,
                endTime: start + 0.5
            )))
        }
        transcriber.emit(.final(TranscriptSegment(
            text: "After it ended.",
            startTime: 820,
            endTime: 822,
            state: .final,
            localeIdentifier: "en-US"
        )))
        await runtime.stop()

        let markdown = try String(contentsOf: layout.transcriptURL, encoding: .utf8)
        let notices = markdown.components(separatedBy: "> **Transcription gap:**").count - 1
        #expect(notices == 1)
        #expect(markdown.contains(
            "> **Transcription gap:** approximately 215.0 seconds of audio was not transcribed "
            + "between 7:10:00 PM and 7:13:35 PM; recognition fell behind capture."
        ))
        // The speech either side of it is untouched and still in order.
        let document = TranscriptDocument.parse(markdown)
        #expect(document.spans.map(\.text) == ["Before the trouble started.", "After it ended."])
        #expect(markdown.contains("**Ended:**"))
    }

    // MARK: - What the interface is told

    @Test("Every observation still counts towards the audio the meeting could not transcribe")
    func liveTotalCountsEveryObservation() async {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 60)

        for step in 0..<20 {
            let start = 10 + Double(step) * 0.5
            harness.dropAudio(seconds: 0.5, from: start, to: start + 0.5)
        }

        #expect(await harness.wait { harness.runtime.transcript.untranscribedSeconds >= 10 })
        #expect(abs(harness.runtime.transcript.untranscribedSeconds - 10) < 0.001)
        // The live total is the sum of the observations; the document says the
        // same number once, when the incident closes.
        harness.reportRecognitionCaughtUp()
        #expect(await harness.wait { harness.writtenGaps.count == 1 })
        #expect(abs((harness.writtenGaps.first?.duration ?? 0) - 10) < 0.001)
    }
}
