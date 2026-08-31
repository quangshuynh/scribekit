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
    private let access: CaptureAccessProbing

    /// Creates a provider.
    ///
    /// - Parameters:
    ///   - excludedBundleIdentifiers: Bundle identifiers never offered as
    ///     sources. Defaults to ScribeKit's own bundle identifier, so the app
    ///     does not list itself.
    ///   - access: Asked only after a discovery attempt has failed, to say
    ///     whether the failure was a missing permission.
    init(
        excludedBundleIdentifiers: Set<String>? = nil,
        access: CaptureAccessProbing = SystemCaptureAccessProbe()
    ) {
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
            ?? Set([Bundle.main.bundleIdentifier].compactMap { $0 })
        self.access = access
    }

    /// Enumerates shareable applications and maps them to capture sources.
    ///
    /// - Returns: The applications that pass ``CaptureSourceCatalog`` filtering.
    /// The permission prompt belongs here: the first attempt is what makes
    /// macOS ask, and nothing pre-checks in order to avoid asking.
    ///
    /// - Throws: ``CaptureSourceDiscoveryError/accessUnavailable`` when macOS
    ///   does not grant Screen & System Audio Recording, otherwise
    ///   ``CaptureSourceDiscoveryError/systemFailure(_:)``.
    func availableSources() async throws -> [CaptureSource] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: true
            )
        } catch {
            throw Self.discoveryError(from: error, hasAccess: access.hasScreenRecordingAccess())
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
    /// ScreenCaptureKit's own refusal is taken at face value. Any other failure
    /// is checked against what macOS says about the permission, because the
    /// framework does not always report a missing one as a refusal, and telling
    /// the user to read a system error when the real answer is a permission
    /// they can grant is the failure this classification exists to avoid. When
    /// access is granted and discovery still failed, the system's own text is
    /// reported rather than a guess.
    ///
    /// - Parameters:
    ///   - error: The error thrown while requesting shareable content.
    ///   - hasAccess: What macOS reports about Screen & System Audio Recording.
    /// - Returns: The matching discovery error.
    static func discoveryError(from error: Error, hasAccess: Bool) -> CaptureSourceDiscoveryError {
        let error = error as NSError
        if error.domain == SCStreamErrorDomain, error.code == SCStreamError.Code.userDeclined.rawValue {
            return .accessUnavailable
        }
        return hasAccess ? .systemFailure(error.localizedDescription) : .accessUnavailable
    }
}
