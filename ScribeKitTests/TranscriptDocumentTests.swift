//
//  TranscriptDocumentTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// Builds transcripts with the formatter ScribeKit actually writes with, so
/// the parser is checked against the real document rather than against a
/// second author's idea of it.
nonisolated enum TranscriptFixture {

    /// The zone fixtures are written in.
    static let zone = TimeZone(identifier: "America/New_York")!

    /// 29 August 2026, 14:01:00 UTC — 10:01 in the fixture zone.
    static let startedAt = Date(timeIntervalSince1970: 1_788_012_060)

    /// A finished transcript with a header, spans, a gap and a footer.
    ///
    /// - Parameters:
    ///   - title: The meeting's title.
    ///   - sourceNames: The applications the header names.
    ///   - texts: The recognised spans, one every twenty seconds.
    ///   - includesGap: Whether a transcription-gap blockquote is written.
    ///   - includesFooter: Whether the closing block is written.
    ///   - includesInterruption: Whether recovery's interruption notice is
    ///     appended.
    /// - Returns: The Markdown ScribeKit would have written.
    static func transcript(
        title: String = "Closures Walkthrough",
        sourceNames: [String] = ["QuickTime Player"],
        texts: [String],
        includesGap: Bool = false,
        includesFooter: Bool = true,
        includesInterruption: Bool = false
    ) -> String {
        var formatter = TranscriptMarkdownFormatter(startedAt: startedAt, timeZone: zone)
        var markdown = formatter.header(
            title: title,
            sourceNames: sourceNames,
            localeIdentifier: "en-US"
        )
        for (index, text) in texts.enumerated() {
            markdown += formatter.finalSegment(TranscriptSegment(
                text: text,
                startTime: Double(index) * 20,
                endTime: Double(index) * 20 + 4,
                state: .final,
                localeIdentifier: "en-US"
            ))
            if includesGap, index == 0 {
                markdown += formatter.gap(TranscriptGap(
                    startTime: 12,
                    duration: 0.8,
                    reason: .audioDropped
                ))
            }
        }
        if includesFooter {
            markdown += formatter.footer(endedAt: startedAt.addingTimeInterval(120))
        }
        if includesInterruption {
            markdown += TranscriptMarkdownFormatter.interruptionNotice(
                recordedAt: startedAt.addingTimeInterval(3_600),
                timeZone: zone
            )
        }
        return markdown
    }
}

@Suite("TranscriptDocument")
struct TranscriptDocumentTests {

