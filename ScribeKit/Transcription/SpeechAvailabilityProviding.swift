//
//  SpeechAvailabilityProviding.swift
//  ScribeKit
//

import Foundation
import Speech

/// Reports what the on-device speech recogniser can do on this machine.
///
/// The protocol exists because availability is a property of the host, not of
/// ScribeKit: whether the recogniser exists at all, which locales it supports
/// and which models are installed differ between a developer's Mac and a
/// hosted continuous-integration runner. Keeping those four questions behind
/// one seam lets ``AppleSpeechTranscriber``'s rules — unsupported system,
/// unsupported locale, uninstalled model, ready to transcribe — be tested for
/// what they decide rather than for what the machine underneath happens to
/// have installed.
///
/// It is not a general abstraction over the Speech framework. Recognition
/// itself still belongs to ``AppleSpeechTranscriber``; only these questions
/// are asked through here.
nonisolated protocol SpeechAvailabilityProviding: Sendable {

    /// Whether this Mac can run the on-device recogniser at all.
    var isAvailable: Bool { get }

    /// The locales the recogniser can transcribe.
    ///
    /// - Returns: Every supported locale, in the recogniser's own order.
    func supportedLocales() async -> [Locale]

    /// The locales whose on-device model is present on this Mac.
    ///
    /// - Returns: Every installed locale. This is the gate on transcription:
    ///   ScribeKit will not download a model to enlarge it.
    func installedLocales() async -> [Locale]

    /// Resolves a requested locale to the one the recogniser would use.
    ///
    /// - Parameter locale: The locale the user asked for.
    /// - Returns: The supported locale equivalent to it, or `nil` when the
    ///   recogniser supports nothing equivalent.
    func supportedLocale(equivalentTo locale: Locale) async -> Locale?
}

/// The answers Apple's `SpeechTranscriber` gives for this Mac.
///
/// This is the only type that asks the Speech framework about availability, so
/// the framework's environment-dependent answers enter ScribeKit in one place.
/// It holds no state and makes no decisions: every rule built on these answers
/// lives in ``AppleSpeechTranscriber``.
nonisolated struct SystemSpeechAvailability: SpeechAvailabilityProviding {

    var isAvailable: Bool { SpeechTranscriber.isAvailable }

    func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales
    }

    func installedLocales() async -> [Locale] {
        await SpeechTranscriber.installedLocales
    }

    func supportedLocale(equivalentTo locale: Locale) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    }
}
