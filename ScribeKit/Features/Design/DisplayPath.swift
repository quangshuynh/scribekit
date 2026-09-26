//
//  DisplayPath.swift
//  ScribeKit
//

import Darwin
import Foundation

/// How a file location is written on screen.
///
/// Paths are shown relative to the home folder, the way the Finder and
/// Terminal write them: `~/Documents/Meetings` says where a folder is without
/// repeating the account name on every screen and in every screenshot.
///
/// The home folder is the user's own, not the sandbox container
/// `NSHomeDirectory()` reports inside App Sandbox, because the folders shown
/// are ones the user chose in a panel and live outside the container.
nonisolated enum DisplayPath {

    /// A path for display, with the home folder written as `~`.
    ///
    /// - Parameters:
    ///   - url: The file or folder.
    ///   - home: The home folder's path; the current user's when omitted.
    /// - Returns: The path, abbreviated when it is inside `home`.
    static func abbreviated(_ url: URL, home: String? = userHome) -> String {
        abbreviated(url.path(percentEncoded: false), home: home)
    }

    /// A path for display, with the home folder written as `~`.
    ///
    /// - Parameters:
    ///   - path: The absolute path.
    ///   - home: The home folder's path, or `nil` to leave the path alone.
    /// - Returns: The path, abbreviated when it is inside `home`.
    static func abbreviated(_ path: String, home: String?) -> String {
        guard let home, !home.isEmpty else { return path }
        let root = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard !root.isEmpty else { return path }
        if path == root || path == root + "/" { return "~" }
        guard path.hasPrefix(root + "/") else { return path }
        return "~" + path.dropFirst(root.count)
    }

    /// The current user's home folder, read from the account database rather
    /// than the environment, which App Sandbox points at the container.
    static var userHome: String? {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return nil }
        return String(cString: directory)
    }
}
