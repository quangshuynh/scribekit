//
//  TranscriptMarkdownFormatterTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@Suite("TranscriptMarkdownFormatter")
struct TranscriptMarkdownFormatterTests {

    /// A fixed zone, so a golden string is the same wherever the tests run.
    private let zone = TimeZone(identifier: "America/New_York")!

    /// 31 August 2026, 11:00:00 in ``zone``.
    private var startedAt: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 11, minute: 0))!
    }

    /// A formatter over the fixed session start.
    private func makeFormatter() -> TranscriptMarkdownFormatter {
        TranscriptMarkdownFormatter(startedAt: startedAt, timeZone: zone)
    }

    /// A finalised span, as a recogniser reports one.
    ///
    /// - Parameters:
    ///   - text: The recognised text.
    ///   - start: Seconds from the start of the run.
    ///   - state: Whether the recogniser finalised it.
    /// - Returns: The segment.
    private func segment(
        _ text: String,
        start: Double,
        state: TranscriptSegment.RecognitionState = .final
    ) -> TranscriptSegment {
        TranscriptSegment(
            text: text,
            startTime: start,
            endTime: start + 2,
            state: state,
            localeIdentifier: "en-US"
        )
    }

    @Test("The header states only what ScribeKit knows about the meeting")
    func headerIsDeterministic() {
        let formatter = makeFormatter()

        let header = formatter.header(
            title: "iOS Training - Day 2",
            sourceNames: ["Microsoft Teams", "Safari"],
            localeIdentifier: "en-US"
        )

        #expect(header == """
            # iOS Training - Day 2

            **Date:** 2026-08-31
            **Started:** 11:00 AM
            **Sources:** Microsoft Teams, Safari
            **Language:** en-US
            **Captured by:** ScribeKit

            ## Transcript


            """)
    }

    @Test("A meeting with no sources omits the field rather than inventing one")
    func headerOmitsUnknownFields() {
        let formatter = makeFormatter()

        let header = formatter.header(title: "Untitled Meeting", sourceNames: [], localeIdentifier: "en-US")

        #expect(!header.contains("Sources"))
        #expect(!header.contains("Ended"))
    }

    @Test("A segment is timed by session start plus its audio offset")
    func segmentUsesWallClockFromOffset() {
        var formatter = makeFormatter()

        let block = formatter.finalSegment(segment("Today we are learning about closures.", start: 242))

        #expect(block == """
            ### 11:04 AM

            **11:04:02**

            Today we are learning about closures.


            """)
    }

    @Test("A minute heading is written once, when the minute changes")
    func minuteHeadingsAppearOncePerMinute() {
        var formatter = makeFormatter()

        let first = formatter.finalSegment(segment("One.", start: 242))
        let second = formatter.finalSegment(segment("Two.", start: 250))
        let third = formatter.finalSegment(segment("Three.", start: 302))

        #expect(first.contains("### 11:04 AM"))
        #expect(!second.contains("###"))
        #expect(second.contains("**11:04:10**"))
        #expect(third.contains("### 11:05 AM"))
        #expect(third.contains("**11:05:02**"))
    }

    @Test("Midnight and noon are written as 12, not as 0")
    func twelveHourClockEdges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 0, minute: 5))!
        var formatter = TranscriptMarkdownFormatter(startedAt: midnight, timeZone: zone)

        let first = formatter.finalSegment(segment("Late.", start: 0))
        let noon = formatter.finalSegment(segment("Midday.", start: 12 * 3_600 - 300))

        #expect(first.contains("### 12:05 AM"))
        #expect(noon.contains("### 12:00 PM"))
    }

    @Test("Recognised text is written exactly as it was finalised")
    func textIsNotRewritten() {
        var formatter = makeFormatter()
        let recognised = "asking and await is *not* what I said #closures"

        let block = formatter.finalSegment(segment(recognised, start: 0))

        #expect(block.contains(recognised))
    }

    @Test("Multiline recognised text keeps its line breaks")
    func multilineTextIsPreserved() {
        var formatter = makeFormatter()

        let block = formatter.finalSegment(segment("First line.\nSecond line.", start: 0))

        #expect(block.hasSuffix("First line.\nSecond line.\n\n"))
    }

    @Test("The space that joins one span to the previous one is not written")
    func joiningWhitespaceIsTrimmed() {
        var formatter = makeFormatter()

        let block = formatter.finalSegment(segment(" A closure is a block of code.", start: 0))

        #expect(block.contains("\n\nA closure is a block of code.\n\n"))
    }

    @Test("A gap with a known position states where it fell")
    func positionalGapIsFormatted() {
        let formatter = makeFormatter()

        let block = formatter.gap(TranscriptGap(startTime: 271.4, duration: 0.8, reason: .audioDropped))

        #expect(block == """
            > **Transcription gap:** approximately 0.8 seconds of audio around 11:04:31 \
            was not transcribed; recognition fell behind capture.


            """)
    }

    @Test("A gap with no known position claims none")
    func nonPositionalGapIsFormatted() {
        let formatter = makeFormatter()

        let block = formatter.gap(TranscriptGap(duration: 2.35, reason: .recognizerRestarted))

        #expect(block == """
            > **Transcription gap:** approximately 2.4 seconds of audio \
            was not transcribed; the recogniser was restarted.


            """)
    }

    @Test("A gap does not open a minute heading of its own")
    func gapDoesNotDisturbMinuteHeadings() {
        var formatter = makeFormatter()
        _ = formatter.finalSegment(segment("One.", start: 0))

        _ = formatter.gap(TranscriptGap(startTime: 200, duration: 1, reason: .audioDropped))
        let next = formatter.finalSegment(segment("Two.", start: 30))

        #expect(!next.contains("###"))
    }

    @Test("The footer records completion without rewriting the header")
    func footerRecordsCompletion() {
        let formatter = makeFormatter()

        let footer = formatter.footer(endedAt: startedAt.addingTimeInterval(2_832))

        #expect(footer == """
            ---

            **Ended:** 11:47 AM
            **Duration:** 47 min 12 s

            """)
    }

    @Test("A duration is described in the coarsest useful unit")
    func durationDescriptions() {
        #expect(TranscriptMarkdownFormatter.durationDescription(38) == "38 s")
        #expect(TranscriptMarkdownFormatter.durationDescription(72) == "1 min 12 s")
        #expect(TranscriptMarkdownFormatter.durationDescription(8_040) == "2 h 14 min")
        #expect(TranscriptMarkdownFormatter.durationDescription(-5) == "0 s")
    }

    @Test("A whole session renders as one readable Markdown document")
    func goldenDocument() {
        var formatter = makeFormatter()
        var document = formatter.header(
            title: "iOS Training - Day 2",
            sourceNames: ["Microsoft Teams"],
            localeIdentifier: "en-US"
        )
        document += formatter.finalSegment(segment("Today we're going to start by talking about closures in Swift.", start: 242))
        document += formatter.finalSegment(segment("A closure is essentially a self-contained block of code.", start: 302))
        document += formatter.gap(TranscriptGap(startTime: 280, duration: 0.8, reason: .audioDropped))
        document += formatter.footer(endedAt: startedAt.addingTimeInterval(300))

        #expect(document == """
            # iOS Training - Day 2

            **Date:** 2026-08-31
            **Started:** 11:00 AM
            **Sources:** Microsoft Teams
            **Language:** en-US
            **Captured by:** ScribeKit

            ## Transcript

            ### 11:04 AM

            **11:04:02**

            Today we're going to start by talking about closures in Swift.

            ### 11:05 AM

            **11:05:02**

            A closure is essentially a self-contained block of code.

            > **Transcription gap:** approximately 0.8 seconds of audio around 11:04:40 \
            was not transcribed; recognition fell behind capture.

            ---

            **Ended:** 11:05 AM
            **Duration:** 5 min 0 s

            """)
    }

    // MARK: - Interruption note

    @Test("The interruption note names the moment it was recorded, not the crash")
    func interruptionNoteIsGolden() {
        let recordedAt = startedAt.addingTimeInterval(3 * 3_600 + 7 * 60)

        let note = TranscriptMarkdownFormatter.interruptionNotice(recordedAt: recordedAt, timeZone: zone)

        #expect(note == """
            ---

            > **Session interrupted.** ScribeKit stopped before this meeting was finished, \
            so the transcript ends at the last speech that reached the file. \
            When it stopped is not known, and nothing was transcribed after that point. \
            Interruption recorded by ScribeKit on 2026-08-31 at 2:07 PM.


            """)
    }

    @Test("The interruption note is ScribeKit's own remark, not something anyone said")
    func interruptionNoteIsStructuralNotSpeech() {
        let note = TranscriptMarkdownFormatter.interruptionNotice(recordedAt: startedAt, timeZone: zone)

        #expect(note.contains("> **Session interrupted.**"))
        #expect(!note.contains("**11:00:00**"))
    }

    @Test("The note claims no duration and no end for the meeting")
    func interruptionNoteClaimsNoTiming() {
        let note = TranscriptMarkdownFormatter.interruptionNotice(recordedAt: startedAt, timeZone: zone)

        #expect(!note.contains("Duration"))
        #expect(!note.contains("**Ended:**"))
        #expect(!note.contains("seconds"))
    }

    @Test("The note is appended, so a transcript keeps everything before it")
    func interruptionNoteOnlyAdds() {
        var formatter = makeFormatter()
        let transcript = formatter.header(title: "A meeting", sourceNames: [], localeIdentifier: "en-US")
            + formatter.finalSegment(segment("Recognised speech.", start: 0))

        let annotated = transcript
            + TranscriptMarkdownFormatter.interruptionNotice(recordedAt: startedAt, timeZone: zone)

        #expect(annotated.hasPrefix(transcript))
        #expect(annotated.contains("Recognised speech."))
    }
}
