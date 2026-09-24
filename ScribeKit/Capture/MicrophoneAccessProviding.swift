//
//  MicrophoneAccessProviding.swift
//  ScribeKit
//

import AVFoundation
import CoreAudio
import Foundation

/// Answers the questions about the microphone that only macOS can answer:
/// whether ScribeKit may use it, and which input is current.
///
/// The protocol exists so those answers can be stated in a test, and so the
/// one place that asks the system is a value rather than calls scattered
/// through capture and the setup screen. Reading is never prompting:
/// ``authorization()`` and ``currentInput()`` ask nothing of the user, and the
/// only call that can put a permission prompt on screen is
/// ``requestAccess()``, which is made when a Microphone meeting starts or the
/// user asks for it — never because a screen appeared, and never for an App
/// Audio meeting.
nonisolated protocol MicrophoneAccessProviding: Sendable {
    /// What macOS reports about microphone access right now.
    func authorization() -> MicrophoneAuthorization

    /// Asks macOS for microphone access, which shows its prompt when ScribeKit
    /// has never asked before and returns the standing answer otherwise.
    ///
    /// - Returns: Whether access is granted.
    func requestAccess() async -> Bool

    /// The Mac's current sound input, or `nil` when it has none.
    func currentInput() -> MicrophoneInput?
}

/// Decides whether a Microphone meeting may listen, asking macOS when it has
/// to.
///
/// Kept apart from the capturer so the decision — which answers mean a prompt,
/// which mean a refusal, and what each refusal is called — is tested without a
/// microphone, a permission dialog or an audio engine.
nonisolated enum MicrophoneAccessGate {

    /// Returns once ScribeKit may use the microphone, asking macOS first when
    /// it never has.
    ///
    /// - Parameters:
    ///   - access: The system's answers.
    ///   - mayPrompt: Whether an undetermined permission may be asked for now.
    ///     A start may prompt; anything that runs without the user having just
    ///     asked for a meeting may not.
    /// - Throws: ``AudioCaptureError/microphoneAccessDenied`` when the user
    ///   refused or turned access off, or when asking was not allowed;
    ///   ``AudioCaptureError/microphoneAccessRestricted`` when it cannot be
    ///   granted on this Mac.
    static func ensureAccess(_ access: any MicrophoneAccessProviding, mayPrompt: Bool) async throws {
        switch access.authorization() {
        case .authorized:
            return
        case .notDetermined:
            guard mayPrompt, await access.requestAccess() else {
                throw AudioCaptureError.microphoneAccessDenied
            }
        case .denied:
            throw AudioCaptureError.microphoneAccessDenied
        case .restricted:
            throw AudioCaptureError.microphoneAccessRestricted
        }
    }

    /// Returns the current input when it is the one a meeting was set up with.
    ///
    /// - Parameters:
    ///   - access: The system's answers.
    ///   - expected: Identifiers of the input the meeting was set up with.
    /// - Returns: The current input.
    /// - Throws: ``AudioCaptureError/microphoneUnavailable`` when the Mac has
    ///   no input, or ``AudioCaptureError/microphoneInputChanged`` when the
    ///   current input is a different device. ScribeKit does not follow the
    ///   system to another microphone on its own.
    static func expectedInput(
        _ access: any MicrophoneAccessProviding,
        matching expected: Set<CaptureSource.ID>
    ) throws -> MicrophoneInput {
        guard let input = access.currentInput() else { throw AudioCaptureError.microphoneUnavailable }
        guard expected.contains(input.id) else { throw AudioCaptureError.microphoneInputChanged }
        return input
    }
}

/// The answers macOS gives for this process.
///
/// Authorization is read from `AVCaptureDevice`, which reports the same
/// Privacy & Security › Microphone setting every audio-input API on the Mac is
/// governed by, and which — unlike the record-permission API — distinguishes a
/// restricted Mac from a refusal. The current input is read from Core Audio,
/// because it is Core Audio's default input device that `AVAudioEngine`'s input
/// node listens to; reading it asks for no permission.
nonisolated struct SystemMicrophoneAccess: MicrophoneAccessProviding {

    /// Creates the system's answers.
    init() {}

    func authorization() -> MicrophoneAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default:
            // An answer this build does not know is not turned into one it
            // does. Undetermined means a start asks macOS, and macOS's reply
            // to that request is authoritative.
            .notDetermined
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func currentInput() -> MicrophoneInput? {
        guard let device = Self.defaultInputDevice(),
              let identifier = Self.string(kAudioDevicePropertyDeviceUID, of: device)
        else { return nil }
        let name = Self.string(kAudioObjectPropertyName, of: device) ?? "Microphone"
        return MicrophoneInput(id: identifier, name: name)
    }

    /// The system's default input device, when there is one.
    private static func defaultInputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return device
    }

    /// Reads one string property of an audio device.
    ///
    /// - Parameters:
    ///   - selector: The property to read.
    ///   - device: The device to read it from.
    /// - Returns: The value, or `nil` when the device did not supply one.
    private static func string(_ selector: AudioObjectPropertySelector, of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        let string = value.takeRetainedValue() as String
        return string.isEmpty ? nil : string
    }
}
