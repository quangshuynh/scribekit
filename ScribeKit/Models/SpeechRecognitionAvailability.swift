//
//  SpeechRecognitionAvailability.swift
//  ScribeKit
//

import Foundation

/// Whether local speech recognition can run for a chosen locale.
///
/// The cases mirror distinctions the speech framework actually makes, so the
/// interface can explain a refusal instead of showing a generic failure.
/// There is deliberately no "permission required" case: ScribeKit's recogniser
/// runs entirely on the device against locally installed models and the system
/// asks for no privacy authorisation to use it.
nonisolated enum SpeechRecognitionAvailability: Equatable, Sendable {
    /// Availability has not been determined yet.
    case unknown

    /// Recognition can start, using the locally installed model for this
    /// BCP-47 locale.
    case available(localeIdentifier: String)

    /// The recogniser does not support this locale at all.
    case unsupportedLocale(localeIdentifier: String)

    /// The locale is supported, but its model is not installed on this Mac.
    ///
    /// ScribeKit reports this instead of downloading anything: a speech model
    /// is a large download, and starting one without being asked is neither
    /// battery-conscious nor honest.
    case modelNotInstalled(localeIdentifier: String)

    /// This Mac cannot run the recogniser at all.
    case unsupportedSystem

    /// Availability could not be determined; the message explains why.
    case failed(message: String)

    /// Whether recognition may be started.
    var canTranscribe: Bool {
        if case .available = self { return true }
        return false
    }

    /// The locale recognition would use, when one was resolved.
    var localeIdentifier: String? {
        switch self {
        case let .available(identifier), let .modelNotInstalled(identifier),
             let .unsupportedLocale(identifier):
            identifier
        case .unknown, .unsupportedSystem, .failed:
            nil
        }
    }

    /// An explanation for the interface, or `nil` when recognition is ready.
    var message: String? {
        switch self {
        case .unknown:
            "Checking whether speech recognition is available…"
        case .available:
            nil
        case let .unsupportedLocale(identifier):
            "On-device speech recognition does not support \(identifier)."
        case let .modelNotInstalled(identifier):
            "The on-device speech model for \(identifier) is not installed on this Mac. "
            + "Install it in System Settings, then check again. "
            + "ScribeKit will not download it for you and will not transcribe over the network."
        case .unsupportedSystem:
            "This Mac cannot run on-device speech recognition."
        case let .failed(message):
            "Speech recognition is unavailable: \(message)"
        }
    }
}
