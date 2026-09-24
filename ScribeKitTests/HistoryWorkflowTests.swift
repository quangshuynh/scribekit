//
//  HistoryWorkflowTests.swift
//  ScribeKitTests
//

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ScribeKit

private let destination = URL(filePath: "/Users/example/Meetings", directoryHint: .isDirectory)

/// A searchable document parsed from what the formatter really writes.
///
/// - Parameters:
///   - title: The meeting's title.
///   - texts: The recognised spans.
///   - mode: The capture mode the record states, or `nil` for a record that
///     predates capture modes.
///   - sourceNames: What the header and record name as sources.
///   - hasRecord: Whether a session record exists at all.
///   - hoursLater: How long after the fixture's start the meeting began.
/// - Returns: The document.
private func document(
    _ title: String,
    texts: [String],
    mode: CaptureMode? = .applications,
    sourceNames: [String]? = nil,
    hasRecord: Bool = true,
    hoursLater: Double = 0
) -> TranscriptSearchDocument {
    let names = sourceNames ?? (mode == .microphone ? ["Microphone (Studio Mic)"] : ["Zoom"])
    let directory = destination.appending(path: SessionDirectoryName.slug(for: title), directoryHint: .isDirectory)
    let markdown = TranscriptFixture.transcript(title: title, sourceNames: names, texts: texts)
    let started = TranscriptFixture.startedAt.addingTimeInterval(hoursLater * 3_600)
    let session = HistorySession(
        directory: directory,
        sessionID: hasRecord ? UUID() : nil,
        title: title,
        status: hasRecord ? .completed : .unrecorded,
        startedAt: hasRecord ? started : nil,
        endedAt: hasRecord ? started.addingTimeInterval(120) : nil,
        sourceNames: names,
        localeIdentifier: "en-US",
        transcriptURL: SessionArtifactLayout(directory: directory).transcriptURL,
        transcript: SessionFileInfo(byteCount: markdown.utf8.count, modifiedAt: started),
        audioRetention: hasRecord ? AudioRetentionMode.none : nil,
        audio: nil,
        captureMode: hasRecord ? mode : nil
    )
    return TranscriptSearchDocument(session: session, spans: TranscriptDocument.parse(markdown).spans)
}

/// The collection most tests search: both modes, a v0.1.0 record with no
/// mode, and a transcript with no record at all.
private let collection = [
    document("Release Planning", texts: ["The deployment moves to Thursday."], mode: .applications, hoursLater: 5),
    document("Thinking Aloud", texts: ["Maybe the deployment should wait.", "Deployment again."],
             mode: .microphone, hoursLater: 4),
    document("Voice Memo", texts: ["Groceries, then the dentist."], mode: .microphone, hoursLater: 3),
    document("Old Standup", texts: ["Deployment is blocked on review."], mode: nil, hoursLater: 2),
    document("Legacy Notes", texts: ["A deployment from before records existed."], hasRecord: false, hoursLater: 1)
]

// MARK: - Filtering

@Suite("History capture filter")
struct HistoryCaptureFilterTests {

    @Test("All lists everything; each mode lists only its own meetings, in load order")
    func filtersByMode() {
        let all = TranscriptSearch.results(for: "", in: collection, filter: .all)
        #expect(all.map(\.session.title) == collection.map(\.session.title))

        let microphone = TranscriptSearch.results(for: "", in: collection, filter: .microphone)
        #expect(microphone.map(\.session.title) == ["Thinking Aloud", "Voice Memo"])

        let applications = TranscriptSearch.results(for: "", in: collection, filter: .applications)
        #expect(applications.map(\.session.title) == ["Release Planning", "Old Standup"])
    }

    @Test("A v0.1.0 record with no capture mode is App Audio, the only thing that build could capture")
    func legacyRecordIsAppAudio() {
        let old = collection[3]
        #expect(old.session.captureMode == nil)
        #expect(old.session.knownCaptureMode == .applications)
    }

    @Test("A transcript with no record has no known mode and is listed under All only")
    func unrecordedIsUnknown() {
        let legacy = collection[4]
        #expect(legacy.session.knownCaptureMode == nil)
        #expect(HistoryCaptureFilter.all.includes(legacy.session))
        #expect(!HistoryCaptureFilter.applications.includes(legacy.session))
        #expect(!HistoryCaptureFilter.microphone.includes(legacy.session))
    }

