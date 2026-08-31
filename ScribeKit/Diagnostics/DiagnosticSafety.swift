//
//  DiagnosticSafety.swift
//  ScribeKit
//

import Foundation

/// What ScribeKit is allowed to say about itself.
///
/// Diagnostics exist so that a failure on somebody else's Mac can be explained,
/// and the material that would explain it best — what was said, what the
/// meeting was called, where it was saved — is exactly the material a
/// transcription application must never collect. So the contract is stated
/// once, here, and everything that logs or reports goes through it:
///
/// - Recognised speech, partial hypotheses, notes, review passages, search
///   queries, clipboard and file contents are never formatted at all. There is
///   no redacted form of them, because there is no reason to hold them.
/// - A meeting's title is user-written prose and is treated as content.
/// - A user-chosen folder is a path through a home directory, so absolute
///   paths, path components and bookmark bytes are never emitted; whether
///   access resolved is what has support value, and that is a boolean.
/// - Captured window titles are never read for diagnostics.
/// - Counts, durations, states, schema versions and stable technical
///   identifiers are emitted in the clear, because a diagnostic nobody can read
///   is not a diagnostic.
///
/// A framework's own error text is the one grey area: it is written by another
/// team, it can name a file, and its wording changes between releases. It is
/// never what a report means — the report carries ``DiagnosticCategory`` and,
/// where there is one, an error domain and code — and where such text is
/// logged locally for a developer it passes through ``sanitized(_:)`` first.
nonisolated enum DiagnosticSafety {

    /// The stand-in written wherever a path was removed.
    static let pathPlaceholder = "<path>"

    /// Removes anything path-shaped from framework-supplied text.
    ///
    /// System errors quote the file they failed on, and a quoted file is a
    /// folder the user picked and usually a home directory with their name in
    /// it. Rather than deciding case by case which framework is careful, every
    /// whitespace-separated run containing a path separator is replaced,
    /// including one wrapped in quotes or a URL scheme.
    ///
    /// - Parameter text: Text from outside ScribeKit.
    /// - Returns: The same text with path-shaped runs replaced by
    ///   ``pathPlaceholder``.
    static func sanitized(_ text: String) -> String {
        text
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { field -> Substring in
                looksLikePath(field) ? Substring(pathPlaceholder) : field
            }
            .joined(separator: " ")
    }

    /// Whether one whitespace-separated field carries a path.
    ///
    /// - Parameter field: One field of framework text.
    /// - Returns: `true` when the field should not be emitted as it stands.
    private static func looksLikePath(_ field: Substring) -> Bool {
        let trimmed = field.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’(),.;:"))
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("://") { return true }
        if trimmed.contains("/") { return true }
        if trimmed.hasPrefix("~") { return true }
        return false
    }

    /// The domain and code of a system error, which say what a localised
    /// sentence says without saying anything else.
    ///
    /// - Parameter error: Any error, including ScribeKit's own.
    /// - Returns: The bridged `NSError` domain and code.
    static func systemErrorIdentity(_ error: Error) -> (domain: String, code: Int) {
        let bridged = error as NSError
        return (bridged.domain, bridged.code)
    }
}
