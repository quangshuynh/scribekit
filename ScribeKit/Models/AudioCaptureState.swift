//
//  AudioCaptureState.swift
//  ScribeKit
//

import Foundation

/// The mutually exclusive states of the audio capture subsystem.
///
/// This is deliberately narrower than ``MeetingState``: a meeting covers
/// transcription, recovery and completion, while capture is one subsystem that
/// a session drives. Keeping the two separate avoids a capture failure having
/// to be expressed as a meeting lifecycle state, and keeps this enum usable
/// before any session exists.
nonisolated enum AudioCaptureState: Equatable, Sendable {
    /// Nothing is being captured and no start is in progress.
    case idle

    /// A start was requested; sources are being resolved and the stream built.
    case preparing

    /// The capture stream is running and delivering audio.
    case capturing

    /// A stop was requested and the stream is being torn down.
    case stopping

    /// Capture ended or failed to start; the message explains why.
    case failed(message: String)

    /// Whether capture is holding, or is about to hold, system resources.
    var isActive: Bool {
        switch self {
        case .preparing, .capturing, .stopping: true
        case .idle, .failed: false
        }
    }

    /// Whether a start request is meaningful in this state.
    ///
    /// A failed state can be started again: the failure is a report about the
    /// previous attempt, not a latch.
    var canStart: Bool {
        switch self {
        case .idle, .failed: true
        case .preparing, .capturing, .stopping: false
        }
    }

    /// Whether a stop request is meaningful in this state.
    ///
    /// Stopping while preparing is allowed, so a start that is slow to resolve
    /// sources can still be abandoned.
    var canStop: Bool {
        switch self {
        case .preparing, .capturing: true
        case .idle, .stopping, .failed: false
        }
    }
}