    @Test("A query and a filter compose: \"deployment\" + Microphone is only Microphone meetings saying it")
    func queryAndFilterCompose() {
        let results = TranscriptSearch.results(for: "deployment", in: collection, filter: .microphone)
        #expect(results.map(\.session.title) == ["Thinking Aloud"])
        #expect(results.first?.transcriptMatchCount == 2)

        let everywhere = TranscriptSearch.results(for: "deployment", in: collection)
        #expect(Set(everywhere.map(\.session.title))
            == ["Release Planning", "Thinking Aloud", "Old Standup", "Legacy Notes"])
        let apps = TranscriptSearch.results(for: "deployment", in: collection, filter: .applications)
        #expect(apps.map(\.session.title).sorted() == ["Old Standup", "Release Planning"])
    }

    @Test("A filtered search is as deterministic as an unfiltered one")
    func filteredOrderingIsStable() {
        let first = TranscriptSearch.results(for: "deployment", in: collection, filter: .applications)
        for _ in 0..<5 {
            #expect(TranscriptSearch.results(for: "deployment", in: collection.reversed(), filter: .applications)
                .map(\.session.id) == first.map(\.session.id))
        }
    }

    @Test("A filter that admits nothing returns nothing, with or without a query")
    func emptyFilter() {
        let appsOnly = [collection[0]]
        #expect(TranscriptSearch.results(for: "", in: appsOnly, filter: .microphone).isEmpty)
        #expect(TranscriptSearch.results(for: "deployment", in: appsOnly, filter: .microphone).isEmpty)
    }
}

// MARK: - Matching

@Suite("History search matching")
struct HistorySearchMatchingTests {

    @Test("A capture mode's name is searchable, below every other kind of match")
    func captureModeIsSearchable() {
        let results = TranscriptSearch.results(for: "app audio", in: collection)
        #expect(results.map(\.session.title) == ["Release Planning", "Old Standup"])
        #expect(results.allSatisfy { $0.kind == .captureMode })
        #expect(results.allSatisfy { $0.excerpt == nil }, "there are no words to quote for a mode match")

        let legacyOnly = TranscriptSearch.results(for: "app audio", in: [collection[4]])
        #expect(legacyOnly.isEmpty, "an unknown mode is not matched by either name")
    }

    @Test("A title fragment finds the meeting with any case")
    func titleMatches() {
        #expect(TranscriptSearch.results(for: "VOICE", in: collection).map(\.session.title) == ["Voice Memo"])
        #expect(TranscriptSearch.results(for: "voice memo", in: collection).first?.kind == .titleExact)
    }

    @Test("Whitespace around and inside a query is not significant", arguments: [
        "moves to", "  moves to ", "moves   to", "moves\tto", "moves\nto"
    ])
    func whitespaceIsNormalised(query: String) {
        let results = TranscriptSearch.results(for: query, in: collection)
        #expect(results.map(\.session.title) == ["Release Planning"])
        #expect(results.first?.excerpt?.text == "The deployment moves to Thursday.")
    }

    @Test("A phrase wrapped onto a second line in the file still matches one typed on one line")
    func wrappedSpanMatches() {
        let span = TranscriptSpan(index: 0, clock: "10:01:00 AM", heading: "10:01 AM", text: "rolling\nback today")
        let matches = TranscriptSearch.occurrences(of: "rolling back", in: [span])
        #expect(matches == [TranscriptFindMatch(spanIndex: 0, offset: 0, length: 12)])
    }

    @Test("Punctuation around a word does not hide it, and punctuation typed is matched as typed")
    func punctuation() {
        let span = TranscriptSpan(index: 0, clock: "10:01:00 AM", heading: nil, text: "Ship it, then deployment. Done?")
        #expect(TranscriptSearch.occurrences(of: "deployment", in: [span]).count == 1)
        #expect(TranscriptSearch.occurrences(of: "deployment.", in: [span]).count == 1)
        #expect(TranscriptSearch.occurrences(of: "deployment?", in: [span]).isEmpty)
        #expect(TranscriptSearch.occurrences(of: "it,", in: [span]).count == 1)
    }

    @Test("A query of only whitespace is no query")
    func whitespaceOnlyIsEmpty() {
        #expect(TranscriptSearch.normalized(" \t\n ").isEmpty)
        #expect(TranscriptSearch.results(for: " \n", in: collection, filter: .microphone).count == 2)
    }

