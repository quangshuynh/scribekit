//
//  TranscriptionState.swift
//  ScribeKit
//

import Foundation

/// The mutually exclusive states of the speech recognition subsystem.
///
/// Recognition is kept separate from ``AudioCaptureState`` because the two
/// fail independently: a stream can be healthy while the recogniser is being
/// restarted, and recognition can be ready before any audio exists. Collapsing
/// them into one enum would make "capturing but not transcribing" impossible
/// to express honestly.
nonisolated enum TranscriptionState: Equatable, Sendable {
    /// Nothing is being recognised and no start is in progress.
    case idle

    /// A start was requested; availability is being checked and the recogniser
    /// built.
    case preparing

    /// The recogniser is running and consuming audio.
    case transcribing

    /// The recogniser stopped by itself and a bounded restart is under way.
    case recovering

    /// A stop was requested and pending audio is being finalised.
    case stopping

    /// Recognition ended or could not start; the message explains why.
    case failed(message: String)

    /// Whether recognition is holding, or is about to hold, system resources.
    var isActive: Bool {
        switch self {
        case .preparing, .transcribing, .recovering, .stopping: true
        case .idle, .failed: false
        }
    }

    /// What went wrong, when something did.
    var failureMessage: String? {
        if case let .failed(message) = self { message } else { nil }
    }

    /// Whether a start request is meaningful in this state.
    ///
    /// A failure is a report about the previous attempt, not a latch, so a
    /// failed recogniser can be started again.
    var canStart: Bool {
        switch self {
        case .idle, .failed: true
        case .preparing, .transcribing, .recovering, .stopping: false
        }
    }

    /// Whether a stop request is meaningful in this state.
    var canStop: Bool {
        switch self {
        case .preparing, .transcribing, .recovering: true
        case .idle, .stopping, .failed: false
        }
    }
}