    @Test("A written transcript reads back as its title, header fields and spans")
    func parsesAWrittenTranscript() throws {
        let markdown = TranscriptFixture.transcript(texts: [
            "Today, we are learning about closures in Swift.",
            "A closure captures the variables it refers to."
        ])

        let document = TranscriptDocument.parse(markdown)

        #expect(document.isScribeKitTranscript)
        #expect(document.title == "Closures Walkthrough")
        #expect(document.sourceNames == ["QuickTime Player"])
        #expect(document.localeIdentifier == "en-US")
        #expect(document.headerValue(TranscriptDocument.dateKey) == "2026-08-29")
        #expect(document.spans.map(\.text) == [
            "Today, we are learning about closures in Swift.",
            "A closure captures the variables it refers to."
        ])
    }

    @Test("A span keeps the clock time and the minute heading the file states")
    func spansKeepTheirTimestamps() throws {
        let markdown = TranscriptFixture.transcript(texts: [
            "First sentence.",
            "Second sentence.",
            "Third sentence, a minute later."
        ])

        let document = TranscriptDocument.parse(markdown)

        #expect(document.spans.count == 3)
        #expect(document.spans[0].clock == "10:01:00 AM")
        #expect(document.spans[0].heading == "10:01 AM")
        #expect(document.spans[0].timestampDescription == "10:01:00 AM")
        #expect(document.spans[1].clock == "10:01:20 AM")
        #expect(document.spans[1].heading == "10:01 AM")
        #expect(document.spans[2].clock == "10:01:40 AM")
        #expect(document.spans.map(\.index) == [0, 1, 2])
    }

    @Test("A transcript written before periods were stated still reads back")
    func legacySpansKeepTheirTimestamps() throws {
        // Exactly what ScribeKit wrote before Interval 19: the seconds line
        // carried no period, and the minute heading above it did.
        let markdown = """
            # Closures Walkthrough

            **Date:** 2026-08-29
            **Started:** 10:01 AM
            **Sources:** QuickTime Player
            **Language:** en-US
            **Captured by:** ScribeKit

            ## Transcript

            ### 10:01 AM

            **10:01:00**

            First sentence.

            ### 1:28 PM

            **13:28:04**

            Second sentence.

            ---

            **Ended:** 1:29 PM
            **Duration:** 3 h 28 min

            """

        let document = TranscriptDocument.parse(markdown)

        #expect(document.isScribeKitTranscript)
        #expect(document.spans.map(\.clock) == ["10:01:00", "13:28:04"])
        #expect(document.spans.map(\.timestampDescription) == ["10:01:00 AM", "13:28:04 PM"])
        #expect(document.spans.map(\.text) == ["First sentence.", "Second sentence."])
    }

    @Test("A span that states its own period does not borrow the heading's")
    func spansPreferTheirOwnPeriod() throws {
        let markdown = TranscriptFixture.transcript(texts: ["First sentence."])

        let document = TranscriptDocument.parse(markdown)

        #expect(document.spans.count == 1)
        #expect(document.spans[0].clock == "10:01:00 AM")
        #expect(document.spans[0].timestampDescription == "10:01:00 AM")
    }

    @Test("A bold line that is not a timestamp still opens no span")
    func boldProseIsNotATimestamp() throws {
        let markdown = TranscriptFixture.transcript(texts: ["First sentence."])
            + "**Ended at 1:28:04 PM**\n\nNot a span.\n\n"

        let document = TranscriptDocument.parse(markdown)

        #expect(document.spans.map(\.text) == ["First sentence."])
    }

    @Test("Structural remarks are not recognised speech")
    func structuralTextIsNotSpeech() throws {
        let markdown = TranscriptFixture.transcript(
            texts: ["The only thing anyone said."],
            includesGap: true,
            includesInterruption: true
        )

        let document = TranscriptDocument.parse(markdown)

        #expect(document.spans.count == 1)
        #expect(document.spans[0].text == "The only thing anyone said.")
        let speech = document.spans.map(\.text).joined(separator: "\n")
        #expect(!speech.contains("Captured by"))
        #expect(!speech.contains("Transcription gap"))
        #expect(!speech.contains("Session interrupted"))
        #expect(!speech.contains("Duration"))
        #expect(!speech.contains("Ended"))
    }

    @Test("Recognised text that looks like Markdown stays recognised text",
          arguments: [
            "---",
            "> quoted the memo back at us",
            "### three hash marks, he said",
            "**Ended:** was how he put it",
            "# not a heading"
          ])
    func markdownLikeSpeechIsKept(text: String) throws {
        let markdown = TranscriptFixture.transcript(texts: [text, "And then we moved on."])

        let document = TranscriptDocument.parse(markdown)

        #expect(document.spans.map(\.text) == [text, "And then we moved on."])
    }

    @Test("A transcript with no speech in it is still a transcript")
    func emptyTranscriptIsRecognised() throws {
        let markdown = TranscriptFixture.transcript(texts: [])

        let document = TranscriptDocument.parse(markdown)

        #expect(document.isScribeKitTranscript)
        #expect(document.title == "Closures Walkthrough")
        #expect(document.spans.isEmpty)
    }

    @Test("A transcript still being written, with no footer, parses")
    func openTranscriptParses() throws {
        let markdown = TranscriptFixture.transcript(
            texts: ["Speech that has already reached the file."],
            includesFooter: false
        )

        let document = TranscriptDocument.parse(markdown)

        #expect(document.isScribeKitTranscript)
        #expect(document.spans.map(\.text) == ["Speech that has already reached the file."])
    }

    @Test("Markdown ScribeKit did not write is not a transcript",
          arguments: [
            "# Shopping List\n\n- Milk\n- Bread\n",
            "Just some notes with no heading at all.\n",
            "",
            "# Meeting Notes\n\n**Date:** 2026-08-29\n**Captured by:** Some Other App\n\n## Transcript\n\n",
            "# Meeting Notes\n\n**Captured by:** ScribeKit\n\nNo transcript heading here.\n"
          ])
    func foreignMarkdownIsRejected(text: String) throws {
        let document = TranscriptDocument.parse(text)

        #expect(!document.isScribeKitTranscript)
        #expect(document.spans.isEmpty)
        #expect(document.title == nil)
    }

    @Test("A header with no Sources field yields no source names")
    func headerWithoutSources() throws {
        let markdown = TranscriptFixture.transcript(sourceNames: [], texts: ["Anything."])

        let document = TranscriptDocument.parse(markdown)

        #expect(document.isScribeKitTranscript)
        #expect(document.sourceNames.isEmpty)
    }

    @Test("Several applications in the header split back into separate names")
    func headerWithSeveralSources() throws {
        let markdown = TranscriptFixture.transcript(
            sourceNames: ["Microsoft Teams", "QuickTime Player"],
            texts: ["Anything."]
        )

        let document = TranscriptDocument.parse(markdown)

        #expect(document.sourceNames == ["Microsoft Teams", "QuickTime Player"])
    }
}
