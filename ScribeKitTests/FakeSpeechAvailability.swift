//
//  FakeSpeechAvailability.swift
//  ScribeKitTests
//

import Foundation
@testable import ScribeKit

/// A stated set of answers about what a Mac's recogniser supports, so the
/// availability rules can be tested without the host's Speech runtime.
///
/// Every question ``SpeechAvailabilityProviding`` asks is answered from these
/// values, including the equivalence step: `supportedLocale(equivalentTo:)`
/// returns an exact match when the identifier is supported, otherwise the
/// stated equivalent, otherwise nothing — which is how the real recogniser
/// resolves a request such as `en` to a locale it actually has.
nonisolated struct FakeSpeechAvailability: SpeechAvailabilityProviding {

    let isAvailable: Bool

    /// BCP-47 identifiers the recogniser supports.
    let supported: [String]

    /// BCP-47 identifiers whose on-device model is installed.
    let installed: [String]

    /// Requested identifiers the recogniser resolves to a supported one.
    let equivalents: [String: String]

    /// Creates a stated environment.
    ///
    /// - Parameters:
    ///   - isAvailable: Whether the recogniser exists on this Mac at all.
    ///   - supported: Identifiers the recogniser supports.
    ///   - installed: Identifiers whose model is installed.
    ///   - equivalents: Requested identifiers mapped to supported ones.
    init(
        isAvailable: Bool = true,
        supported: [String] = [],
        installed: [String] = [],
        equivalents: [String: String] = [:]
    ) {
        self.isAvailable = isAvailable
        self.supported = supported
        self.installed = installed
        self.equivalents = equivalents
    }

    func supportedLocales() async -> [Locale] {
        supported.map { Locale(identifier: $0) }
    }

    func installedLocales() async -> [Locale] {
        installed.map { Locale(identifier: $0) }
    }

    func supportedLocale(equivalentTo locale: Locale) async -> Locale? {
        let requested = locale.identifier(.bcp47)
        if supported.contains(requested) { return Locale(identifier: requested) }
        guard let equivalent = equivalents[requested], supported.contains(equivalent) else { return nil }
        return Locale(identifier: equivalent)
    }
}
