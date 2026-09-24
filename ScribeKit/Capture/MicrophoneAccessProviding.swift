//
//  MicrophoneAccessProviding.swift
//  ScribeKit
//

import AVFoundation
import CoreAudio
import Foundation

/// Answers the questions about the microphone that only macOS can answer:
/// whether ScribeKit may use it, and which inputs the Mac offers.
///
/// The protocol exists so those answers can be stated in a test, and so the
/// one place that asks the system is a value rather than calls scattered
/// through capture and the setup screen. Reading is never prompting:
/// ``authorization()``, ``inputs()`` and ``inputChanges()`` ask nothing of the
/// user, and the only call that can put a permission prompt on screen is
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

    /// The Mac's usable sound inputs and which of them is the default.
    func inputs() -> MicrophoneInputCatalog

    /// Yields each time an input is connected or disconnected, or the Mac's
    /// default input changes, until the consumer stops iterating.
    ///
    /// Event-driven, so a setup screen can keep its list of inputs current
    /// without polling. What changed is read again with ``inputs()``.
    func inputChanges() -> AsyncStream<Void>
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

    /// Returns the input a meeting was set up with, when it is connected.
    ///
    /// The meeting's input is fixed when it starts — System Default is
    /// resolved to a device then — so what is checked here is that device,
    /// not whichever input the Mac's default has become since. A default that
    /// moved to another microphone neither refuses a resume nor switches it.
    ///
    /// - Parameters:
    ///   - access: The system's answers.
    ///   - expected: The UID of the input the meeting was set up with.
    /// - Returns: The input.
    /// - Throws: ``AudioCaptureError/microphoneUnavailable`` when the Mac has
    ///   no input at all, or ``AudioCaptureError/microphoneDisconnected`` when
    ///   the meeting's input is not among the ones it has. ScribeKit does not
    ///   listen to another microphone in its place.
    static func expectedInput(
        _ access: any MicrophoneAccessProviding,
        matching expected: Set<CaptureSource.ID>
    ) throws -> MicrophoneInput {
        let catalog = access.inputs()
        if let input = catalog.devices.first(where: { expected.contains($0.id) }) { return input }
        throw catalog.devices.isEmpty ? AudioCaptureError.microphoneUnavailable : .microphoneDisconnected
    }
}

/// The answers macOS gives for this process.
///
/// Authorization is read from `AVCaptureDevice`, which reports the same
/// Privacy & Security › Microphone setting every audio-input API on the Mac is
/// governed by, and which — unlike the record-permission API — distinguishes a
/// restricted Mac from a refusal. The inputs are read from Core Audio, because
/// Core Audio's device is what a meeting's audio unit is bound to; reading
/// them asks for no permission.
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

    func inputs() -> MicrophoneInputCatalog {
        CoreAudioInputDevices.catalog()
    }

    func inputChanges() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let queue = DispatchQueue(label: "com.scribekit.microphone.inputs")
            let listeners = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice]
                .compactMap { selector in
                    CoreAudioPropertyListener.listen(to: selector, on: queue) { continuation.yield() }
                }
            continuation.onTermination = { _ in
                for listener in listeners { listener.cancel() }
            }
        }
    }
}
