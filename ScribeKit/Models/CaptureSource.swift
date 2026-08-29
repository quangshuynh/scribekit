//
//  CaptureSource.swift
//  ScribeKit
//

import Foundation

/// A selectable origin of meeting audio.
///
/// This is a plain value describing *what* the user picked. It intentionally
/// carries no capture machinery: binding a source to a real system audio
/// stream is the responsibility of a later interval, and nothing here assumes
/// a particular capture API.
nonisolated struct CaptureSource: Identifiable, Hashable, Codable, Sendable {
    /// Stable identifier used to persist and compare selections.
    ///
    /// For application sources this is the bundle identifier, so a selection
    /// survives an application relaunch.
    let id: String

    /// Name shown to the user, such as an application name.
    let displayName: String

    /// The kind of audio this source represents.
    let kind: Kind

    /// The category of a capture source.
    enum Kind: String, Codable, Sendable, Hashable {
        /// Audio produced by a single running application.
        case application

        /// The combined system audio output.
        case systemAudio
    }

    /// Creates a source describing a running application.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: The application's bundle identifier, used as the
    ///     source's stable identity.
    ///   - displayName: The application name shown to the user.
    /// - Returns: A capture source of kind ``Kind/application``.
    static func application(bundleIdentifier: String, displayName: String) -> CaptureSource {
        CaptureSource(id: bundleIdentifier, displayName: displayName, kind: .application)
    }
}
