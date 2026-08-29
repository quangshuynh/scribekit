//
//  SpeechTranscribing.swift
//  ScribeKit
//

import Foundation

/// Turns captured audio into transcription events.
///
/// The protocol exists so that state owners and views depend on recognition as
/// a capability rather than on Apple's Speech framework: the production
/// implementation owns a `SpeechAnalyzer`, while tests substitute a value that
/// records calls and emits synthetic events.
///
/// A transcriber is also an ``AudioSampleConsuming``, so it is attached to
/// capture in the same way the activity summary is, and audio reaches it on
/// the capture system's delivery queue without a detour through the main
/// actor.
nonisolated protocol SpeechTranscribing: AudioSampleConsuming {

    /// Partial text, finalised text and interruptions, in the order they were
    /// produced.
    ///
    /// The sequence spans the transcriber's whole life, not one run, so a stop
    /// and a later start are observed through the same sequence. It finishes
    /// when the transcriber is released.
    var events: AsyncStream<TranscriptionEvent> { get }

    /// The locales the recogniser supports, and whether each one's on-device
    /// model is installed.
    ///
    /// - Returns: The available locales, ordered by display name.
    func availableLocales() async -> [TranscriptionLocale]

    /// Reports whether recognition could run with this configuration.
    ///
    /// - Parameter configuration: The locale and hints to check.
    /// - Returns: What the recogniser can do, without starting anything.
    func availability(for configuration: TranscriptionConfiguration) async -> SpeechRecognitionAvailability

    /// Begins a recognition run.
    ///
    /// The call returns once the recogniser is ready for audio, so a caller
    /// that returns without an error can start capture.
    ///
    /// - Parameter configuration: The locale and hints to recognise with.
    /// - Throws: ``TranscriptionError``. Starting while a run is in progress
    ///   throws ``TranscriptionError/alreadyTranscribing`` rather than
    ///   restarting silently.
    func start(configuration: TranscriptionConfiguration) async throws

    /// Ends the run, finalising whatever audio has already been accepted.
    ///
    /// Stopping when nothing is running is not an error, so teardown paths can
    /// call it unconditionally.
    func stop() async
}

/// A reason recognition could not start, or could not continue.
nonisolated enum TranscriptionError: Error, Equatable, Sendable {
    /// A start was requested while a run was already in progress.
    case alreadyTranscribing

    /// Recognition cannot run with the requested configuration.
    case unavailable(SpeechRecognitionAvailability)

    /// The recogniser accepted no audio format ScribeKit can produce.
    case incompatibleAudioFormat

    /// Starting failed for a reason the system described.
    case systemFailure(String)
}

extension TranscriptionError: LocalizedError {
    /// A message suitable for display in the setup screen.
    var errorDescription: String? {
        switch self {
        case .alreadyTranscribing:
            "Transcription is already running."
        case let .unavailable(availability):
            availability.message ?? "Speech recognition is unavailable."
        case .incompatibleAudioFormat:
            "The speech recogniser accepts no audio format ScribeKit can produce from this capture."
        case let .systemFailure(description):
            "Transcription could not start: \(description)"
        }
    }
}
