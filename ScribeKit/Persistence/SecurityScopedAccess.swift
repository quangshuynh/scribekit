//
//  SecurityScopedAccess.swift
//  ScribeKit
//

import Foundation

/// Bounds the lifetime of sandboxed access to a user-selected directory.
///
/// macOS grants a sandboxed process access to a bookmarked directory only
/// between `startAccessingSecurityScopedResource()` and its stop counterpart,
/// and the two are balanced by reference count. ScribeKit therefore acquires
/// access for the duration of a piece of work rather than holding it open
/// because a URL happens to exist.
///
/// Ownership boundary: restoring a save location borrows access only long
/// enough to validate and renew it. Nothing here owns a session-length lease.
/// When session writing arrives it will hold access for exactly as long as the
/// session lives, by keeping its own scope open, not by inheriting one from
/// restoration.
nonisolated enum SecurityScopedAccess {
    /// Runs work with security-scoped access to a directory held open.
    ///
    /// - Parameters:
    ///   - url: A directory resolved from a security-scoped bookmark.
    ///   - body: Work to perform while access is held.
    /// - Returns: Whatever `body` returns.
    /// - Throws: ``SaveLocationError`` with ``SaveLocationError/Reason/accessDenied``
    ///   when the system refuses access, or anything `body` throws.
    static func withAccess<T>(to url: URL, perform body: (URL) throws -> T) throws -> T {
        guard url.startAccessingSecurityScopedResource() else {
            throw SaveLocationError(.accessDenied)
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return try body(url)
    }
}