    @Test("No match is an empty list, not an error")
    func noMatch() {
        #expect(TranscriptSearch.results(for: "xylophone", in: collection).isEmpty)
    }

    @Test("A result's snippet is the recognised wording, located at the match")
    func snippetIsVerbatim() throws {
        let result = try #require(TranscriptSearch.results(for: "dentist", in: collection).first)
        let excerpt = try #require(result.excerpt)
        #expect(excerpt.text == "Groceries, then the dentist.")
        let start = excerpt.text.index(excerpt.text.startIndex, offsetBy: excerpt.matchOffset)
        let end = excerpt.text.index(start, offsetBy: excerpt.matchLength)
        #expect(excerpt.text[start..<end] == "dentist")
    }
}

// MARK: - Row presentation

@Suite("History row presentation")
@MainActor
struct HistoryRowPresentationTests {

    @Test("A row names the capture mode beside the date when it is known, and nothing when it is not")
    func dateAndSource() {
        let microphone = HistoryView.dateAndSourceDescription(for: collection[1].session)
        #expect(microphone.hasSuffix(" · Microphone"))
        let v010 = HistoryView.dateAndSourceDescription(for: collection[3].session)
        #expect(v010.hasSuffix(" · App Audio"))
        let legacy = HistoryView.dateAndSourceDescription(for: collection[4].session)
        #expect(!legacy.contains("·"))
    }

    @Test("A result reads as its title, status, date, mode, match time, verbatim snippet and count")
    func accessibilityDescriptionIsComplete() throws {
        let result = try #require(TranscriptSearch.results(for: "deployment", in: collection, filter: .microphone).first)
        let text = result.accessibilityDescription(date: "Aug 29, 2026 at 2:00 PM")
        #expect(text.hasPrefix("Thinking Aloud. Completed. Aug 29, 2026 at 2:00 PM. Microphone."))
        #expect(text.contains("Match at \(try #require(result.excerpt).timestampDescription):"))
        #expect(text.contains("Maybe the deployment should wait."))
        #expect(text.hasSuffix("2 matches in the transcript."))
        #expect(!text.contains("…"), "the ellipses the row draws are not read out")
    }

    @Test("A result with no quoted speech and no known mode says only what is known")
    func accessibilityDescriptionIsHonest() throws {
        let result = try #require(TranscriptSearch.results(for: "legacy", in: collection).first)
        let text = result.accessibilityDescription(date: "Transcript last written Aug 29")
        #expect(text == "Legacy Notes. Legacy. Transcript last written Aug 29.")
    }

    @Test("The footer counts what is listed only while something narrows the list")
    func countDescription() {
        #expect(HistoryView.countDescription(listed: 5, total: 5, isNarrowed: false) == "5 meetings")
        #expect(HistoryView.countDescription(listed: 1, total: 1, isNarrowed: false) == "1 meeting")
        #expect(HistoryView.countDescription(listed: 2, total: 5, isNarrowed: true) == "2 of 5")
    }

    @Test("An empty list names whatever is narrowing it")
    func emptyListDescription() {
        #expect(HistoryView.emptyListDescription(query: "", filter: .all, sessionCount: 0)
            == "No meetings in the save folder yet.")
        #expect(HistoryView.emptyListDescription(query: "", filter: .microphone, sessionCount: 3)
            == "No Microphone meetings in the save folder.")
        #expect(HistoryView.emptyListDescription(query: "deploy", filter: .all, sessionCount: 3)
            == "No meeting matches “deploy”.")
        #expect(HistoryView.emptyListDescription(query: "deploy", filter: .applications, sessionCount: 3)
            == "No App Audio meeting matches “deploy”.")
    }
}

// MARK: - Transcript find

@Suite("Transcript find")
struct TranscriptFindTests {

    private let spans = [
        TranscriptSpan(index: 0, clock: "10:01:00 AM", heading: "10:01 AM", text: "Closures capture values."),
        TranscriptSpan(index: 1, clock: "10:01:20 AM", heading: "10:01 AM", text: "No match in this one."),
        TranscriptSpan(index: 2, clock: "10:01:40 AM", heading: "10:01 AM", text: "A closure, and another CLOSURE.")
    ]

