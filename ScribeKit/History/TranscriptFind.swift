//
//  TranscriptFind.swift
//  ScribeKit
//

import Foundation

/// One occurrence of a find query in an open transcript.
///
/// A position, never a copy: the span it names and the character range within
/// that span's recognised text, so highlighting it changes how the words are
/// drawn and nothing about the words.
nonisolated struct TranscriptFindMatch: Hashable, Sendable {
    /// The span's position in the transcript.
    let spanIndex: Int

    /// Where the match begins, in characters from the start of the span's text.
    let offset: Int

    /// How long the match is, in characters.
    let length: Int
}

/// Finding a phrase within one transcript: every occurrence, and which one is
/// current.
///
/// A value over the finalised spans History already has in memory. It reads
/// no file and writes nothing, and it is not a second representation of the
/// transcript: `transcript.md` remains the only authority on what was said,
/// and a match is a position in it.
///
/// Stepping wraps. Next from the last match is the first, and Previous from
/// the first is the last, as Find does in any Mac application.
nonisolated struct TranscriptFind: Equatable, Sendable {

    /// The query as it is matched.
    let query: String

    /// Every occurrence, in transcript order.
    let matches: [TranscriptFindMatch]

    /// Which match is current, or `nil` when there are none.
    private(set) var currentIndex: Int?

    /// No query, and so nothing found.
    static let inactive = TranscriptFind(query: "", matches: [])

    /// Creates a find over precomputed matches, with the first one current.
    ///
    /// - Parameters:
    ///   - query: The query as it is matched.
    ///   - matches: Every occurrence, in transcript order.
    init(query: String, matches: [TranscriptFindMatch]) {
        self.query = query
        self.matches = matches
        currentIndex = matches.isEmpty ? nil : 0
    }

    /// Finds a query in a set of spans.
    ///
    /// - Parameters:
    ///   - query: What the user typed.
    ///   - spans: The transcript's spans.
    init(query: String, in spans: [TranscriptSpan]) {
        self.init(
            query: TranscriptSearch.normalized(query),
            matches: TranscriptSearch.occurrences(of: query, in: spans)
        )
    }

    /// Whether a query has been entered.
    var isActive: Bool { !query.isEmpty }

    /// The current match.
    var current: TranscriptFindMatch? {
        currentIndex.map { matches[$0] }
    }

    /// Makes the next match current, wrapping from the last to the first.
    mutating func next() {
        guard let currentIndex else { return }
        self.currentIndex = (currentIndex + 1) % matches.count
    }

    /// Makes the previous match current, wrapping from the first to the last.
    mutating func previous() {
        guard let currentIndex else { return }
        self.currentIndex = (currentIndex + matches.count - 1) % matches.count
    }

    /// The matches within one span, for highlighting it.
    ///
    /// - Parameter spanIndex: The span's position.
    /// - Returns: Its matches, in order.
    func matches(inSpan spanIndex: Int) -> [TranscriptFindMatch] {
        matches.filter { $0.spanIndex == spanIndex }
    }

    /// Where the find stands, in words, such as `3 of 12`, `No matches` or
    /// `1 match`.
    var positionDescription: String {
        guard isActive else { return "" }
        guard let currentIndex else { return "No matches" }
        return matches.count == 1 ? "1 match" : "\(currentIndex + 1) of \(matches.count)"
    }

    /// The same, as assistive technology reads it.
    var accessibilityPosition: String {
        guard isActive else { return "No search" }
        guard let currentIndex else { return "No matches for \(query)" }
        return matches.count == 1 ? "1 match for \(query)" : "Match \(currentIndex + 1) of \(matches.count) for \(query)"
    }
}

/// Which spans a transcript preview shows.
///
/// The preview is bounded, because a multi-hour meeting has thousands of spans
/// and laying them all out would cost the History screen what it costs to
/// open. With nothing to show, it is the first page; with a span to show — the
/// current find match, or a passage the user asked to see — it is the page
/// around that span, so any part of the transcript can be reached without the
/// whole of it being laid out.
nonisolated enum TranscriptPreviewWindow {

    /// The spans to show.
    ///
    /// - Parameters:
    ///   - count: How many spans the transcript has.
    ///   - anchor: A span that must be shown, when there is one.
    ///   - limit: How many spans to show at most.
    ///   - leading: How many spans to show before the anchor, when there are
    ///     that many.
    /// - Returns: A contiguous range of span positions containing `anchor`.
    static func range(count: Int, anchor: Int?, limit: Int, leading: Int = 10) -> Range<Int> {
        guard count > 0, limit > 0 else { return 0..<0 }
        guard count > limit, let anchor, anchor >= 0, anchor < count else { return 0..<min(count, limit) }
        let start = min(max(0, anchor - leading), count - limit)
        return start..<(start + limit)
    }
}
