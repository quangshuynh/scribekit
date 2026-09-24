//
//  MicrophoneAccess.swift
//  ScribeKit
//

import Foundation

/// What macOS says about ScribeKit's access to the microphone.
///
/// The cases are the operating system's own and nothing more: ScribeKit does
/// not keep a permission state of its own beside the one macOS holds, so there
/// is nothing here that could disagree with System Settings. Each answer is a
/// fact about the moment it was read.
nonisolated enum MicrophoneAuthorization: Equatable, Sendable {
    /// ScribeKit has never asked. macOS asks the user the first time a
    /// Microphone meeting starts.
    case notDetermined

    /// The user allowed ScribeKit to use the microphone.
    case authorized

    /// The user refused, or later turned access off. Only System Settings can
    /// change this; macOS will not ask again.
    case denied

    /// Access is restricted on this Mac, for example by a device-management
    /// profile, and neither ScribeKit nor the user can grant it from here.
    case restricted
}

/// A microphone input the system offered as its current one.
nonisolated struct MicrophoneInput: Equatable, Sendable {
    /// The device's identifier as the system reported it.
    ///
    /// Used for one comparison — is the current input still the one this
    /// meeting started with? — and never written anywhere. Device identifiers
    /// are the system's to assign, and ScribeKit does not remember a
    /// microphone between launches.
    let id: String

    /// The device's name, as System Settings shows it.
    let name: String
}

/// What the setup screen knows about listening to the microphone.
nonisolated enum MicrophoneReadiness: Equatable, Sendable {
    /// Nothing has been read yet.
    case notChecked

    /// What macOS reported when it was last asked.
    ///
    /// - Parameters:
    ///   - authorization: Whether ScribeKit may use the microphone.
    ///   - input: The Mac's current sound input, or `nil` when it has none.
    case checked(authorization: MicrophoneAuthorization, input: MicrophoneInput?)
}
