//
//  AudioCapturing.swift
//  ScribeKit
//

import Foundation

/// Starts and stops capture of audio from selected applications.
///
/// The protocol exists so that session and presentation code depends on
/// capture as a capability rather than on ScreenCaptureKit: the production
/// implementation owns an `SCStream`, while tests substitute a value that
/// records calls and feeds synthetic samples. Implementations own their own
/// lifecycle and are not shared singletons.
nonisolated protocol AudioCapturing: Sendable {

    /// Interruptions reported by the capture system after a successful start.
    ///
    /// The stream stopping on its own — a revoked permission, a system stop —
    /// is an event, not the result of a call, so it is delivered here rather
    /// than thrown. The sequence finishes when the implementation is released.
    var interruptions: AsyncStream<AudioCaptureError> { get }

    /// Begins capturing audio from the configured applications.
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
        }
    }
}
