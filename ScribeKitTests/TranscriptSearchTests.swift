//
//  TranscriptSearchTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@Suite("TranscriptSearch")
struct TranscriptSearchTests {

    private let destination = URL(filePath: "/Users/example/Meetings", directoryHint: .isDirectory)

    /// 29 August 2026, 14:01:00 UTC.
    private let startedAt = TranscriptFixture.startedAt

    /// A searchable document built from a real ScribeKit transcript.
    ///
    /// The spans come from parsing what ``TranscriptMarkdownFormatter`` would
    /// have written, so search is exercised against the document ScribeKit
    /// actually produces rather than against hand-built spans.
    ///
    /// - Parameters:
    ///   - title: The meeting's title.
    ///   - texts: The recognised spans.
    ///   - sourceNames: The applications captured.
    ///   - started: When the meeting began.
    ///   - includesGap: Whether a transcription-gap blockquote is written.
    ///   - includesInterruption: Whether an interruption notice is appended.
    /// - Returns: The document.
    private func document(
        title: String,
        texts: [String],
        sourceNames: [String] = ["QuickTime Player"],
        started: Date? = nil,
        includesGap: Bool = false,
        includesInterruption: Bool = false
    ) -> TranscriptSearchDocument {
        let directory = destination.appending(
            path: SessionDirectoryName.slug(for: title),
            directoryHint: .isDirectory
        )
        let markdown = TranscriptFixture.transcript(
            title: title,
            sourceNames: sourceNames,
            texts: texts,
            includesGap: includesGap,
            includesInterruption: includesInterruption
        )
        let parsed = TranscriptDocument.parse(markdown)
        let session = HistorySession(
            directory: directory,
            sessionID: UUID(),
            title: title,
            status: .completed,
            startedAt: started ?? startedAt,
            endedAt: (started ?? startedAt).addingTimeInterval(120),
            sourceNames: sourceNames,
            localeIdentifier: "en-US",
            transcriptURL: SessionArtifactLayout(directory: directory).transcriptURL,
            transcript: SessionFileInfo(byteCount: markdown.utf8.count, modifiedAt: started ?? startedAt),
            audioRetention: AudioRetentionMode.none,
            audio: nil
        )
        return TranscriptSearchDocument(session: session, spans: parsed.spans)
    }

    // MARK: - Empty query

    @Test("An empty query shows every meeting, in the order the load produced")
    func emptyQueryShowsEverything() throws {
        let documents = [
            document(title: "Third", texts: ["c"]),
            document(title: "Second", texts: ["b"]),
            document(title: "First", texts: ["a"])
        ]

        let results = TranscriptSearch.results(for: "", in: documents)

        #expect(results.map(\.session.title) == ["Third", "Second", "First"])
        #expect(results.allSatisfy { $0.kind == .unfiltered })
        #expect(results.allSatisfy { $0.excerpt == nil })
    }

    @Test("A query of nothing but spaces is the absence of a query")
    func whitespaceQueryShowsEverything() throws {
        let documents = [document(title: "Only One", texts: ["something"])]

        #expect(TranscriptSearch.results(for: "   \n ", in: documents).count == 1)
    }

    // MARK: - Titles

    @Test("Titles match without regard to case", arguments: ["closures", "CLOSURES", "ClOsUrEs"])
    func titleMatchesAreCaseInsensitive(query: String) throws {
        let documents = [
            document(title: "Closures Walkthrough", texts: ["Nothing relevant here."]),
            document(title: "Standup", texts: ["Nothing relevant here either."])
        ]

        let results = TranscriptSearch.results(for: query, in: documents)

        #expect(results.map(\.session.title) == ["Closures Walkthrough"])
        #expect(results.first?.kind == .titlePrefix)
    }

    @Test("An exact title beats a prefix, which beats a substring")
    func titleMatchStrengthOrdersResults() throws {
        let documents = [
            document(title: "Weekly Standup Notes", texts: ["nothing"]),
            document(title: "Standup", texts: ["nothing"]),
            document(title: "Standup and Retro", texts: ["nothing"])
        ]

        let results = TranscriptSearch.results(for: "Standup", in: documents)

        #expect(results.map(\.session.title) == ["Standup", "Standup and Retro", "Weekly Standup Notes"])
        #expect(results.map(\.kind) == [.titleExact, .titlePrefix, .titleSubstring])
    }