    @Test("No query is inactive; a query with no match says so and has nothing to step to")
    func zeroMatches() {
        #expect(!TranscriptFind.inactive.isActive)
        #expect(TranscriptFind.inactive.positionDescription.isEmpty)

        var find = TranscriptFind(query: "lambda", in: spans)
        #expect(find.isActive)
        #expect(find.matches.isEmpty)
        #expect(find.current == nil)
        find.next()
        find.previous()
        #expect(find.current == nil)
        #expect(find.positionDescription == "No matches")
        #expect(find.accessibilityPosition == "No matches for lambda")
    }

    @Test("One match is current, and stepping either way stays on it")
    func oneMatch() {
        var find = TranscriptFind(query: "values", in: spans)
        let only = TranscriptFindMatch(spanIndex: 0, offset: 17, length: 6)
        #expect(find.matches == [only])
        find.next()
        #expect(find.current == only)
        find.previous()
        #expect(find.current == only)
        #expect(find.positionDescription == "1 match")
        #expect(find.accessibilityPosition == "1 match for values")
    }

    @Test("Several matches, across spans and within one, in transcript order and any case")
    func multipleMatches() {
        let find = TranscriptFind(query: "closure", in: spans)
        #expect(find.matches == [
            TranscriptFindMatch(spanIndex: 0, offset: 0, length: 7),
            TranscriptFindMatch(spanIndex: 2, offset: 2, length: 7),
            TranscriptFindMatch(spanIndex: 2, offset: 23, length: 7)
        ])
        #expect(find.current == find.matches.first)
        #expect(find.matches(inSpan: 2).count == 2)
        #expect(find.matches(inSpan: 1).isEmpty)
        #expect(find.positionDescription == "1 of 3")
    }

    @Test("Next wraps from the last match to the first; Previous wraps from the first to the last")
    func wrapping() {
        var find = TranscriptFind(query: "closure", in: spans)
        find.previous()
        #expect(find.currentIndex == 2)
        #expect(find.accessibilityPosition == "Match 3 of 3 for closure")
        find.next()
        #expect(find.currentIndex == 0)
        find.next()
        find.next()
        find.next()
        #expect(find.currentIndex == 0)
    }

    @Test("The query is normalised the way History's search normalises it")
    func normalisedQuery() {
        let find = TranscriptFind(query: "  capture   values ", in: spans)
        #expect(find.query == "capture values")
        #expect(find.matches.count == 1)
    }

    @Test("Finding reads the spans and changes nothing about them")
    func canonicalTextUnchanged() {
        let before = spans
        var find = TranscriptFind(query: "closure", in: spans)
        find.next()
        find.previous()
        #expect(spans == before)
        let highlighted = HistorySessionDetailView.highlighted(
            spans[2].text,
            matches: find.matches(inSpan: 2),
            current: find.matches[1]
        )
        #expect(String(highlighted.characters) == spans[2].text, "highlighting adds and removes no character")
    }

    @Test("Speech outside ASCII is found by character, not by byte")
    func nonASCII() {
        let span = TranscriptSpan(index: 0, clock: "10:01:00 AM", heading: nil, text: "Café résumé, CAFÉ.")
        let find = TranscriptFind(query: "café", in: [span])
        #expect(find.matches == [
            TranscriptFindMatch(spanIndex: 0, offset: 0, length: 4),
            TranscriptFindMatch(spanIndex: 0, offset: 13, length: 4)
        ])
    }
}

@Suite("Transcript find highlighting")
@MainActor
struct TranscriptFindHighlightTests {

    @Test("The current match is emphasised as well as coloured; the others are only tinted")
    func currentIsDistinct() {
        let text = "one two one"
        let first = TranscriptFindMatch(spanIndex: 0, offset: 0, length: 3)
        let second = TranscriptFindMatch(spanIndex: 0, offset: 8, length: 3)
        let attributed = HistorySessionDetailView.highlighted(text, matches: [first, second], current: second)

        let runs = attributed.runs.map { (String(attributed[$0.range].characters), $0.inlinePresentationIntent) }
        #expect(runs.first { $0.0 == "one" && $0.1 == .stronglyEmphasized } != nil)
        #expect(runs.filter { $0.1 == .stronglyEmphasized }.count == 1)
        #expect(attributed.runs.filter { $0.backgroundColor != nil }.count == 2)
    }

