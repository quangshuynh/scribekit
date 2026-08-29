//
//  ScreenCaptureKitSourceProvider.swift
//  ScribeKit
//

import Foundation
import ScreenCaptureKit

/// Discovers capture sources from the applications ScreenCaptureKit reports as
/// shareable.
///
/// The provider only reads the shareable content list. It creates no
/// `SCStream`, captures no audio or video, and reads no window contents.
/// ScreenCaptureKit types stop here: everything above the provider works with
/// ``CaptureSource`` values.
struct ScreenCaptureKitSourceProvider: CaptureSourceProviding {

    /// Window layer of ordinary application windows; higher layers hold menus,
    /// status items and other transient chrome.
    private static let normalWindowLayer = 0

    private let excludedBundleIdentifiers: Set<String>

    /// Creates a provider.
    ///
    /// - Parameter excludedBundleIdentifiers: Bundle identifiers never offered
    ///   as sources. Defaults to ScribeKit's own bundle identifier, so the app
    ///   does not list itself.
    init(excludedBundleIdentifiers: Set<String>? = nil) {
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
            ?? Set([Bundle.main.bundleIdentifier].compactMap { $0 })
    }

    /// Enumerates shareable applications and maps them to capture sources.
    ///
    /// - Returns: The applications that pass ``CaptureSourceCatalog`` filtering.
    /// - Throws: ``CaptureSourceDiscoveryError/permissionDenied`` when Screen
    ///   Recording permission is missing, otherwise
    ///   ``CaptureSourceDiscoveryError/systemFailure(_:)``.
    func availableSources() async throws -> [CaptureSource] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: true
            )
        } catch {
            throw Self.discoveryError(from: error)
        }

        return CaptureSourceCatalog.sources(
            from: Self.applications(in: content),
            excludingBundleIdentifiers: excludedBundleIdentifiers
        )
    }

    /// Adapts shareable content into framework-independent values.
    ///
    /// - Parameter content: Shareable content reported by ScreenCaptureKit.
    /// - Returns: One value per reported running application.
    private static func applications(in content: SCShareableContent) -> [DiscoveredApplication] {
        let processesOwningWindows = Set(
            content.windows
                .filter { $0.windowLayer == normalWindowLayer }
                .compactMap { $0.owningApplication?.processID }
        )

        return content.applications.map { application in
            DiscoveredApplication(
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.applicationName,
                processIdentifier: application.processID,
                ownsOnScreenWindow: processesOwningWindows.contains(application.processID)
            )
        }
    }

    /// Classifies an error raised by ScreenCaptureKit.
    ///
    /// - Parameter error: The error thrown while requesting shareable content.
    /// - Returns: The matching discovery error.
    private static func discoveryError(from error: Error) -> CaptureSourceDiscoveryError {
        let error = error as NSError
        if error.domain == SCStreamErrorDomain, error.code == SCStreamError.Code.userDeclined.rawValue {
            return .permissionDenied
        }
        return .systemFailure(error.localizedDescription)
    }
}
