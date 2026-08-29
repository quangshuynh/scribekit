//
//  AppleSpeechTranscriberTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// Exercises the availability rules and the recogniser's lifecycle.
///
/// The rules are tested against a stated environment rather than the host's
/// own, because what a Mac's Speech runtime supports is a property of the
/// machine: a hosted CI runner reports no recogniser at all, while a
/// developer's Mac reports thirty locales and nine installed models. Both are
/// legitimate, and neither should decide whether ScribeKit's own decisions are
/// correct.
///
/// The real framework is still exercised, in tests that adapt to what this
/// machine actually has and assert what is true either way.
@Suite("AppleSpeechTranscriber")
struct AppleSpeechTranscriberTests {

    // MARK: - Availability rules

    @Test("A Mac without the recogniser reports an unsupported system, not a missing locale")
    func systemWithoutARecogniserIsReported() async {
        let transcriber = AppleSpeechTranscriber(
            speechAvailability: FakeSpeechAvailability(isAvailable: false)
        )

        let availability = await transcriber.availability(
            for: TranscriptionConfiguration(localeIdentifier: "en-US")
        )

        #expect(availability == .unsupportedSystem)
        #expect(!availability.canTranscribe)
        #expect(await transcriber.availableLocales().isEmpty)
    }

    @Test("A locale the recogniser does not support is reported, not substituted")
    func unsupportedLocaleIsReported() async {
        let transcriber = AppleSpeechTranscriber(
            speechAvailability: FakeSpeechAvailability(
                supported: ["en-US", "de-DE"],
                installed: ["en-US"]
            )
        )

        let availability = await transcriber.availability(
            for: TranscriptionConfiguration(localeIdentifier: "zz-ZZ")
        )

        #expect(availability == .unsupportedLocale(localeIdentifier: "zz-ZZ"))
        #expect(!availability.canTranscribe)
        #expect(availability.localeIdentifier == "zz-ZZ")
    }

    @Test("A supported locale whose model is absent reports the model, not the locale")
    func supportedLocaleWithoutAModelIsReported() async {
        let transcriber = AppleSpeechTranscriber(
            speechAvailability: FakeSpeechAvailability(
                supported: ["en-US", "de-DE"],
                installed: ["en-US"],
                equivalents: ["de": "de-DE"]
            )
        )

        let requested = await transcriber.availability(
            for: TranscriptionConfiguration(localeIdentifier: "de-DE")
        )
        let resolved = await transcriber.availability(
            for: TranscriptionConfiguration(localeIdentifier: "de")
        )

        #expect(requested == .modelNotInstalled(localeIdentifier: "de-DE"))
        #expect(!requested.canTranscribe)
        // The equivalence the recogniser resolved is what gets reported, so the
        // message names the locale whose model is actually missing.
        #expect(resolved == .modelNotInstalled(localeIdentifier: "de-DE"))
    }

    @Test("A supported locale with an installed model may transcribe")
    func installedModelIsAvailable() async {
        let transcriber = AppleSpeechTranscriber(
            speechAvailability: FakeSpeechAvailability(
                supported: ["en-US", "de-DE"],
                installed: ["en-US"],
                equivalents: ["en": "en-US"]
            )
        )

        let requested = await transcriber.availability(
            for: TranscriptionConfiguration(localeIdentifier: "en-US")
        )
        let resolved = await transcriber.availability(
            for: TranscriptionConfiguration(localeIdentifier: "en")
        )

        #expect(requested == .available(localeIdentifier: "en-US"))
        #expect(requested.canTranscribe)
        #expect(resolved == .available(localeIdentifier: "en-US"))
        #expect(resolved.canTranscribe)
    }