    @Test("A title match outranks a transcript match")
    func titleOutranksTranscript() throws {
        let documents = [
            document(title: "Unrelated", texts: ["We talked about closures for an hour."]),
            document(title: "Closures", texts: ["We talked about something else entirely."])
        ]

        let results = TranscriptSearch.results(for: "closures", in: documents)

        #expect(results.map(\.session.title) == ["Closures", "Unrelated"])
    }

    // MARK: - Transcript content

    @Test("Recognised speech is searchable")
    func transcriptContentIsSearchable() throws {
        let documents = [
            document(title: "Alpha", texts: ["A closure captures the variables it refers to."]),
            document(title: "Beta", texts: ["Nothing about that subject at all."])
        ]

        let results = TranscriptSearch.results(for: "captures the variables", in: documents)

        #expect(results.map(\.session.title) == ["Alpha"])
        #expect(results.first?.kind == .transcript)
        #expect(results.first?.transcriptMatchCount == 1)
    }

    @Test("Transcript matches are case-insensitive")
    func transcriptMatchesAreCaseInsensitive() throws {
        let documents = [document(title: "Alpha", texts: ["Escaping closures outlive the call."])]

        #expect(TranscriptSearch.results(for: "ESCAPING", in: documents).count == 1)
        #expect(TranscriptSearch.results(for: "escaping", in: documents).count == 1)
    }

    @Test("Every occurrence is counted, across spans")
    func occurrencesAreCounted() throws {
        let documents = [document(title: "Alpha", texts: [
            "A closure, and another closure.",
            "One more closure to finish."
        ])]

        let results = TranscriptSearch.results(for: "closure", in: documents)

        #expect(results.first?.transcriptMatchCount == 3)
    }

    @Test("A source application name is searchable")
    func sourceNamesAreSearchable() throws {
        let documents = [
            document(title: "Alpha", texts: ["nothing relevant"], sourceNames: ["Microsoft Teams"]),
            document(title: "Beta", texts: ["nothing relevant"], sourceNames: ["QuickTime Player"])
        ]

        let results = TranscriptSearch.results(for: "microsoft", in: documents)

        #expect(results.map(\.session.title) == ["Alpha"])
        #expect(results.first?.kind == .source)
    }

    @Test("Nothing matches a query that is in no meeting")
    func absentQueryMatchesNothing() throws {
        let documents = [document(title: "Alpha", texts: ["Something quite specific."])]

        #expect(TranscriptSearch.results(for: "helicopter", in: documents).isEmpty)
    }

    // MARK: - Structural text

    @Test("ScribeKit's own structural text is not searchable speech",
          arguments: [
            "Captured by",
            "Transcription gap",
            "Session interrupted",
            "Duration",
            "Ended",
            "Transcript"
          ])
    func structuralTextProducesNoTranscriptMatch(query: String) throws {
        let documents = [document(
            title: "Alpha",
            texts: ["The only sentence anyone said."],
            includesGap: true,
            includesInterruption: true
        )]

        let results = TranscriptSearch.results(for: query, in: documents)

        #expect(results.isEmpty)
    }

    @Test("Metadata search still works when the phrase is also a header word")
    func metadataStillMatchesDeliberately() throws {
        let documents = [document(
            title: "Language Review",
            texts: ["Nothing about that."],
            sourceNames: ["Language Lab"]
        )]

        let results = TranscriptSearch.results(for: "Language", in: documents)

        #expect(results.map(\.session.title) == ["Language Review"])
        #expect(results.first?.kind == .titlePrefix)
        #expect(results.first?.transcriptMatchCount == 0)
    }

    // MARK: - Excerpts and timestamps

    @Test("An excerpt carries the timestamp of the span the match came from")
    func excerptKeepsItsTimestamp() throws {
        let documents = [document(title: "Alpha", texts: [
            "First sentence.",
            "The phrase we are looking for.",
            "Third sentence."
        ])]

        let excerpt = try #require(TranscriptSearch.results(for: "looking for", in: documents).first?.excerpt)

        #expect(excerpt.spanIndex == 1)
        #expect(excerpt.clock == "10:01:20")
        #expect(excerpt.heading == "10:01 AM")
        #expect(excerpt.timestampDescription == "10:01:20 AM")
    }

