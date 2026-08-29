//
//  LiveTranscriptModelTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@MainActor
@Suite("LiveTranscriptModel")
struct LiveTranscriptModelTests {

    /// Builds a segment as a recogniser would report one.
    ///
    /// - Parameters:
    ///   - text: The recognised text.
    ///   - state: Whether the recogniser finalised the span.
    ///   - start: Seconds from the start of the run.
    ///   - end: Seconds from the start of the run.
    /// - Returns: The segment.
    private func segment(
        _ text: String,
        _ state: TranscriptSegment.RecognitionState = .final,
        start: Double = 0,
        end: Double = 1
    ) -> TranscriptSegment {
        TranscriptSegment(
            text: text,
            startTime: start,
            endTime: end,
            state: state,
            localeIdentifier: "en-US"
        )
    }

    @Test("Each partial replaces the one before it")
    func partialsReplaceOneAnother() {
        let model = LiveTranscriptModel()
        model.begin()

        model.apply(.partial(segment("Today", .partial)))
        model.apply(.partial(segment("Today we", .partial)))
        model.apply(.partial(segment("Today we are", .partial)))

        #expect(model.partialSegment?.text == "Today we are")
        #expect(model.finalizedSegments.isEmpty)
    }

    @Test("Five partials and one final leave exactly one transcript entry")
    func partialsDoNotBecomeEntries() {
        let model = LiveTranscriptModel()
        model.begin()

        for text in ["Today", "Today we're", "Today we're going", "Today we're going to",
                     "Today we're going to learn Swift"] {
            model.apply(.partial(segment(text, .partial)))
        }
        model.apply(.final(segment("Today we're going to learn Swift.")))

        #expect(model.finalizedSegments.count == 1)
        #expect(model.finalizedSegments.first?.text == "Today we're going to learn Swift.")
        #expect(model.partialSegment == nil)
    }

    @Test("Finalised spans accumulate in the order they were finalised")
    func finalsAccumulateInOrder() {
        let model = LiveTranscriptModel()
        model.begin()

        model.apply(.final(segment("First.", start: 0, end: 2)))
        model.apply(.final(segment(" Second.", start: 2, end: 4)))

        #expect(model.finalizedSegments.map(\.displayText) == ["First.", "Second."])
        #expect(model.finalizedSegments.map(\.text) == ["First.", " Second."])
    }

    @Test("Recognised text is stored exactly as the recogniser reported it")
    func keepsRawText() {
        let model = LiveTranscriptModel()
        model.begin()

        model.apply(.final(segment(" a closure is a self contained block of code.")))

        #expect(model.finalizedSegments.first?.text == " a closure is a self contained block of code.")
    }

    @Test("An empty final span is not recorded as a transcript entry")
    func emptyFinalIsNotRecorded() {
        let model = LiveTranscriptModel()
        model.begin()
        model.apply(.partial(segment("Today", .partial)))

        model.apply(.final(segment("   ")))

        #expect(model.finalizedSegments.isEmpty)
        #expect(model.partialSegment == nil)
    }

    @Test("Dropped audio accumulates as untranscribed time")
    func recordsDroppedAudio() {
        let model = LiveTranscriptModel()
        model.begin()

        model.apply(.interrupted(.audioDropped(seconds: 0.5)))
        model.apply(.interrupted(.audioDropped(seconds: 1.25)))

        #expect(model.untranscribedSeconds == 1.75)
        #expect(model.lastInterruption == .audioDropped(seconds: 1.25))
    }

    @Test("A recogniser failure discards the hypothesis it had not finalised")
    func failureDiscardsPartial() {
        let model = LiveTranscriptModel()
        model.begin()
        model.apply(.partial(segment("Today we", .partial)))

        model.apply(.interrupted(.recognitionFailed(message: "resources")))

        #expect(model.partialSegment == nil)
        #expect(model.lastInterruption == .recognitionFailed(message: "resources"))
    }

    @Test("A new run starts from nothing")
    func beginClearsPreviousRun() {
        let model = LiveTranscriptModel()
        model.begin()
        model.apply(.final(segment("First run.")))
        model.apply(.interrupted(.audioDropped(seconds: 2)))

        model.begin()

        #expect(model.isEmpty)
        #expect(model.untranscribedSeconds == 0)
        #expect(model.lastInterruption == nil)
    }

    @Test("A segment's wall-clock time is its audio offset from the run's start")
    func placesSegmentsInWallClockTime() {
        let model = LiveTranscriptModel()
        let start = Date(timeIntervalSince1970: 1_000)
        model.begin(at: start)

        let placed = model.wallClockStart(of: segment("Later.", start: 90, end: 92))

        #expect(placed == start.addingTimeInterval(90))
    }

    @Test("Without a run there is no wall-clock time to report")
    func noWallClockBeforeARun() {
        let model = LiveTranscriptModel()

        #expect(model.wallClockStart(of: segment("Nothing.")) == nil)
    }
}
