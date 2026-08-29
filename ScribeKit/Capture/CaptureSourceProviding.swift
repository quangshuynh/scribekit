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
    /// The user has not granted the permission the discovery API requires.
    case permissionDenied

    /// Discovery failed for another reason, described by the system.
    case systemFailure(String)
}

extension CaptureSourceDiscoveryError: LocalizedError {
    /// A message suitable for display in the setup screen.
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "ScribeKit needs Screen Recording permission to list running applications. "
            + "Grant it in System Settings › Privacy & Security › Screen Recording, then refresh."
        case let .systemFailure(description):
            "Applications could not be listed: \(description)"
        }
    }
}
