//
//  SessionDirectoryName.swift
//  ScribeKit
//

import Foundation

/// Names the directory a session's artifacts will live in, such as
/// `2026-08-31-ios-training-day-2`.
///
/// The policy is pure: it derives a name from a date and a title and touches
/// no filesystem. Collision handling is expressed as a predicate, so the rule
/// can be tested without creating directories and reused unchanged once
/// session creation exists.
nonisolated enum SessionDirectoryName {
    /// Slug used when a title contributes no usable characters.
    static let fallbackSlug = "untitled-meeting"

    /// Longest title slug kept, so names stay comfortable in a file listing.
    static let maximumSlugLength = 60

    /// Highest numeric suffix tried before falling back to a time-based one.
    static let maximumCollisionSuffix = 999

    /// The only characters a slug keeps; everything else becomes a separator.
    private static let slugCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")

    /// Builds a directory name for a session.
    ///
    /// - Parameters:
    ///   - date: When the session was created.
    ///   - title: The user-entered title, which may be empty or unusable.
    ///   - timeZone: Zone the date is interpreted in. Defaults to the current
    ///     zone, so a session is filed under the day the user experienced.
    /// - Returns: A filesystem-safe name of the form `yyyy-MM-dd-title-slug`.
    static func make(date: Date, title: String, timeZone: TimeZone = .current) -> String {
        "\(datePrefix(for: date, timeZone: timeZone))-\(slug(for: title))"
    }

    /// Builds a directory name that avoids names already in use.
    ///
    /// A numeric suffix is appended (`-2`, `-3`, …) until the name is free. If
    /// the whole numeric range is taken, the session's time of day is used
    /// instead, which stays deterministic for a given date.
    ///
    /// - Parameters:
    ///   - date: When the session was created.
    ///   - title: The user-entered title.
    ///   - timeZone: Zone the date is interpreted in.
    ///   - isTaken: Answers whether a candidate name already exists. The caller
    ///     decides what "exists" means; this policy never looks at disk.
    /// - Returns: A name for which `isTaken` returned `false`, or the
    ///   time-based fallback.
    static func make(
        date: Date,
        title: String,
        timeZone: TimeZone = .current,
        isTaken: (String) -> Bool
    ) -> String {
        let base = make(date: date, title: title, timeZone: timeZone)
        guard isTaken(base) else { return base }

        for suffix in 2...maximumCollisionSuffix {
            let candidate = "\(base)-\(suffix)"
            if !isTaken(candidate) { return candidate }
        }
        return "\(base)-\(timeOfDaySuffix(for: date, timeZone: timeZone))"
    }

    /// Formats the date part of a session name.
    ///
    /// The Gregorian calendar and fixed digits are used deliberately: the name
    /// is an identifier on disk, so it must not change with the user's calendar
    /// or locale settings.
    ///
    /// - Parameters:
    ///   - date: The date to format.
    ///   - timeZone: Zone the date is interpreted in.
    /// - Returns: The date as `yyyy-MM-dd`.
    static func datePrefix(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Reduces a meeting title to lower-case ASCII words joined by hyphens.
    ///
    /// Diacritics are folded, every other character becomes a separator, runs
    /// of separators collapse, and the result is truncated on a word boundary.
    /// A title that contributes nothing usable — empty, punctuation only, or
    /// written in a script that does not fold to ASCII — yields
    /// ``fallbackSlug`` rather than an empty name.
    ///
    /// - Parameter title: The user-entered title.
    /// - Returns: A filesystem-safe slug.
    static func slug(for title: String) -> String {
        let folded = title.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )

        var words: [String] = []
        var current = ""
        for scalar in folded.unicodeScalars {
            if slugCharacters.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }

        var slug = ""
        for word in words {
            let candidate = slug.isEmpty ? word : "\(slug)-\(word)"
            if candidate.count > maximumSlugLength {
                if slug.isEmpty { slug = String(word.prefix(maximumSlugLength)) }
                break
            }
            slug = candidate
        }
        return slug.isEmpty ? fallbackSlug : slug
    }

    /// Formats a session's time of day, used only when every numeric suffix is
    /// already taken.
    ///
    /// - Parameters:
    ///   - date: The date to format.
    ///   - timeZone: Zone the date is interpreted in.
    /// - Returns: The time as `HHmmss`.
    private static func timeOfDaySuffix(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d%02d%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}
