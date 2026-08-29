//
//  TranscriptionConfigurationTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@Suite("TranscriptionConfiguration")
struct TranscriptionConfigurationTests {

    @Test("A configuration ships no recognition hints of its own")
    func hasNoBuiltInVocabulary() {
        let configuration = TranscriptionConfiguration(localeIdentifier: "en-US")

        #expect(configuration.contextualStrings.isEmpty)
    }

    @Test("Recognition hints are carried when they are given")
    func carriesHints() {
        let configuration = TranscriptionConfiguration(
            localeIdentifier: "en-US",
            contextualStrings: ["SwiftUI", "Codable"]
        )

        #expect(configuration.contextualStrings == ["SwiftUI", "Codable"])
        #expect(configuration != TranscriptionConfiguration(localeIdentifier: "en-US"))
    }

    @Test("The system locale is read in the form the recogniser uses")
    func readsSystemLocale() {
        let identifier = TranscriptionConfiguration.systemLocaleIdentifier(
            Locale(identifier: "en_GB")
        )

        #expect(identifier == "en-GB")
    }

    @Test("A locale names itself for the interface and remembers its model state")
    func describesLocales() {
        let installed = TranscriptionLocale(id: "en-US", isInstalled: true)
        let missing = TranscriptionLocale(id: "de-DE", isInstalled: false)

        #expect(!installed.displayName.isEmpty)
        #expect(installed.displayName != "en-US" || installed.id == "en-US")
        #expect(installed.isInstalled)
        #expect(!missing.isInstalled)
        #expect(TranscriptionLocale(id: "en-US", displayName: "English", isInstalled: true).displayName == "English")
    }
}
