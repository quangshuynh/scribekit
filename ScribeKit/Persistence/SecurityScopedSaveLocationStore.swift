//
//  SecurityScopedSaveLocationStore.swift
//  ScribeKit
//

import Foundation

/// Remembers the user's save location as a security-scoped bookmark held in a
/// local preference store.
///
/// This is the only type that knows about bookmark data. It keeps App Sandbox
/// intact: access comes from the folder the user picked in the system open
/// panel, is renewed when the folder moves, and is never widened to a
/// directory ScribeKit chose for itself.
nonisolated final class SecurityScopedSaveLocationStore: SaveLocationPersisting {
    /// Preference key holding the bookmark for the chosen save location.
    static let defaultsKey = "com.scribekit.saveLocation.bookmark"

    private let defaults: UserDefaults
    private let key: String

    /// Creates a store.
    ///
    /// - Parameters:
    ///   - defaults: Where bookmark data is kept. Defaults to the standard
    ///     preferences; tests pass an isolated suite.
    ///   - key: Preference key for the bookmark data.
    init(defaults: UserDefaults = .standard, key: String = SecurityScopedSaveLocationStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    /// Remembers a directory the user selected in the system open panel.
    ///
    /// Access is held only while the bookmark is created. A URL that carries no
    /// security scope — as in a test, or outside the sandbox — is bookmarked
    /// directly rather than being rejected.
    ///
    /// - Parameter url: The user-selected directory.
    /// - Throws: ``SaveLocationError`` with
    ///   ``SaveLocationError/Reason/bookmarkCreationFailed`` when macOS will
    ///   not issue durable access for the directory.
    func save(_ url: URL) throws {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw SaveLocationError(.bookmarkCreationFailed, underlying: error)
        }
        defaults.set(data, forKey: key)
    }

    /// Restores the remembered directory, renewing stale access data.
    ///
    /// The directory is validated while access is held and released again
    /// before returning, so restoration never leaves an open lease behind.
    ///
    /// - Returns: The remembered directory, or `nil` when none is stored.
    /// - Throws: ``SaveLocationError`` describing why a stored location is not
    ///   usable. Malformed stored data is reported rather than silently
    ///   replaced, and ScribeKit never falls back to a folder of its own.
    func restore() throws -> URL? {
        guard let stored = defaults.object(forKey: key) else { return nil }
        guard let data = stored as? Data, !data.isEmpty else {
            throw SaveLocationError(.malformedStoredData)
        }

        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw SaveLocationError(.bookmarkResolutionFailed, underlying: error)
        }

        try SecurityScopedAccess.withAccess(to: url) { directory in
            try validate(directory)
            if isStale { try renewBookmark(for: directory) }
        }
        return url
    }

    func clear() throws {
        defaults.removeObject(forKey: key)
    }

    /// Confirms the restored location still exists and is a directory.
    ///
    /// - Parameter url: The restored location, with access held.
    /// - Throws: ``SaveLocationError`` with
    ///   ``SaveLocationError/Reason/directoryUnavailable`` when the location is
    ///   missing or is not a directory.
    private func validate(_ url: URL) throws {
        let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
        guard isDirectory == true else {
            throw SaveLocationError(.directoryUnavailable)
        }
    }

    /// Replaces stored access data that macOS reported as stale.
    ///
    /// - Parameter url: The restored directory, with access held.
    /// - Throws: ``SaveLocationError`` with
    ///   ``SaveLocationError/Reason/staleBookmarkNotRefreshed`` when new access
    ///   data cannot be created, because the old data will not keep working.
    private func renewBookmark(for url: URL) throws {
        do {
            try save(url)
        } catch {
            throw SaveLocationError(.staleBookmarkNotRefreshed, underlying: error)
        }
    }
}