    @Test("An excerpt is the original wording, with the match located in it")
    func excerptIsVerbatim() throws {
        let text = "A closure captures the variables it refers to, and keeps them alive."
        let documents = [document(title: "Alpha", texts: [text])]

        let excerpt = try #require(TranscriptSearch.results(for: "variables", in: documents).first?.excerpt)

        #expect(excerpt.text == text)
        #expect(!excerpt.isTruncatedAtStart)
        #expect(!excerpt.isTruncatedAtEnd)
        let start = excerpt.text.index(excerpt.text.startIndex, offsetBy: excerpt.matchOffset)
        let end = excerpt.text.index(start, offsetBy: excerpt.matchLength)
        #expect(String(excerpt.text[start..<end]) == "variables")
    }

    @Test("A long span is cut to a bounded excerpt around the match")
    func excerptIsBounded() throws {
        let filler = String(repeating: "padding words ", count: 60)
        let text = filler + "the needle we want " + filler
        let documents = [document(title: "Alpha", texts: [text])]

        let excerpt = try #require(TranscriptSearch.results(for: "needle", in: documents).first?.excerpt)

        #expect(excerpt.text.count <= TranscriptSearch.excerptLength)
        #expect(excerpt.isTruncatedAtStart)
        #expect(excerpt.isTruncatedAtEnd)
        #expect(text.contains(excerpt.text))
        let start = excerpt.text.index(excerpt.text.startIndex, offsetBy: excerpt.matchOffset)
        let end = excerpt.text.index(start, offsetBy: excerpt.matchLength)
        #expect(String(excerpt.text[start..<end]) == "needle")
    }

    @Test("A match at the very end of a long span is still shown whole")
    func excerptAtTheEndOfASpan() throws {
        let text = String(repeating: "padding words ", count: 60) + "trailing needle"
        let documents = [document(title: "Alpha", texts: [text])]

        let excerpt = try #require(TranscriptSearch.results(for: "needle", in: documents).first?.excerpt)

        #expect(excerpt.text.count <= TranscriptSearch.excerptLength)
        #expect(excerpt.isTruncatedAtStart)
        #expect(!excerpt.isTruncatedAtEnd)
        let start = excerpt.text.index(excerpt.text.startIndex, offsetBy: excerpt.matchOffset)
        let end = excerpt.text.index(start, offsetBy: excerpt.matchLength)
        #expect(String(excerpt.text[start..<end]) == "needle")
    }

    @Test("A title-only match carries no excerpt, because there is nothing to quote")
    func titleOnlyMatchHasNoExcerpt() throws {
        let documents = [document(title: "Closures", texts: ["Something else entirely."])]

        let result = try #require(TranscriptSearch.results(for: "closures", in: documents).first)

        #expect(result.excerpt == nil)
        #expect(result.transcriptMatchCount == 0)
    }

    @Test("The first occurrence is the one excerpted")
    func firstOccurrenceIsExcerpted() throws {
        let documents = [document(title: "Alpha", texts: [
            "The needle appears here first.",
            "And the needle appears here again."
        ])]

        let result = try #require(TranscriptSearch.results(for: "needle", in: documents).first)

        #expect(result.transcriptMatchCount == 2)
        #expect(result.excerpt?.spanIndex == 0)
    }

    // MARK: - Ordering

    @Test("Within one kind, more matches rank higher, then the earlier match")
    func transcriptMatchesAreRankedDeterministically() throws {
        let documents = [
            document(title: "One Match Late", texts: ["padding", "padding", "the needle"]),
            document(title: "Three Matches", texts: ["needle needle", "and one more needle"]),
            document(title: "One Match Early", texts: ["the needle", "padding", "padding"])
        ]

        let results = TranscriptSearch.results(for: "needle", in: documents)

        #expect(results.map(\.session.title) == ["Three Matches", "One Match Early", "One Match Late"])
        #expect(results.map(\.transcriptMatchCount) == [3, 1, 1])
    }

