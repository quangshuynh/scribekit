//
//  SpeechRecognitionAvailabilityTests.swift
//  ScribeKitTests
//

import Testing
@testable import ScribeKit

@Suite("SpeechRecognitionAvailability")
struct SpeechRecognitionAvailabilityTests {

    @Test("Only an installed local model allows transcription")
    func onlyAvailableTranscribes() {
        #expect(SpeechRecognitionAvailability.available(localeIdentifier: "en-US").canTranscribe)
        #expect(!SpeechRecognitionAvailability.unknown.canTranscribe)
        #expect(!SpeechRecognitionAvailability.unsupportedSystem.canTranscribe)
        #expect(!SpeechRecognitionAvailability.unsupportedLocale(localeIdentifier: "cy-GB").canTranscribe)
        #expect(!SpeechRecognitionAvailability.modelNotInstalled(localeIdentifier: "de-DE").canTranscribe)
        #expect(!SpeechRecognitionAvailability.failed(message: "boom").canTranscribe)
    }

    @Test("A locale-specific outcome reports which locale it is about")
    func reportsLocale() {
        #expect(SpeechRecognitionAvailability.available(localeIdentifier: "en-GB").localeIdentifier == "en-GB")
        #expect(SpeechRecognitionAvailability.modelNotInstalled(localeIdentifier: "de-DE").localeIdentifier == "de-DE")
        #expect(SpeechRecognitionAvailability.unsupportedLocale(localeIdentifier: "cy-GB").localeIdentifier == "cy-GB")
        #expect(SpeechRecognitionAvailability.unsupportedSystem.localeIdentifier == nil)
    }

    @Test("Only a ready recogniser has nothing to explain")
    func explainsEverythingButSuccess() {
        #expect(SpeechRecognitionAvailability.available(localeIdentifier: "en-US").message == nil)
        #expect(SpeechRecognitionAvailability.unknown.message != nil)
        #expect(SpeechRecognitionAvailability.unsupportedSystem.message != nil)
        #expect(SpeechRecognitionAvailability.failed(message: "boom").message?.contains("boom") == true)
    }

    @Test("A missing model says it will not be downloaded and audio will not leave the Mac")
    func missingModelIsExplicitAboutTheLimit() throws {
        let message = try #require(
            SpeechRecognitionAvailability.modelNotInstalled(localeIdentifier: "de-DE").message
        )

        #expect(message.contains("de-DE"))
        #expect(message.contains("will not download"))
        #expect(message.contains("network"))
    }
}