    @Test("A match that does not fit the text is ignored rather than trusted")
    func outOfRangeIsIgnored() {
        let text = "short"
        let bogus = TranscriptFindMatch(spanIndex: 0, offset: 3, length: 10)
        let attributed = HistorySessionDetailView.highlighted(text, matches: [bogus], current: bogus)
        #expect(String(attributed.characters) == text)
        #expect(attributed.runs.allSatisfy { $0.backgroundColor == nil })
    }

    @Test("A preview row says whether it holds matches and the current one, and nothing when it holds none")
    func rowValue() {
        #expect(HistorySessionDetailView.matchAccessibilityValue(matchCount: 0, hasCurrent: false).isEmpty)
        #expect(HistorySessionDetailView.matchAccessibilityValue(matchCount: 1, hasCurrent: false) == "1 match")
        #expect(HistorySessionDetailView.matchAccessibilityValue(matchCount: 1, hasCurrent: true) == "Current match")
        #expect(HistorySessionDetailView.matchAccessibilityValue(matchCount: 3, hasCurrent: true)
            == "Current match, 3 matches")
    }
}

@Suite("Transcript preview window")
struct TranscriptPreviewWindowTests {

    @Test("With nothing to show, the preview is the first page")
    func firstPage() {
        #expect(TranscriptPreviewWindow.range(count: 500, anchor: nil, limit: 50) == 0..<50)
        #expect(TranscriptPreviewWindow.range(count: 20, anchor: nil, limit: 50) == 0..<20)
        #expect(TranscriptPreviewWindow.range(count: 0, anchor: 3, limit: 50) == 0..<0)
    }

    @Test("A span deep in a long transcript is shown with the passages before it")
    func followsAnchor() {
        let window = TranscriptPreviewWindow.range(count: 500, anchor: 300, limit: 50)
        #expect(window == 290..<340)
        #expect(window.contains(300))
    }

    @Test("The window never runs past either end, and always contains its anchor")
    func clamped() {
        #expect(TranscriptPreviewWindow.range(count: 500, anchor: 3, limit: 50) == 0..<50)
        #expect(TranscriptPreviewWindow.range(count: 500, anchor: 499, limit: 50) == 450..<500)
        for anchor in stride(from: 0, to: 500, by: 7) {
            let window = TranscriptPreviewWindow.range(count: 500, anchor: anchor, limit: 50)
            #expect(window.contains(anchor))
            #expect(window.count == 50)
        }
    }

    @Test("An anchor the transcript does not have is ignored")
    func invalidAnchor() {
        #expect(TranscriptPreviewWindow.range(count: 100, anchor: 100, limit: 50) == 0..<50)
        #expect(TranscriptPreviewWindow.range(count: 100, anchor: -1, limit: 50) == 0..<50)
    }
}

// MARK: - The model

/// A remembered save folder, without a bookmark or the sandbox.
private nonisolated final class RememberedFolder: SaveLocationPersisting, @unchecked Sendable {
    func save(_ url: URL) throws {}
    func restore() throws -> URL? { destination }
    func clear() throws {}
}

@MainActor
@Suite("HistoryModel search, filter and find")
struct HistoryModelWorkflowTests {

    private func directory(_ name: String) -> URL {
        destination.appending(path: name, directoryHint: .isDirectory)
    }

    /// A folder with an App Audio meeting, a Microphone meeting, a v0.1.0
    /// record and a transcript with no record.
    private func makeModel() throws -> (HistoryModel, FakeHistoryStore) {
        let store = FakeHistoryStore()
        func add(_ name: String, _ title: String, _ mode: CaptureMode?, hours: Double, _ texts: [String]) throws {
            try store.addSession(
                directory(name),
                in: destination,
                metadata: SessionRecoveryMetadata(
                    sessionID: UUID(),
                    title: title,
                    startedAt: TranscriptFixture.startedAt.addingTimeInterval(hours * 3_600),
                    sourceNames: [mode == .microphone ? "Microphone (Studio Mic)" : "Zoom"],
                    localeIdentifier: "en-US",
                    captureMode: mode,
                    status: .completed,
                    endedAt: TranscriptFixture.startedAt.addingTimeInterval(hours * 3_600 + 120)
                ),
                transcript: TranscriptFixture.transcript(title: title, texts: texts)
            )
        }
        try add("a-release", "Release Planning", .applications, hours: 3, ["The deployment moves to Thursday."])
        try add("b-thinking", "Thinking Aloud", .microphone, hours: 2,
                ["Maybe the deployment should wait.", "Nothing here.", "Deployment again, deployment."])
        try add("c-old", "Old Standup", nil, hours: 1, ["Deployment is blocked on review."])
        try store.addSession(
            directory("d-legacy"),
            in: destination,
            metadata: nil,
            transcript: TranscriptFixture.transcript(title: "Legacy Notes", texts: ["An old deployment."])
        )
        let model = HistoryModel(
            service: HistoryService(store: store, access: FakeSecurityScopedAccess()),
            saveLocation: RememberedFolder()
        )
        return (model, store)
    }

