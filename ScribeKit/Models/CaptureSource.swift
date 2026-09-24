//
//  CaptureSource.swift
//  ScribeKit
//

import Foundation

/// A selectable origin of meeting audio.
///
/// This is a plain value describing *what* the user picked. It intentionally
/// carries no capture machinery: the capturer for the meeting's
/// ``CaptureMode`` binds it to a real audio stream, and nothing here assumes a
/// particular capture API.
nonisolated struct CaptureSource: Identifiable, Hashable, Codable, Sendable {
    /// Stable identifier used to persist and compare selections.
    ///
    /// For application sources this is the bundle identifier, so a selection
    /// survives an application relaunch. For the microphone it is the input
    /// device's identifier as the system reported it when the meeting was set
    /// up; it is held for the length of one meeting and never persisted.
    let id: String

    /// Name shown to the user, such as an application name.
    let displayName: String

    /// The kind of audio this source represents.
    let kind: Kind

    /// The category of a capture source.
    enum Kind: String, Codable, Sendable, Hashable {
        /// Audio produced by a single running application.
        case application

        /// The combined system audio output.
        case systemAudio

        /// The Mac's current microphone input.
        case microphone
    }

    /// Creates a source describing a running application.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: The application's bundle identifier, used as the
    ///     source's stable identity.
    ///   - displayName: The application name shown to the user.
    /// - Returns: A capture source of kind ``Kind/application``.
    static func application(bundleIdentifier: String, displayName: String) -> CaptureSource {
        CaptureSource(id: bundleIdentifier, displayName: displayName, kind: .application)
    }

    /// Creates a source describing the Mac's current microphone input.
    ///
    /// - Parameter input: The input the system reported as current.
    /// - Returns: A capture source of kind ``Kind/microphone`` identified by the
    ///   input's device identifier, so a capturer can refuse to listen to a
    ///   different microphone than the one the meeting was set up with.
    static func microphone(_ input: MicrophoneInput) -> CaptureSource {
        CaptureSource(id: input.id, displayName: input.name, kind: .microphone)
    }

    /// The name written into a transcript and its session record.
    ///
    /// An application is named as itself. A microphone is named as one, so a
    /// transcript read without ScribeKit still says where its speech came
    /// from rather than listing a device name that could be mistaken for an
    /// application.
    var transcriptName: String {
        switch kind {
        case .application, .systemAudio: displayName
        case .microphone: "Microphone (\(displayName))"
        }
    }
}
