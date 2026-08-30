//
//  TranscriptSearch.swift
//  ScribeKit
//

import Foundation

/// Why a session matched a query.
///
/// The order of the cases is the order results appear in, so ranking is a
/// property of the model rather than a comparison function's private opinion.
nonisolated enum HistoryMatchKind: Int, Comparable, Equatable, Sendable {
    /// No query was entered, so every session is shown.
    case unfiltered

    /// The whole title is the query.
    case titleExact

    /// The title begins with the query.
    case titlePrefix

    /// The title contains the query.
    case titleSubstring

    /// Recognised speech in the transcript contains the query.
    case transcript

    /// One of the captured application names contains the query.
    case source

    static func < (lhs: HistoryMatchKind, rhs: HistoryMatchKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A short piece of a transcript around a match.
///
/// The text is a verbatim substring of what the recogniser finalised: nothing
/// is re-wrapped, re-punctuated, corrected or elided inside it. Where it was
/// cut is reported as a flag rather than by putting an ellipsis into the
/// words, and the match is reported as a range rather than by wrapping it in
/// markup, so the interface can highlight it without the excerpt ever ceasing
/// to be the user's own text.
nonisolated struct TranscriptExcerpt: Equatable, Sendable {

    /// The excerpt, verbatim.
    let text: String

    /// Where the match begins, in characters from the start of ``text``.
    let matchOffset: Int

    /// How long the match is, in characters.
    let matchLength: Int

    /// The clock time the span carries, such as `10:01:33`.
    let clock: String

    /// The minute heading the span sat under, such as `10:01 AM`.
    let heading: String?

    /// The span's position in the transcript.
    let spanIndex: Int

    /// Whether text was cut from the beginning of the span.
    let isTruncatedAtStart: Bool

    /// Whether text was cut from the end of the span.
    let isTruncatedAtEnd: Bool

    /// The span's time as the transcript states it.
    var timestampDescription: String {
        guard let period = heading?.split(separator: " ").last, period == "AM" || period == "PM" else {
            return clock
        }
        return "\(clock) \(period)"
    }

    /// Creates an excerpt.
    ///
    /// - Parameters:
    ///   - text: The excerpt, verbatim.
    ///   - matchOffset: Where the match begins within it.
    ///   - matchLength: How long the match is.
    ///   - clock: The span's clock time.
    ///   - heading: The minute heading the span sat under.
    ///   - spanIndex: The span's position in the transcript.
    ///   - isTruncatedAtStart: Whether text was cut from the beginning.
    ///   - isTruncatedAtEnd: Whether text was cut from the end.
    init(
        text: String,
        matchOffset: Int,
        matchLength: Int,
        clock: String,
        heading: String?,
        spanIndex: Int,
        isTruncatedAtStart: Bool,
        isTruncatedAtEnd: Bool
    ) {
        self.text = text
        self.matchOffset = matchOffset
        self.matchLength = matchLength
        self.clock = clock
        self.heading = heading
        self.spanIndex = spanIndex
        self.isTruncatedAtStart = isTruncatedAtStart
        self.isTruncatedAtEnd = isTruncatedAtEnd
    }
}

/// One session a query matched.
nonisolated struct HistorySearchResult: Identifiable, Equatable, Sendable {

    /// The session that matched.
    let session: HistorySession

    /// Why it matched, at its strongest.
    let kind: HistoryMatchKind

    /// How many times the query occurs in recognised speech.
    let transcriptMatchCount: Int

    /// The first match in recognised speech, with the timestamp of the span it
    /// came from. `nil` when the session matched on its title or a source name
    /// alone, and when no query was entered.
    let excerpt: TranscriptExcerpt?

    /// The session's directory.
    var id: URL { session.id }

    /// Creates a result.
    ///
    /// - Parameters:
    ///   - session: The session that matched.
    ///   - kind: Why it matched.
    ///   - transcriptMatchCount: How many times the query occurs in speech.
    ///   - excerpt: The first match in speech, when there is one.
    init(
        session: HistorySession,
        kind: HistoryMatchKind,
        transcriptMatchCount: Int,
        excerpt: TranscriptExcerpt?
    ) {
        self.session = session
        self.kind = kind
        self.transcriptMatchCount = transcriptMatchCount
        self.excerpt = excerpt
    }
}

/// Deterministic text search over the transcripts History has loaded.
///
/// Plain substring matching, case-insensitive and locale-independent. There is
/// no fuzzy matching, no stemming, no embedding, no ranking model and no
/// network: a query either occurs in the text or it does not, and the same
/// query over the same folder always produces the same list in the same order.
///
/// Search runs against the in-memory documents a load produced. It reads no
/// files, so typing a character costs a walk over text that is already in
/// memory rather than a trip to disk.
///
/// What is searched is deliberately narrow. Recognised speech and the
/// meeting's own title and source names are searchable; the header block,
/// minute headings, gap blockquotes, the interruption notice and the footer
/// are things ScribeKit wrote *about* the meeting, and matching them would
/// mean every transcript answering to `ScribeKit`, `Transcription gap` or
/// `Duration`.
nonisolated enum TranscriptSearch {

    /// The longest excerpt returned for a match, in characters.
    static let excerptLength = 160

    /// Matching options: case-insensitive, and independent of the user's
    /// locale so the same query behaves the same on any Mac.
    private static let matchOptions: String.CompareOptions = [.caseInsensitive]

    /// Runs a query over the loaded transcripts.
    ///
    /// An empty query is not a failed search; it is the absence of one, so
    /// every session is returned in the order the load produced — newest
    /// first.
    ///
    /// - Parameters:
    ///   - query: What the user typed. Surrounding whitespace is ignored.
    ///   - documents: The sessions and their text, from ``HistoryService``.
    /// - Returns: The matching sessions, best match first.
    static func results(
        for query: String,
        in documents: [TranscriptSearchDocument]
    ) -> [HistorySearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return documents.map {
                HistorySearchResult(
                    session: $0.session,
                    kind: .unfiltered,
                    transcriptMatchCount: 0,
                    excerpt: nil
                )
            }
        }

        var matches: [(result: HistorySearchResult, firstSpan: Int)] = []
        for document in documents {
            guard let match = evaluate(needle, against: document) else { continue }
            matches.append(match)
        }
        return matches.sorted(by: isOrderedBefore).map(\.result)
    }

    /// Scores one document against a query.
    ///
    /// - Parameters:
    ///   - needle: The trimmed query.
    ///   - document: The session and its text.
    /// - Returns: The result and the index of the first matching span, or
    ///   `nil` when nothing matched.
    private static func evaluate(
        _ needle: String,
        against document: TranscriptSearchDocument
    ) -> (result: HistorySearchResult, firstSpan: Int)? {
        let titleKind = titleKind(needle, title: document.session.title)

        var count = 0
        var excerpt: TranscriptExcerpt?
        var firstSpan = Int.max
        for span in document.spans {
            var searchStart = span.text.startIndex
            while let range = span.text.range(
                of: needle,
                options: matchOptions,
                range: searchStart..<span.text.endIndex,
                locale: nil
            ) {
                count += 1
                if excerpt == nil {
                    firstSpan = span.index
                    excerpt = makeExcerpt(in: span, matching: range)
                }
                searchStart = range.upperBound > range.lowerBound
                    ? range.upperBound
                    : span.text.index(after: range.lowerBound)
                guard searchStart < span.text.endIndex else { break }
            }
        }

        let matchesSource = document.session.sourceNames.contains {
            $0.range(of: needle, options: matchOptions, locale: nil) != nil
        }

        var kinds: [HistoryMatchKind] = []
        if let titleKind { kinds.append(titleKind) }
        if count > 0 { kinds.append(.transcript) }
        if matchesSource { kinds.append(.source) }
        guard let kind = kinds.min() else { return nil }

        let result = HistorySearchResult(
            session: document.session,
            kind: kind,
            transcriptMatchCount: count,
            excerpt: excerpt
        )
        return (result, firstSpan)
    }

    /// How strongly a query matches a title.
    ///
    /// - Parameters:
    ///   - needle: The trimmed query.
    ///   - title: The meeting's title.
    /// - Returns: The strongest title match, or `nil` when there is none.
    private static func titleKind(_ needle: String, title: String) -> HistoryMatchKind? {
        if title.caseInsensitiveCompare(needle) == .orderedSame { return .titleExact }
        if title.range(of: needle, options: [.caseInsensitive, .anchored], locale: nil) != nil {
            return .titlePrefix
        }
        if title.range(of: needle, options: matchOptions, locale: nil) != nil { return .titleSubstring }
        return nil
    }

    /// Cuts a bounded excerpt around a match, keeping the wording intact.
    ///
    /// - Parameters:
    ///   - span: The span the match was found in.
    ///   - range: Where the match sits in the span's text.
    /// - Returns: The excerpt.
    private static func makeExcerpt(in span: TranscriptSpan, matching range: Range<String.Index>) -> TranscriptExcerpt {
        let text = span.text
        let total = text.count
        let matchStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let matchLength = text.distance(from: range.lowerBound, to: range.upperBound)

        var start = 0
        var end = total
        if total > excerptLength {
            if matchLength >= excerptLength {
                start = matchStart
                end = min(total, matchStart + excerptLength)
            } else {
                let context = (excerptLength - matchLength) / 2
                start = max(0, matchStart - context)
                end = min(total, start + excerptLength)
                start = max(0, end - excerptLength)
            }
        }

        let lower = text.index(text.startIndex, offsetBy: start)
        let upper = text.index(text.startIndex, offsetBy: end)
        return TranscriptExcerpt(
            text: String(text[lower..<upper]),
            matchOffset: matchStart - start,
            matchLength: min(matchLength, end - matchStart),
            clock: span.clock,
            heading: span.heading,
            spanIndex: span.index,
            isTruncatedAtStart: start > 0,
            isTruncatedAtEnd: end < total
        )
    }

    /// Orders two results.
    ///
    /// Strongest match kind first; within one kind, the transcript the query
    /// occurs in most often, then the one where it occurs earliest, then the
    /// newer session, and finally the directory path so the order never
    /// depends on how the folder happened to be listed.
    ///
    /// - Parameters:
    ///   - lhs: One scored result.
    ///   - rhs: Another.
    /// - Returns: Whether `lhs` sorts before `rhs`.
    private static func isOrderedBefore(
        _ lhs: (result: HistorySearchResult, firstSpan: Int),
        _ rhs: (result: HistorySearchResult, firstSpan: Int)
    ) -> Bool {
        if lhs.result.kind != rhs.result.kind { return lhs.result.kind < rhs.result.kind }
        if lhs.result.transcriptMatchCount != rhs.result.transcriptMatchCount {
            return lhs.result.transcriptMatchCount > rhs.result.transcriptMatchCount
        }
        if lhs.firstSpan != rhs.firstSpan { return lhs.firstSpan < rhs.firstSpan }
        if lhs.result.session.sortDate != rhs.result.session.sortDate {
            return lhs.result.session.sortDate > rhs.result.session.sortDate
        }
        return lhs.result.session.directory.path < rhs.result.session.directory.path
    }
}