    @Test("A filter narrows the list, a query narrows it further, and clearing the query keeps the filter")
    func filterAndQueryCompose() async throws {
        let (model, store) = try makeModel()
        await model.load()
        let reads = store.readCount
        #expect(model.results.count == 4)

        model.filter = .microphone
        #expect(model.results.map(\.session.title) == ["Thinking Aloud"])

        model.query = "deployment"
        #expect(model.results.map(\.session.title) == ["Thinking Aloud"])
        model.filter = .applications
        #expect(model.results.map(\.session.title) == ["Release Planning", "Old Standup"])

        model.query = ""
        #expect(model.filter == .applications, "clearing the search leaves the filter alone")
        #expect(model.results.map(\.session.title) == ["Release Planning", "Old Standup"])

        model.filter = .all
        #expect(model.results.count == 4)
        #expect(store.readCount == reads, "filtering and searching read no file")
    }

    @Test("A result opens its own meeting's transcript")
    func resultOpensItsOwnTranscript() async throws {
        let (model, _) = try makeModel()
        await model.load()
        model.query = "blocked"
        let result = try #require(model.results.first)
        let opened = try #require(model.document(for: result.id))
        #expect(opened.session == result.session)
        #expect(opened.session.transcriptURL == directory("c-old").appending(path: "transcript.md"))
        #expect(opened.spans.first?.text == "Deployment is blocked on review.")
    }

    @Test("A reload keeps the filter and the query")
    func reloadKeepsNarrowing() async throws {
        let (model, _) = try makeModel()
        await model.load()
        model.filter = .microphone
        model.query = "wait"
        await model.load()
        #expect(model.filter == .microphone)
        #expect(model.results.map(\.session.title) == ["Thinking Aloud"])
    }

    @Test("Find runs over the selected transcript, steps with wrapping, and reads no file")
    func findInSelectedTranscript() async throws {
        let (model, store) = try makeModel()
        await model.load()
        await model.selectSession(directory("b-thinking"))
        let reads = store.readCount

        model.findQuery = "deployment"
        #expect(model.find.matches.map(\.spanIndex) == [0, 2, 2])
        #expect(model.previewAnchor == 0)
        model.findNext()
        #expect(model.find.current?.spanIndex == 2)
        #expect(model.previewAnchor == 2)
        model.findPrevious()
        model.findPrevious()
        #expect(model.find.currentIndex == 2, "previous from the first wraps to the last")
        #expect(store.readCount == reads)
    }

    @Test("Selecting another meeting keeps the find query and finds it there")
    func findFollowsSelection() async throws {
        let (model, _) = try makeModel()
        await model.load()
        await model.selectSession(directory("b-thinking"))
        model.findQuery = "deployment"
        #expect(model.find.matches.count == 3)

        await model.selectSession(directory("a-release"))
        #expect(model.findQuery == "deployment")
        #expect(model.find.matches.count == 1)

        await model.selectSession(nil)
        #expect(model.find == .inactive)
    }

    @Test("Showing a flagged passage moves the preview there until the next find step")
    func revealAndFind() async throws {
        let (model, _) = try makeModel()
        await model.load()
        await model.selectSession(directory("b-thinking"))
        model.findQuery = "deployment"
        model.reveal(spanIndex: 1)
        #expect(model.previewAnchor == 1)
        model.findNext()
        #expect(model.revealedSpanIndex == nil)
        #expect(model.previewAnchor == 2)

        model.reveal(spanIndex: 1)
        await model.selectSession(directory("a-release"))
        #expect(model.revealedSpanIndex == nil, "a passage belongs to the meeting it was revealed in")
    }
}
