//
//  AudioCapturing.swift
//  ScribeKit
//

import Foundation

/// Starts and stops capture of a meeting's audio.
///
/// The protocol exists so that session and presentation code depends on
/// capture as a capability rather than on a framework: one production
/// implementation owns an `SCStream` for application audio, another an
/// `AVAudioEngine` for the microphone, while tests substitute a value that
/// records calls and feeds synthetic samples. Whatever the source, audio
/// leaves an implementation as ``CapturedPCMBuffer`` values delivered to an
/// ``AudioSampleConsuming`` on the implementation's own queue, and a stream
/// that ends by itself is reported through ``interruptions``. Implementations
/// own their own lifecycle and are not shared singletons.
nonisolated protocol AudioCapturing: Sendable {

    /// Interruptions reported by the capture system after a successful start.
    ///
    /// The stream stopping on its own — a revoked permission, a system stop —
    /// is an event, not the result of a call, so it is delivered here rather
    /// than thrown. The sequence finishes when the implementation is released.
    var interruptions: AsyncStream<AudioCaptureError> { get }

    /// Checks, before anything about a meeting has been created, that capture
    /// could start.
    ///
    /// This is where a capture source asks for what it needs from the user —
    /// the microphone's permission prompt is shown here, while nothing is on
    /// disk yet — so a refusal leaves no half-made meeting behind. It captures
    /// nothing. The default does nothing, because application capture's
    /// permission flow belongs to discovery and has already run by the time a
    /// meeting can be started.
    ///
    /// - Parameter configuration: What would be captured.
    /// - Throws: ``AudioCaptureError`` describing why capture could not start.
    func prepare(configuration: AudioCaptureConfiguration) async throws

    /// Begins capturing audio from the configured source.
    ///
    /// The call returns once the capture system has accepted the stream, so a
    /// caller that returns without an error is genuinely capturing.
    ///
    /// - Parameter configuration: The applications and audio format to capture.
    /// - Throws: ``AudioCaptureError``. Starting while already capturing throws
    ///   ``AudioCaptureError/alreadyCapturing`` rather than silently restarting
    ///   or ignoring the request.
    func start(configuration: AudioCaptureConfiguration) async throws

    /// Ends capture and releases the capture system's resources.
    ///
    /// Stopping when nothing is running is not an error, so teardown paths can
    /// call it unconditionally.
    func stop() async
}

nonisolated extension AudioCapturing {
    /// Accepts every configuration: there is nothing to check ahead of a start.
    func prepare(configuration: AudioCaptureConfiguration) async throws {}
}

/// A reason capture could not start, or could not continue.
nonisolated enum AudioCaptureError: Error, Equatable, Sendable {
    /// No application was selected, so there is nothing to capture.
    case noSourcesSelected

    /// Selected applications, by bundle identifier, that are not running now.
    ///
    /// Capture refuses rather than quietly recording the remaining selection,
    /// so the audio ScribeKit captures is always the audio that was chosen.
    case sourcesUnavailable([String])

    /// The system withheld the permission capture needs.
    case permissionDenied

    /// The capture system reported no display to build a filter against.
    case noCaptureDisplay

    /// A start was requested while capture was already running.
    case alreadyCapturing

    /// Starting failed for a reason the system described.
    case systemFailure(String)

    /// A running stream stopped on its own, for the described reason.
    case interrupted(String)

    /// A meeting was asked to capture application audio and the microphone
    /// together. A meeting has one capture mode.
    case mixedCaptureModes

    /// A Microphone meeting was asked to keep its audio. Microphone meetings
    /// write a transcript and never a recording.
    case microphoneAudioNotRetained

    /// The user refused microphone access, or turned it off in System
    /// Settings.
    case microphoneAccessDenied

    /// Microphone access is restricted on this Mac and cannot be granted from
    /// ScribeKit.
    case microphoneAccessRestricted

    /// The Mac has no microphone input to listen to.
    case microphoneUnavailable

    /// The microphone the meeting uses is not connected, and ScribeKit does
    /// not listen to another one in its place.
    case microphoneDisconnected

    /// The audio input is not listening to the microphone the meeting was set
    /// up with, and ScribeKit does not switch microphones on its own.
    case microphoneInputChanged
}

extension AudioCaptureError: LocalizedError {
    /// A message suitable for display in the setup screen.
    var errorDescription: String? {
        switch self {
        case .noSourcesSelected:
            "Select at least one application before starting capture."
        case let .sourcesUnavailable(identifiers):
            "These applications are no longer running: "
            + identifiers.formatted(.list(type: .and))
        case .permissionDenied:
            "ScribeKit needs Screen & System Audio Recording permission to capture application audio. "
            + "Grant it in System Settings › Privacy & Security › Screen & System Audio Recording, then try again."
        case .noCaptureDisplay:
            "No display was available to capture from."
        case .alreadyCapturing:
            "Capture is already running."
        case let .systemFailure(description):
            "Capture could not start: \(description)"
        case let .interrupted(description):
            "Capture stopped: \(description)"
        case .mixedCaptureModes:
            "A meeting captures either application audio or the microphone, not both."
        case .microphoneAudioNotRetained:
            "Microphone meetings keep no audio. Only the transcript is written."
        case .microphoneAccessDenied:
            "ScribeKit does not have access to the microphone. Turn it on in System Settings › "
            + "Privacy & Security › Microphone, then try again."
        case .microphoneAccessRestricted:
            "Microphone access is restricted on this Mac, for example by a device-management profile, "
            + "and ScribeKit cannot ask for it."
        case .microphoneUnavailable:
            "This Mac has no microphone input. Connect one, then try again."
        case .microphoneDisconnected:
            "The microphone this meeting uses is not connected. ScribeKit does not switch to another "
            + "microphone on its own: reconnect it, or stop and start a meeting with another input."
        case .microphoneInputChanged:
            "The audio input is no longer listening to the microphone this meeting uses. ScribeKit does not "
            + "switch microphones on its own, so it stopped listening."
        }
    }
}
