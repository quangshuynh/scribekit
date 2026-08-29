//
//  CaptureSourceCatalog.swift
//  ScribeKit
//

import Foundation

/// Turns raw system discovery results into the source list shown to the user.
///
/// The policy lives apart from any capture framework so it can be tested
/// directly, and so a system provider stays a thin adapter around it.
enum CaptureSourceCatalog {

    /// Maps discovered applications to displayable capture sources.
    ///
    /// Entries are dropped when they cannot be presented honestly or usefully:
    /// an application without a bundle identifier has no stable identity, one
    /// without a name cannot be labelled, one without an ordinary on-screen
    /// window is a helper or background process, and ScribeKit itself is never
    /// offered as a source. Remaining entries are de-duplicated by bundle
    /// identifier — a single application may run several processes — and sorted
    /// so repeated discovery passes produce the same order.
    ///
    /// - Parameters:
    ///   - applications: Applications reported by a system discovery API.
    ///   - excludedBundleIdentifiers: Bundle identifiers never offered as
    ///     sources, normally ScribeKit's own.
    /// - Returns: Display-ready sources, ordered by name.
    static func sources(
        from applications: [DiscoveredApplication],
        excludingBundleIdentifiers excludedBundleIdentifiers: Set<String> = []
    ) -> [CaptureSource] {
        var seenBundleIdentifiers: Set<String> = []
        var sources: [CaptureSource] = []

        for application in applications {
            let bundleIdentifier = application.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = application.applicationName.trimmingCharacters(in: .whitespacesAndNewlines)

            guard application.ownsOnScreenWindow,
                  !bundleIdentifier.isEmpty,
                  !displayName.isEmpty,
                  !excludedBundleIdentifiers.contains(bundleIdentifier),
                  seenBundleIdentifiers.insert(bundleIdentifier).inserted
            else { continue }

            sources.append(.application(bundleIdentifier: bundleIdentifier, displayName: displayName))
        }

        return sources.sorted { lhs, rhs in
            let comparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
            return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
        }
    }
}