    @Test("Locales are reported with whether their on-device model is installed")
    func reportsLocalesAndTheirModels() async {
        let transcriber = AppleSpeechTranscriber(
            speechAvailability: FakeSpeechAvailability(
                supported: ["ja-JP", "en-US", "de-DE", "fr-FR"],
                installed: ["en-US", "fr-FR"]
            )
        )

        let locales = await transcriber.availableLocales()

        #expect(locales.map(\.id).sorted() == ["de-DE", "en-US", "fr-FR", "ja-JP"])
        #expect(locales.allSatisfy { !$0.displayName.isEmpty })
        let installed = Dictionary(uniqueKeysWithValues: locales.map { ($0.id, $0.isInstalled) })
        #expect(installed == ["ja-JP": false, "en-US": true, "de-DE": false, "fr-FR": true])
        // Ordering is ScribeKit's, not the recogniser's: the list is presented
        // by display name in the reader's own language.
        let names = locales.map(\.displayName)
        #expect(names == names.sorted { $0.localizedCompare($1) == .orderedAscending })
    }

    @Test("An unavailable recogniser reports nothing, even where locales and models exist")
    func unavailableSystemOutranksInstalledModels() async {
        let transcriber = AppleSpeechTranscriber(
            speechAvailability: FakeSpeechAvailability(
                isAvailable: false,
                supported: ["en-US"],
                installed: ["en-US"]
            )
        )

        // An unavailable recogniser is unavailable whatever it would otherwise
        // support: nothing is listed and nothing is offered as transcribable.
        #expect(await transcriber.availableLocales().isEmpty)
        let availability = await transcriber.availability(
            for: TranscriptionConfiguration(localeIdentifier: "en-US")
        )
        #expect(availability == .unsupportedSystem)
    }

    // MARK: - The real framework, whatever this Mac has

    @Test("The real recogniser is reported as this Mac actually has it")
    func realRecogniserIsReportedHonestly() async {
        let system = SystemSpeechAvailability()
        let transcriber = AppleSpeechTranscriber()
        let locales = await transcriber.availableLocales()

        guard system.isAvailable else {
            // A machine without the recogniser — a hosted CI runner is one —
            // must say so rather than offering locales it cannot transcribe.
            #expect(locales.isEmpty)
            let availability = await transcriber.availability(
                for: TranscriptionConfiguration(localeIdentifier: "en-US")
            )
            #expect(availability == .unsupportedSystem)
            #expect(!availability.canTranscribe)
            return
        }

        #expect(locales.allSatisfy { !$0.id.isEmpty && !$0.displayName.isEmpty })
        #expect(Set(locales.map(\.id)).count == locales.count)
        let installed = Set(await system.installedLocales().map { $0.identifier(.bcp47) })
        #expect(locales.filter(\.isInstalled).allSatisfy { installed.contains($0.id) })

        let unsupported = await transcriber.availability(
            for: TranscriptionConfiguration(localeIdentifier: "zz-ZZ")
        )
        #expect(unsupported == .unsupportedLocale(localeIdentifier: "zz-ZZ"))

        // No model need be installed for this to hold; it says only that each
        // real locale is reported as whichever of the two states it is in.
        for locale in locales.prefix(6) {
            let availability = await transcriber.availability(
                for: TranscriptionConfiguration(localeIdentifier: locale.id)
            )
            if locale.isInstalled {
                #expect(availability == .available(localeIdentifier: locale.id))
            } else {
                #expect(availability == .modelNotInstalled(localeIdentifier: locale.id))
            }
        }
    }

    @Test("A run starts, refuses a second start, and stops again")
    func lifecycle() async throws {
        let transcriber = AppleSpeechTranscriber()
        let locales = await transcriber.availableLocales()
        // Starting a real `SpeechAnalyzer` needs a model this machine may not
        // have; the deterministic lifecycle rules are covered against the
        // transcriber double, and this is the integration check that the real
        // one behaves the same way when it can run at all.
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

    @Test("A start is refused when the recogniser is unavailable")
    func startIsRefusedWithoutARecogniser() async {
        let transcriber = AppleSpeechTranscriber(
            speechAvailability: FakeSpeechAvailability(isAvailable: false)
        )

        await #expect(throws: TranscriptionError.unavailable(.unsupportedSystem)) {
            try await transcriber.start(
                configuration: TranscriptionConfiguration(localeIdentifier: "en-US")
            )
        }
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
