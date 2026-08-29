//
//  TranscriptMarkdownFormatter.swift
//  ScribeKit
//

import Foundation

/// Renders a transcript as Markdown.
///
/// Formatting is deliberately separated from writing: this type produces
/// strings and touches no filesystem, so the exact bytes a session writes can
/// be checked against golden text without creating a file.
///
/// Presentation is deterministic. The transcript is a document the user keeps,
/// so its date and clock times follow fixed rules — an ISO date and a
/// twelve-hour English clock — rather than the locale the Mac happens to be
/// set to, for the same reason ``SessionDirectoryName`` fixes its date format:
/// a file's contents should not change with a system setting. The time zone is
/// explicit and defaults to the one the meeting was held in.
///
/// Recognised text is written exactly as the recogniser finalised it, apart
/// from the whitespace that joins one span to the previous one. Nothing here
/// corrects, escapes, re-wraps or otherwise edits it, so a transcript never
/// contains a character that was not spoken.
///
/// The only state the formatter keeps is the last minute it emitted a heading
/// for, so headings appear once per minute rather than once per segment.
nonisolated struct TranscriptMarkdownFormatter: Equatable, Sendable {

    /// Wall-clock moment the run's timeline starts from; a segment's offset is
    /// measured from here.
    let startedAt: Date

    /// The zone clock times are written in.
    let timeZone: TimeZone

    /// The minute a heading was last written for, as whole minutes since the
    /// reference date. Every real time zone offset is a whole number of
    /// minutes, so this bucket is the same in any zone.
    private var lastMinuteIndex: Int?

    /// Creates a formatter for one session.
    ///
    /// - Parameters:
    ///   - startedAt: The wall-clock moment the run's audio timeline begins.
    ///   - timeZone: The zone clock times are written in. The current zone by
    ///     default, so a transcript reads in the time the meeting happened.
    init(startedAt: Date, timeZone: TimeZone = .current) {
        self.startedAt = startedAt
        self.timeZone = timeZone
    }

    /// The transcript's opening block, written once when the file is created.
    ///
    /// Only facts ScribeKit has are stated. The moment the meeting ended is
    /// not one of them until it ends, so it belongs to ``footer(endedAt:)``
    /// rather than to a header field that would have to be rewritten.
    ///
    /// - Parameters:
    ///   - title: The meeting's title, already resolved to a display title.
    ///   - sourceNames: Display names of the applications being captured.
    ///   - localeIdentifier: The BCP-47 locale recognition runs in.
    /// - Returns: Markdown ending in the transcript heading and a blank line.
    func header(title: String, sourceNames: [String], localeIdentifier: String) -> String {
        var text = "# \(title)\n\n"
        text += "**Date:** \(SessionDirectoryName.datePrefix(for: startedAt, timeZone: timeZone))\n"
        text += "**Started:** \(clock(startedAt, includingSeconds: false))\n"
        if !sourceNames.isEmpty {
            text += "**Sources:** \(sourceNames.joined(separator: ", "))\n"
        }
        text += "**Language:** \(localeIdentifier)\n"
        text += "**Captured by:** ScribeKit\n\n"
        text += "## Transcript\n\n"
        return text
    }

    /// One finalised span, preceded by a minute heading when the minute has
    /// changed since the last span.
    ///
    /// - Parameter segment: The finalised span to render. Its offset is
    ///   audio-relative, so the time written is when the words were spoken,
    ///   not when they reached disk.
    /// - Returns: Markdown ending in a blank line.
    mutating func finalSegment(_ segment: TranscriptSegment) -> String {
        let spokenAt = wallClock(offset: segment.startTime)
        var text = ""
        let minute = Self.minuteIndex(of: spokenAt)
        if minute != lastMinuteIndex {
            lastMinuteIndex = minute
            text += "### \(clock(spokenAt, includingSeconds: false))\n\n"
        }
        text += "**\(clock(spokenAt, includingSeconds: true))**\n\n"
        text += segment.displayText
        text += "\n\n"
        return text
    }

    /// A marker for audio that was never transcribed.
    ///
    /// A gap does not open a minute heading. It is an interruption in the
    /// timeline rather than speech, and a gap whose position is unknown has no
    /// minute to head.
    ///
    /// - Parameter gap: The untranscribed stretch.
    /// - Returns: Markdown ending in a blank line.
    func gap(_ gap: TranscriptGap) -> String {
        let seconds = String(format: "%.1f", gap.duration)
        let position = gap.startTime.map { " around \(clock(wallClock(offset: $0), includingSeconds: true))" } ?? ""
        return "> **Transcription gap:** approximately \(seconds) seconds of audio"
            + "\(position) was not transcribed; \(gap.reasonDescription).\n\n"
    }

    /// The closing block, appended once when the session ends.
    ///
    /// Recording completion as a footer keeps the file append-only: nothing
    /// already written has to be rewritten to state when the meeting ended.
    ///
    /// - Parameter endedAt: The wall-clock moment the session finished.
    /// - Returns: Markdown ending in a newline.
    func footer(endedAt: Date) -> String {
        var text = "---\n\n"
        text += "**Ended:** \(clock(endedAt, includingSeconds: false))\n"
        text += "**Duration:** \(Self.durationDescription(endedAt.timeIntervalSince(startedAt)))\n"
        return text
    }

    /// The wall-clock moment an audio-relative offset refers to.
    ///
    /// - Parameter offset: Seconds from the first captured frame of the run.
    /// - Returns: The moment that audio was heard.
    func wallClock(offset: Double) -> Date {
        startedAt.addingTimeInterval(offset)
    }

    /// Formats a moment as a twelve-hour clock time.
    ///
    /// The format is fixed rather than localised, so the file reads the same
    /// on any Mac. Written by hand rather than with a `DateFormatter` because
    /// there is nothing to localise and nothing to configure wrongly.
    ///
    /// A time to the second omits the period. It always appears under a minute
    /// heading that carries one, and repeating `AM` on every line of a
    /// transcript adds noise rather than meaning.
    ///
    /// - Parameters:
    ///   - date: The moment to format.
    ///   - includingSeconds: Whether to include seconds, and so to omit the
    ///     period.
    /// - Returns: A string such as `11:04 AM` or `11:04:02`.
    private func clock(_ date: Date, includingSeconds: Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour24 = parts.hour ?? 0
        let hour = hour24 % 12 == 0 ? 12 : hour24 % 12
        return includingSeconds
            ? String(format: "%d:%02d:%02d", hour, parts.minute ?? 0, parts.second ?? 0)
            : String(format: "%d:%02d %@", hour, parts.minute ?? 0, hour24 < 12 ? "AM" : "PM")
    }

    /// The minute a moment falls in, counted from the reference date.
    ///
    /// - Parameter date: The moment to bucket.
    /// - Returns: Whole minutes since the reference date.
    private static func minuteIndex(of date: Date) -> Int {
        Int((date.timeIntervalSinceReferenceDate / 60).rounded(.down))
    }

    /// Describes a length of time in the coarsest unit that stays informative.
    ///
    /// - Parameter seconds: The length, which is clamped at zero.
    /// - Returns: A string such as `2 h 14 min`, `47 min 12 s` or `38 s`.
    static func durationDescription(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        if hours > 0 { return "\(hours) h \(minutes) min" }
        if minutes > 0 { return "\(minutes) min \(total % 60) s" }
        return "\(total) s"
    }
}
