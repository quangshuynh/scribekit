//
//  TranscriptionConfiguration.swift
//  ScribeKit
//

import Foundation

/// A locale the recogniser can work in.
///
/// The value is ScribeKit's own, so the locale list, its ordering and the
/// distinction between "supported" and "installed on this Mac" can be shown
/// and tested without the speech framework.
nonisolated struct TranscriptionLocale: Identifiable, Hashable, Sendable {
    /// The BCP-47 identifier, which is also the identity.
    let id: String

    /// The locale's name in the user's own language.
    let displayName: String

    /// Whether the on-device model for this locale is installed.
    ///
    /// Only installed locales can be transcribed, because ScribeKit never
    /// falls back to network recognition and never downloads a model on its
    /// own.
    let isInstalled: Bool

    /// Creates a locale entry.
    ///
    /// - Parameters:
    ///   - id: The BCP-47 identifier.
    ///   - displayName: A name for the interface. Derived from the identifier
    ///     in the user's current locale when omitted.
    ///   - isInstalled: Whether the on-device model is present.
    init(id: String, displayName: String? = nil, isInstalled: Bool) {
        self.id = id
        self.displayName = displayName
            ?? Locale.current.localizedString(forIdentifier: id)
            ?? id
        self.isInstalled = isInstalled
    }
}

/// What a transcriber needs in order to start.
///
/// The locale is explicit rather than inferred at the point of use: a meeting
/// transcript that quietly changed language would be worse than one that
/// refused to start.
nonisolated struct TranscriptionConfiguration: Equatable, Sendable {

    /// The BCP-47 identifier of the language to recognise.
    let localeIdentifier: String

    /// Words and names to weight the recogniser towards.
    ///
    /// The speech framework accepts contextual strings as a hint; they change
    /// what the recogniser is more likely to hear, and nothing is substituted
    /// afterwards. ScribeKit ships none, so the default recognition is the
    /// recogniser's own. The field exists so a technical vocabulary can be
    /// added later as configuration rather than as post-processing.
    let contextualStrings: [String]

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - localeIdentifier: The BCP-47 language to recognise in.
    ///   - contextualStrings: Optional recognition hints.
    init(localeIdentifier: String, contextualStrings: [String] = []) {
        self.localeIdentifier = localeIdentifier
        self.contextualStrings = contextualStrings
    }

    /// The identifier of the system locale, in the form the recogniser uses.
    ///
    /// - Parameter locale: The locale to read. The current one by default.
    /// - Returns: A BCP-47 identifier.
    static func systemLocaleIdentifier(_ locale: Locale = .current) -> String {
        locale.identifier(.bcp47)
    }
}
