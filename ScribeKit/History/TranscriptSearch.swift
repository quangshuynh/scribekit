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
        TranscriptClock.description(clock: clock, heading: heading)
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

/// The transcripts History has loaded, prepared for matching.
///
/// This is a disposable index, not a database. It holds nothing that is not
/// already in the documents it was built from, it is never written to disk,
/// and it is rebuilt from the Markdown on every refresh — so it can be thrown
/// away at any moment without losing anything, and the user's files remain the
/// only authority on what a meeting contains.
///
/// What it precomputes is one thing: the lower-cased ASCII bytes of each span,
/// for the spans that are pure ASCII. Case-insensitive comparison through
/// `String.range(of:options:)` was measured at roughly 140 ms per megabyte of
/// transcript in a debug build, which a search field cannot afford on every
/// keystroke; matching folded bytes is about fifteen times faster. Spans that
/// are not pure ASCII keep no folded form and are matched through Unicode-aware
/// comparison instead, because ASCII folding would be the wrong answer for
/// them and byte offsets would not be character offsets.
nonisolated struct TranscriptSearchIndex: Sendable {

    /// One document with its spans prepared for matching.
    private struct Entry {
        let document: TranscriptSearchDocument

        /// The lower-cased ASCII bytes of each span, in span order, or `nil`
        /// for a span that is not pure ASCII.
        let folded: [[UInt8]?]
    }

    private let entries: [Entry]

    /// The sessions and their text, as the load produced them.
    let documents: [TranscriptSearchDocument]

    /// Prepares a set of documents for searching.
    ///
    /// - Parameter documents: The sessions and their text, from
    ///   ``HistoryService``.
    init(_ documents: [TranscriptSearchDocument]) {
        self.documents = documents
        entries = documents.map { document in
            Entry(document: document, folded: document.spans.map { TranscriptSearchIndex.folded($0.text) })
        }
    }

    /// An empty index, for a screen that has not loaded anything.
    static let empty = TranscriptSearchIndex([])

    /// Whether there is nothing to search.
    var isEmpty: Bool { entries.isEmpty }

    /// Runs `body` over each document and the folded form of its spans.
    ///
    /// - Parameter body: Called once per document.
    fileprivate func forEachEntry(_ body: (TranscriptSearchDocument, [[UInt8]?]) -> Void) {
        for entry in entries { body(entry.document, entry.folded) }
    }

    /// The lower-cased ASCII bytes of a string.
    ///
    /// - Parameter text: The string to fold.
    /// - Returns: Its bytes with `A`–`Z` lowered, or `nil` when the string
    ///   holds anything outside ASCII.
    static func folded(_ text: String) -> [UInt8]? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.utf8.count)
        for byte in text.utf8 {
            guard byte < 0x80 else { return nil }
            bytes.append(byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z") ? byte + 32 : byte)
        }
        return bytes
    }

    /// Finds the first occurrence of one byte sequence in another.
    ///
    /// - Parameters:
    ///   - needle: The bytes to look for, already folded.
    ///   - haystack: The bytes to look in, already folded.
    ///   - start: Where to begin looking.
    /// - Returns: The offset of the match, or `nil` when there is none.
    static func firstOccurrence(of needle: [UInt8], in haystack: [UInt8], from start: Int) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        let first = needle[0]
        let limit = haystack.count - needle.count
        var index = max(0, start)
        while index <= limit {
            if haystack[index] == first {
                var offset = 1
                while offset < needle.count, haystack[index + offset] == needle[offset] { offset += 1 }
                if offset == needle.count { return index }
            }
            index += 1
        }
        return nil
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
    ///   - index: The loaded transcripts, prepared for matching.
    /// - Returns: The matching sessions, best match first.
    static func results(for query: String, in index: TranscriptSearchIndex) -> [HistorySearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return index.documents.map {
                HistorySearchResult(
                    session: $0.session,
                    kind: .unfiltered,
                    transcriptMatchCount: 0,
                    excerpt: nil
                )
            }
        }

        let foldedNeedle = TranscriptSearchIndex.folded(needle)
        var matches: [(result: HistorySearchResult, firstSpan: Int)] = []
        index.forEachEntry { document, folded in
            guard let match = evaluate(
                needle,
                foldedNeedle: foldedNeedle,
                against: document,
                folded: folded
            ) else { return }
            matches.append(match)
        }
        return matches.sorted(by: isOrderedBefore).map(\.result)
    }

    /// Runs a query over documents that have not been prepared yet.
    ///
    /// Building the index is part of the call, so this is for a one-off search
    /// rather than for a search field: a screen that searches as the user types
    /// builds the index once, when it loads.
    ///
    /// - Parameters:
    ///   - query: What the user typed.
    ///   - documents: The sessions and their text.
    /// - Returns: The matching sessions, best match first.
    static func results(
        for query: String,
        in documents: [TranscriptSearchDocument]
    ) -> [HistorySearchResult] {
        results(for: query, in: TranscriptSearchIndex(documents))
    }

    /// Scores one document against a query.
    ///
    /// - Parameters:
    ///   - needle: The trimmed query.
    ///   - foldedNeedle: Its folded ASCII bytes, or `nil` when the query is
    ///     not pure ASCII and every span must be matched through Unicode-aware
    ///     comparison.
    ///   - document: The session and its text.
    ///   - folded: The folded form of each span, from the index.
    /// - Returns: The result and the index of the first matching span, or
    ///   `nil` when nothing matched.
    private static func evaluate(
        _ needle: String,
        foldedNeedle: [UInt8]?,
        against document: TranscriptSearchDocument,
        folded: [[UInt8]?]
    ) -> (result: HistorySearchResult, firstSpan: Int)? {
        let titleKind = titleKind(needle, title: document.session.title)

        var count = 0
        var excerpt: TranscriptExcerpt?
        var firstSpan = Int.max
        for (position, span) in document.spans.enumerated() {
            for match in matches(of: needle, foldedNeedle: foldedNeedle, in: span, folded: folded[position]) {
                count += 1
                if excerpt == nil {
                    firstSpan = span.index
                    excerpt = makeExcerpt(in: span, at: match.offset, length: match.length)
                }
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

    /// Every occurrence of a query in one span, as character offsets.
    ///
    /// A pure-ASCII query in a pure-ASCII span is matched on folded bytes,
    /// where a byte offset is a character offset. Anything else — a span with
    /// a character outside ASCII, or a query with one — is matched through
    /// `String.range(of:options:)`, which is the correct answer for text
    /// ASCII folding would mishandle.
    ///
    /// - Parameters:
    ///   - needle: The trimmed query.
    ///   - foldedNeedle: Its folded ASCII bytes, when it has them.
    ///   - span: The span to search.
    ///   - folded: The span's folded ASCII bytes, when it has them.
    /// - Returns: The offset and length of each match, in characters, in the
    ///   order they occur.
    private static func matches(
        of needle: String,
        foldedNeedle: [UInt8]?,
        in span: TranscriptSpan,
        folded: [UInt8]?
    ) -> [(offset: Int, length: Int)] {
        var found: [(offset: Int, length: Int)] = []

        if let foldedNeedle, let folded {
            var from = 0
            while let offset = TranscriptSearchIndex.firstOccurrence(of: foldedNeedle, in: folded, from: from) {
                found.append((offset, foldedNeedle.count))
                from = offset + max(1, foldedNeedle.count)
            }
            return found
        }

        let text = span.text
        var searchStart = text.startIndex
        while let range = text.range(of: needle, options: matchOptions, range: searchStart..<text.endIndex, locale: nil) {
            found.append((
                text.distance(from: text.startIndex, to: range.lowerBound),
                text.distance(from: range.lowerBound, to: range.upperBound)
            ))
            searchStart = range.upperBound > range.lowerBound
                ? range.upperBound
                : text.index(after: range.lowerBound)
            guard searchStart < text.endIndex else { break }
        }
        return found
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
    ///   - matchStart: Where the match begins, in characters.
    ///   - matchLength: How long the match is, in characters.
    /// - Returns: The excerpt.
    private static func makeExcerpt(
        in span: TranscriptSpan,
        at matchStart: Int,
        length matchLength: Int
    ) -> TranscriptExcerpt {
        let text = span.text
        let total = text.count

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
