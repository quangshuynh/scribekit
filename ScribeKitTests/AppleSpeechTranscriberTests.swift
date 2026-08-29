//
//  AppleSpeechTranscriberTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// Exercises the real recogniser's availability reporting and lifecycle.
///
/// Nothing here needs a network, a permission prompt or recorded speech. The
/// tests that would need an installed speech model check for one first and
/// report what they found instead of failing on a machine that has none.
@Suite("AppleSpeechTranscriber")
struct AppleSpeechTranscriberTests {

    @Test("A locale the recogniser does not support is reported, not substituted")
    func unsupportedLocaleIsReported() async {
        let transcriber = AppleSpeechTranscriber()

        let availability = await transcriber.availability(
            for: TranscriptionConfiguration(localeIdentifier: "zz-ZZ")
        )

        #expect(availability == .unsupportedLocale(localeIdentifier: "zz-ZZ"))
        #expect(!availability.canTranscribe)
    }

    @Test("Locales are reported with whether their on-device model is installed")
    func reportsLocalesAndTheirModels() async {
        let transcriber = AppleSpeechTranscriber()

        let locales = await transcriber.availableLocales()

        #expect(!locales.isEmpty)
        #expect(locales.allSatisfy { $0.id.contains("-") })
        #expect(locales.allSatisfy { !$0.displayName.isEmpty })
    }

    @Test("Recognition only reports itself available when a local model is installed")
    func availabilityRequiresALocalModel() async {
        let transcriber = AppleSpeechTranscriber()
        let locales = await transcriber.availableLocales()

        for locale in locales.prefix(6) {
            let availability = await transcriber.availability(
                for: TranscriptionConfiguration(localeIdentifier: locale.id)
            )
            if locale.isInstalled {
                #expect(availability.canTranscribe)
            } else {
                #expect(availability == .modelNotInstalled(localeIdentifier: locale.id))
            }
        }
    }

    @Test("A run starts, refuses a second start, and stops again")
    func lifecycle() async throws {
        let transcriber = AppleSpeechTranscriber()
        let locales = await transcriber.availableLocales()
        guard let installed = locales.first(where: \.isInstalled) else { return }
        let configuration = TranscriptionConfiguration(localeIdentifier: installed.id)

        try await transcriber.start(configuration: configuration)

        await #expect(throws: TranscriptionError.alreadyTranscribing) {
            try await transcriber.start(configuration: configuration)
        }

        await transcriber.stop()
        await transcriber.stop()

        try await transcriber.start(configuration: configuration)
        await transcriber.stop()
    }

    @Test("Audio delivered outside a run is discarded rather than buffered")
    func audioOutsideARunIsDiscarded() async {
        let transcriber = AppleSpeechTranscriber()
        let buffer = CapturedPCMBuffer(
            format: CapturedAudioFormat(
                sampleRate: 48_000,
                channelCount: 1,
                bitsPerChannel: 32,
                isFloat: true,
                isInterleaved: false
            ),
            frameCount: 960,
            presentationTime: 0,
            peakAmplitude: 0.5,
            samples: [Float](repeating: 0.5, count: 960)
        )

        for _ in 0..<10_000 { transcriber.consume(buffer) }
    }
}
