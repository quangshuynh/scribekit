//
//  MeetingRuntimeStatus.swift
//  ScribeKit
//

import Foundation

/// What the meeting as a whole is doing, in one value.
///
/// A meeting is four subsystems — capture, recognition, the transcript file
/// and the retained recording — each with its own state, and each of those
/// states says something the meeting screen genuinely needs. What the menu bar
/// needs, and what any other observer needs to answer "is a meeting running",
/// is a single answer derived from all four.
///
/// This is that answer, and it is a derivation rather than a second state
/// machine: nothing sets it, ``MeetingRuntime`` computes it, so the menu bar
/// and the main window cannot disagree about what the meeting is doing.
nonisolated enum MeetingRuntimeStatus: Equatable, Sendable {
    /// No meeting has been started, or the last one has been cleared away.
    case idle

    /// A meeting is starting: files are being created and the pipeline built.
    case preparing

    /// Audio is being captured and recognised.
    case transcribing

    /// A stop is under way and the meeting's artifacts are being finished.
    case stopping

    /// The meeting ended normally and its artifacts are closed.
    case completed

    /// The meeting failed; the message explains what it means for the
    /// artifacts.
    case failed(message: String)

    /// Whether the meeting is holding, or is about to hold, capture,
    /// recognition or file resources.
    ///
    /// This is the question the quit policy and the recovery controls ask, so
    /// it is answered here rather than by each of them re-deriving it.
    var isActive: Bool {
        switch self {
        case .preparing, .transcribing, .stopping: true
        case .idle, .completed, .failed: false
        }
    }

    /// What went wrong, when something did.
    var failureMessage: String? {
        if case let .failed(message) = self { message } else { nil }
    }

    /// Derives the meeting's state from its subsystems.
    ///
    /// Failure is reported first and by artifact: the transcript is the
    /// canonical one, so its failure is what the meeting failed of, then the
    /// retained recording, then capture and recognition. A failure is reported
    /// as soon as it exists, including while the teardown it triggered is
    /// still running, because a meeting that has already lost an artifact is
    /// not "stopping normally" and must not be described as though it were.
    ///
    /// - Parameters:
    ///   - capture: What the capture subsystem is doing.
    ///   - transcription: What the recogniser is doing.
    ///   - persistence: What the durable transcript is doing.
    ///   - audio: What the retained recording is doing, which stays
    ///     ``AudioRetentionState/idle`` for a meeting that keeps no audio.
    init(
        capture: AudioCaptureState,
        transcription: TranscriptionState,
        persistence: TranscriptPersistenceState,
        audio: AudioRetentionState
    ) {
        if let message = persistence.failureMessage {
            self = .failed(message: message)
        } else if let message = audio.failureMessage {
            self = .failed(message: message)
        } else if case let .failed(message) = capture {
            self = .failed(message: message)
        } else if case let .failed(message) = transcription {
            self = .failed(message: message)
        } else if capture == .stopping || transcription == .stopping {
            self = .stopping
        } else if capture == .capturing, transcription.isActive {
            self = .transcribing
        } else if capture.isActive || transcription.isActive || persistence.isActive || audio.isActive {
            self = .preparing
        } else if case .saved = persistence {
            self = .completed
        } else {
            self = .idle
        }
    }
}