    @Test("Sessions that are otherwise equal are ordered newest first")
    func newerSessionWinsATie() throws {
        let older = document(title: "Older", texts: ["the needle"], started: startedAt)
        let newer = document(
            title: "Newer",
            texts: ["the needle"],
            started: startedAt.addingTimeInterval(3_600)
        )

        let results = TranscriptSearch.results(for: "needle", in: [older, newer])

        #expect(results.map(\.session.title) == ["Newer", "Older"])
    }

    @Test("The same query over the same documents always produces the same list")
    func searchIsRepeatable() throws {
        let documents = [
            document(title: "Alpha", texts: ["the needle appears"]),
            document(title: "Beta", texts: ["the needle appears twice: needle"]),
            document(title: "Needle", texts: ["nothing else"])
        ]

        let first = TranscriptSearch.results(for: "needle", in: documents)
        let second = TranscriptSearch.results(for: "needle", in: documents)

        #expect(first == second)
        #expect(first.map(\.session.title) == ["Needle", "Beta", "Alpha"])
    }

    // MARK: - Text outside ASCII

    @Test("Speech with accented characters matches without regard to case")
    func nonASCIISpeechMatches() throws {
        let documents = [document(title: "Alpha", texts: ["Nous avons parlé du café au lait."])]

        let results = TranscriptSearch.results(for: "CAFÉ", in: documents)

        #expect(results.count == 1)
        let excerpt = try #require(results.first?.excerpt)
        let start = excerpt.text.index(excerpt.text.startIndex, offsetBy: excerpt.matchOffset)
        let end = excerpt.text.index(start, offsetBy: excerpt.matchLength)
        #expect(String(excerpt.text[start..<end]) == "café")
    }

    @Test("An ASCII query still locates itself correctly in speech that is not ASCII")
    func asciiQueryInNonASCIISpeech() throws {
        let documents = [document(title: "Alpha", texts: ["Nous avons parlé du café au lait."])]

        let excerpt = try #require(TranscriptSearch.results(for: "lait", in: documents).first?.excerpt)

        let start = excerpt.text.index(excerpt.text.startIndex, offsetBy: excerpt.matchOffset)
        let end = excerpt.text.index(start, offsetBy: excerpt.matchLength)
        #expect(String(excerpt.text[start..<end]) == "lait")
        #expect(excerpt.text == "Nous avons parlé du café au lait.")
    }

    @Test("A query outside ASCII matches nothing in speech that has no such character")
    func nonASCIIQueryAgainstASCIISpeech() throws {
        let documents = [document(title: "Alpha", texts: ["Plain ASCII speech only."])]

        #expect(TranscriptSearch.results(for: "é", in: documents).isEmpty)
    }

    @Test("Preparing an index once gives the same answers as searching directly")
    func indexMatchesTheOneShotSearch() throws {
        let documents = [
            document(title: "Alpha", texts: ["the needle appears", "parlé du café"]),
            document(title: "Beta", texts: ["needle needle"])
        ]
        let index = TranscriptSearchIndex(documents)

        for query in ["needle", "NEEDLE", "café", "", "nothing here"] {
            #expect(TranscriptSearch.results(for: query, in: index)
                    == TranscriptSearch.results(for: query, in: documents))
        }
    }

    @Test("An empty index has nothing to return")
    func emptyIndex() throws {
        #expect(TranscriptSearchIndex.empty.isEmpty)
        #expect(TranscriptSearch.results(for: "anything", in: TranscriptSearchIndex.empty).isEmpty)
        #expect(TranscriptSearch.results(for: "", in: TranscriptSearchIndex.empty).isEmpty)
    }

    @Test("Recognised text that looks like Markdown is searchable as text")
    func markdownLikeSpeechIsSearchable() throws {
        let documents = [document(title: "Alpha", texts: ["> quoted the memo back at us"])]

        let results = TranscriptSearch.results(for: "quoted the memo", in: documents)

        #expect(results.count == 1)
        #expect(results.first?.excerpt?.text.contains("> quoted the memo back at us") == true)
    }
}
