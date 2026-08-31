//
//  TranscriptDocument.swift
//  ScribeKit
//

import Foundation

/// One finalised span as it stands in a written transcript.
///
/// The clock time and the minute heading above it are kept exactly as
/// ``TranscriptMarkdownFormatter`` wrote them. Nothing is re-derived: the
/// seconds line carries no period of its own, the heading above it does, and
/// keeping the pair verbatim states what the document says without inventing
/// an offset from it. That is the information a later interval needs to seek a
/// retained recording, preserved rather than approximated.
nonisolated struct TranscriptSpan: Identifiable, Equatable, Sendable {

    /// The span's position in the document, counting from zero.
    let index: Int

    /// The clock time written above the span, such as `10:01:33 AM`, or
    /// `10:01:33` in a transcript written before periods were always stated.
    let clock: String

    /// The minute heading in effect, such as `10:01 AM`, or `nil` when the
    /// span appeared before any heading.
    let heading: String?

    /// The recognised text, exactly as it was written to the file.
    let text: String

    /// The span's position, which identifies it within one document.
    var id: Int { index }

    /// Creates a span.
    ///
    /// - Parameters:
    ///   - index: The span's position in the document.
    ///   - clock: The clock time written above it.
    ///   - heading: The minute heading in effect.
    ///   - text: The recognised text, verbatim.
    init(index: Int, clock: String, heading: String?, text: String) {
        self.index = index
        self.clock = clock
        self.heading = heading
        self.text = text
    }

    /// The span's time as the document states it.
    var timestampDescription: String {
        TranscriptClock.description(clock: clock, heading: heading)
    }
}

/// How a written clock time is read back.
///
/// Transcripts written from Interval 19 onwards state `AM` or `PM` on every
/// wall-clock time, so a span's own line is already unambiguous. Older ones
/// left the period to the minute heading above the span, and those files are
/// not rewritten, so the heading is still consulted when the line itself is
/// silent.
nonisolated enum TranscriptClock {

    /// The period a written time carries, if it carries one.
    ///
    /// - Parameter clock: A clock time as a transcript states it.
    /// - Returns: `AM`, `PM`, or `nil` when the time states neither.
    static func period(of clock: some StringProtocol) -> String? {
        guard let last = clock.split(separator: " ").last else { return nil }
        return last == "AM" || last == "PM" ? String(last) : nil
    }

    /// A span's time as the document states it: its own period when it has
    /// one, the minute heading's when it does not, and the bare time when
    /// neither states one.
    ///
    /// - Parameters:
    ///   - clock: The clock time written above the span.
    ///   - heading: The minute heading in effect, when there is one.
    /// - Returns: The time to show for the span.
    static func description(clock: String, heading: String?) -> String {
        if period(of: clock) != nil { return clock }
        guard let heading, let period = period(of: heading) else { return clock }
        return "\(clock) \(period)"
    }
}

