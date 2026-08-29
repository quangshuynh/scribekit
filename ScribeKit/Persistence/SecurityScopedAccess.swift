//
//  SecurityScopedAccess.swift
//  ScribeKit
//

import Foundation
import Synchronization

/// Starts and stops sandboxed access to a user-selected directory.
///
/// The protocol exists so the two calls macOS balances by reference count live
/// in exactly one place and can be substituted in tests, where a temporary
/// directory carries no security scope and the system call would refuse.
nonisolated protocol SecurityScopedResourceAccessing: Sendable {
    /// Begins access to a directory resolved from a security-scoped bookmark.
    ///
    /// - Parameter url: The directory to open access to.
    /// - Returns: Whether the system granted access.
    func startAccess(to url: URL) -> Bool

    /// Ends one previously granted access to a directory.
    ///
    /// - Parameter url: The directory access was granted for.
    func stopAccess(to url: URL)
}

/// Security-scoped access as macOS provides it.
nonisolated struct SystemSecurityScopedResourceAccess: SecurityScopedResourceAccessing {
    /// Creates the system-backed accessor.
    init() {}

    func startAccess(to url: URL) -> Bool { url.startAccessingSecurityScopedResource() }

    func stopAccess(to url: URL) { url.stopAccessingSecurityScopedResource() }
}

/// A held claim on a user-selected directory, released exactly once.
///
/// macOS grants a sandboxed process access to a bookmarked directory only
/// between `startAccessingSecurityScopedResource()` and its stop counterpart.
/// A lease makes that pairing an object with an owner and a lifetime, so a
/// session can hold access for as long as it is writing without the two calls
/// being scattered across the code that happens to need a path.
///
/// Ownership boundary: whoever acquires a lease releases it. A transcript
/// session holds one from the moment its directory is created until its writer
/// is flushed and closed, and no longer; restoring a save location borrows
/// access through ``SecurityScopedAccess/withAccess(to:using:perform:)``
/// instead and never leaves one open.
nonisolated final class SecurityScopedLease: Sendable {

    /// The directory access is held for.
    let url: URL

    private let access: any SecurityScopedResourceAccessing
    private let isHeld = Mutex(true)

    private init(url: URL, access: any SecurityScopedResourceAccessing) {
        self.url = url
        self.access = access
    }

    /// Opens access to a directory and keeps it open until the lease is
    /// released.
    ///
    /// - Parameters:
    ///   - url: A directory resolved from a security-scoped bookmark, or
    ///     selected by the user in this launch.
    ///   - access: How access is started and stopped. The system by default.
    /// - Returns: A lease holding access open.
    /// - Throws: ``SaveLocationError`` with
    ///   ``SaveLocationError/Reason/accessDenied`` when the system refuses.
    static func acquire(
        _ url: URL,
        using access: any SecurityScopedResourceAccessing = SystemSecurityScopedResourceAccess()
    ) throws -> SecurityScopedLease {
        guard access.startAccess(to: url) else { throw SaveLocationError(.accessDenied) }
        return SecurityScopedLease(url: url, access: access)
    }

    /// Gives up the claim. Calling it again does nothing, so teardown paths
    /// can release unconditionally without unbalancing the reference count.
    func release() {
        let wasHeld = isHeld.withLock { held in
            defer { held = false }
            return held
        }
        guard wasHeld else { return }
        access.stopAccess(to: url)
    }

    /// Releases a lease its owner dropped without releasing it. This is a
    /// safety net for a path that failed, not the intended way to end one.
    deinit { release() }
}

/// Bounds the lifetime of sandboxed access to a user-selected directory.
///
/// Use this for work that finishes inside one call, such as validating a
/// restored folder. Work that outlives a call — a meeting writing a transcript
/// — takes a ``SecurityScopedLease`` instead.
nonisolated enum SecurityScopedAccess {
    /// Runs work with security-scoped access to a directory held open.
    ///
    /// - Parameters:
    ///   - url: A directory resolved from a security-scoped bookmark.
    ///   - access: How access is started and stopped. The system by default.
    ///   - body: Work to perform while access is held.
    /// - Returns: Whatever `body` returns.
    /// - Throws: ``SaveLocationError`` with ``SaveLocationError/Reason/accessDenied``
    ///   when the system refuses access, or anything `body` throws.
    static func withAccess<T>(
        to url: URL,
        using access: any SecurityScopedResourceAccessing = SystemSecurityScopedResourceAccess(),
        perform body: (URL) throws -> T
    ) throws -> T {
        let lease = try SecurityScopedLease.acquire(url, using: access)
        defer { lease.release() }
        return try body(lease.url)
    }
}
