//
//  TranscriptSegmentTests.swift
//  ScribeKitTests
//

import Testing
@testable import ScribeKit

@Suite("TranscriptSegment")
struct TranscriptSegmentTests {

    private func segment(
        _ text: String,
        start: Double = 1,
        end: Double = 3,
        state: TranscriptSegment.RecognitionState = .final
    ) -> TranscriptSegment {
        TranscriptSegment(
            text: text,
            startTime: start,
            endTime: end,
            state: state,
            localeIdentifier: "en-US"
        )
    }

    @Test("A span lasts from its start to its end")
    func reportsDuration() {
        #expect(segment("Hello.", start: 2, end: 5).duration == 3)
    }

    @Test("A span the recogniser reported backwards lasts no time rather than negative time")
    func clampsInvertedDuration() {
        #expect(segment("Hello.", start: 5, end: 2).duration == 0)
    }

    @Test("Display trims the joining space; the stored text keeps it")
    func trimsOnlyForDisplay() {
        let joined = segment(" A closure is a block of code.")

        #expect(joined.displayText == "A closure is a block of code.")
        #expect(joined.text == " A closure is a block of code.")
    }

    @Test("Two segments with the same text are still distinct entries")
    func identityIsNotText() {
        #expect(segment("Yes.") != segment("Yes."))
    }

    @Test("An event carries its segment, and an interruption carries none")
    func eventsExposeTheirSegment() {
        let final = segment("Done.")

        #expect(TranscriptionEvent.final(final).segment == final)
        #expect(TranscriptionEvent.partial(final).segment == final)
        #expect(TranscriptionEvent.interrupted(.audioDropped(seconds: 1)).segment == nil)
    }

    @Test("An interruption explains itself in the terms the user needs")
    func interruptionsExplainThemselves() {
        #expect(TranscriptionInterruption.audioDropped(seconds: 1.5).message.contains("1.5"))
        #expect(TranscriptionInterruption.recognitionFailed(message: "boom").message.contains("boom"))
    }
}