/// One `**Key:** value` line from a transcript's header or footer.
nonisolated struct TranscriptHeaderField: Equatable, Sendable {

    /// The field's name, such as `Sources`.
    let key: String

    /// The field's value, exactly as written.
    let value: String

    /// Creates a field.
    ///
    /// - Parameters:
    ///   - key: The field's name.
    ///   - value: The field's value.
    init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// A ScribeKit Markdown transcript, read back into its parts.
///
/// The parser exists so history can search what was *said* without searching
/// what ScribeKit *wrote about* the meeting. Header fields, the transcript
/// heading, minute headings, gap blockquotes, the interruption notice and the
/// footer are all structure; only the paragraphs the recogniser produced are
/// recognised speech, and only those become ``spans``.
///
/// Structure is never guessed at from the shape of a line. The document's
/// grammar is the one ``TranscriptMarkdownFormatter`` writes, and in it a
/// finalised span is always a clock line, a blank line and then one paragraph.
/// So the parser consumes that paragraph *positionally* — whatever it contains
/// — and only tests a line against a structural pattern when it is not
/// expecting recognised text. A sentence that happens to read `---`, to begin
/// with `>` or to look like a heading is therefore kept as speech rather than
/// mistaken for markup, without the format having to promise that recognised
/// words avoid punctuation.
///
/// Parsing is pure: it takes a string and touches no filesystem, and it
/// returns what the document says rather than a corrected version of it.
/// Nothing here rewrites, normalises or repairs a transcript.
nonisolated struct TranscriptDocument: Equatable, Sendable {

    /// The header field every ScribeKit transcript carries.
    static let capturedByKey = "Captured by"

    /// The value that field carries.
    static let capturedByValue = "ScribeKit"

    /// The header field naming the captured applications.
    static let sourcesKey = "Sources"

    /// The header field naming the recognition locale.
    static let languageKey = "Language"

    /// The header field naming the meeting's date.
    static let dateKey = "Date"

    /// The heading that opens the transcript body.
    static let transcriptHeading = "## Transcript"

    /// The meeting's title, from the document's `#` heading.
    let title: String?

    /// The `**Key:** value` lines of the header block, in the order written.
    let headerFields: [TranscriptHeaderField]

    /// The finalised spans, in the order written.
    let spans: [TranscriptSpan]

    /// Whether the document carries the evidence that ScribeKit wrote it.
    ///
    /// Three deterministic facts, all of them produced by
    /// ``TranscriptMarkdownFormatter/header(title:sourceNames:localeIdentifier:)``:
    /// a title heading, a `**Captured by:** ScribeKit` field, and the
    /// transcript heading that opens the body. A Markdown file the user
    /// happens to keep in the same folder has none of them, so it is not
    /// mistaken for a meeting.
    let isScribeKitTranscript: Bool

    /// Creates a document.
    ///
    /// - Parameters:
    ///   - title: The meeting's title.
    ///   - headerFields: The header's fields.
    ///   - spans: The finalised spans.
    ///   - isScribeKitTranscript: Whether ScribeKit's own header was found.
    init(
        title: String?,
        headerFields: [TranscriptHeaderField],
        spans: [TranscriptSpan],
        isScribeKitTranscript: Bool
    ) {
        self.title = title
        self.headerFields = headerFields
        self.spans = spans
        self.isScribeKitTranscript = isScribeKitTranscript
    }

    /// A document with nothing in it, used for a file that is not a ScribeKit
    /// transcript.
    static let unrecognised = TranscriptDocument(
        title: nil,
        headerFields: [],
        spans: [],
        isScribeKitTranscript: false
    )

    /// The value of one header field.
    ///
    /// - Parameter key: The field's name.
    /// - Returns: Its value, or `nil` when the header has no such field.
    func headerValue(_ key: String) -> String? {
        headerFields.first { $0.key == key }?.value
    }

    /// The applications the header names, split back into separate names.
    ///
    /// - Returns: The names, or an empty array when the header names none.
    var sourceNames: [String] {
        guard let value = headerValue(Self.sourcesKey) else { return [] }
        return value
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The recognition locale the header names.
    var localeIdentifier: String? { headerValue(Self.languageKey) }

    // MARK: - Parsing

    /// Reads a transcript.
    ///
    /// - Parameter text: The file's contents.
    /// - Returns: What the document says. A file that is not a ScribeKit
    ///   transcript comes back as ``unrecognised`` rather than as a guess.
    static func parse(_ text: String) -> TranscriptDocument {
        let lines = text.components(separatedBy: "\n")
        var index = 0

        while index < lines.count, lines[index].isBlank { index += 1 }
        guard index < lines.count, let title = titleHeading(lines[index]) else { return .unrecognised }
        index += 1

        var fields: [TranscriptHeaderField] = []
        var reachedBody = false
        while index < lines.count {
            let line = lines[index]
            if line.isBlank { index += 1; continue }
            if line == transcriptHeading { index += 1; reachedBody = true; break }
            guard let field = headerField(line) else { break }
            fields.append(field)
            index += 1
        }

        let capturedByScribeKit = fields.contains {
            $0.key == capturedByKey && $0.value == capturedByValue
        }
        guard reachedBody, capturedByScribeKit else { return .unrecognised }

        return TranscriptDocument(
            title: title,
            headerFields: fields,
            spans: parseBody(lines, from: index),
            isScribeKitTranscript: true
        )
    }

    /// Reads the transcript body: minute headings, finalised spans, and the
    /// structural remarks between them.
    ///
    /// - Parameters:
    ///   - lines: The document's lines.
    ///   - start: The first line after the transcript heading.
    /// - Returns: The finalised spans, in order.
    private static func parseBody(_ lines: [String], from start: Int) -> [TranscriptSpan] {
        var spans: [TranscriptSpan] = []
        var heading: String?
        var index = start

        while index < lines.count {
            let line = lines[index]
            if line.isBlank { index += 1; continue }

            if let minute = minuteHeading(line) {
                heading = minute
                index += 1
                continue
            }

            guard let clock = spanClock(line) else {
                index += 1
                continue
            }
            index += 1

            while index < lines.count, lines[index].isBlank { index += 1 }
            var paragraph: [String] = []
            while index < lines.count, !lines[index].isBlank {
                paragraph.append(lines[index])
                index += 1
            }
            guard !paragraph.isEmpty else { continue }
            spans.append(TranscriptSpan(
                index: spans.count,
                clock: clock,
                heading: heading,
                text: paragraph.joined(separator: "\n")
            ))
        }
        return spans
    }

    /// The meeting title a `# ` heading carries.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: The title, or `nil` when the line is not a title heading.
    private static func titleHeading(_ line: String) -> String? {
        guard line.hasPrefix("# ") else { return nil }
        let title = String(line.dropFirst(2))
        return title.isBlank ? nil : title
    }

    /// The clock time a `### ` heading carries.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: The heading's text, or `nil` when the line is not one.
    private static func minuteHeading(_ line: String) -> String? {
        guard line.hasPrefix("### ") else { return nil }
        let heading = String(line.dropFirst(4))
        return heading.isBlank ? nil : heading
    }

    /// The clock time a span's `**h:mm:ss AM**` line carries.
    ///
    /// The digits are checked rather than assumed, so a bold line that is not
    /// a timestamp — the footer's `**Ended:**`, for instance — does not open a
    /// span.
    ///
    /// The period is optional because transcripts written before Interval 19
    /// left it to the minute heading, and a transcript already on disk is
    /// never rewritten. Both shapes open a span, and the time is returned
    /// exactly as the document states it.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: The clock time, or `nil` when the line is not a span marker.
    private static func spanClock(_ line: String) -> String? {
        guard line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4 else { return nil }
        let clock = String(line.dropFirst(2).dropLast(2))
        var time = Substring(clock)
        if let separator = clock.lastIndex(of: " ") {
            guard TranscriptClock.period(of: clock[clock.index(after: separator)...]) != nil else { return nil }
            time = clock[..<separator]
        }
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 1 || parts[0].count == 2,
              parts[1].count == 2,
              parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) })
        else { return nil }
        return clock
    }

    /// The key and value of a `**Key:** value` line.
    ///
    /// - Parameter line: The line to read.
    /// - Returns: The field, or `nil` when the line has another shape.
    private static func headerField(_ line: String) -> TranscriptHeaderField? {
        guard line.hasPrefix("**"), let separator = line.range(of: ":** ") else { return nil }
        let key = String(line[line.index(line.startIndex, offsetBy: 2)..<separator.lowerBound])
        guard !key.isBlank, !key.contains("*") else { return nil }
        return TranscriptHeaderField(key: key, value: String(line[separator.upperBound...]))
    }
}

// MARK: - Line helpers

private extension String {
    /// Whether the line holds nothing but whitespace.
    nonisolated var isBlank: Bool { allSatisfy(\.isWhitespace) }
}

private extension Character {
    /// Whether the character is one of the ten ASCII digits, independently of
    /// any other numeral system Unicode considers a digit.
    nonisolated var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}
