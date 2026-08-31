//
//  CaptureSourceProviding.swift
//  ScribeKit
//

import Foundation

/// Discovers the applications that can be offered as capture sources.
///
/// The protocol exists so that presentation code depends on discovery as a
/// capability rather than on a specific system framework: the production
/// implementation talks to ScreenCaptureKit, while tests substitute a value
/// returning fixed results.
protocol CaptureSourceProviding: Sendable {
    /// Returns the capture sources currently available on this machine.
    ///
    /// Implementations only enumerate; they never start a capture stream.
    ///
    /// - Returns: The available sources, filtered and ordered for display.
    /// - Throws: ``CaptureSourceDiscoveryError`` when the system refuses or
    ///   fails to report shareable content.
    func availableSources() async throws -> [CaptureSource]
}

/// A reason application discovery could not produce a list of sources.
enum CaptureSourceDiscoveryError: Error, Equatable, Sendable {
    /// macOS does not currently grant the access discovery requires.
    ///
    /// ScribeKit says the access is not available rather than that the user
    /// denied it: a permission that has never been asked for and one that was
    /// refused look the same from here.
    case accessUnavailable

    /// Discovery failed for another reason, described by the system.
    case systemFailure(String)
}

extension CaptureSourceDiscoveryError: LocalizedError {
    /// A message suitable for display in the setup screen.
    var errorDescription: String? {
        switch self {
        case .accessUnavailable:
            "ScribeKit does not have Screen & System Audio Recording access, so it cannot list or record "
            + "this Mac's applications. Grant it in System Settings › Privacy & Security › "
            + "Screen & System Audio Recording, then choose Refresh here."
        case let .systemFailure(description):
            "Applications could not be listed: \(description)"
        }
    }
}
