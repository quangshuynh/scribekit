//
//  TranscriptPersistenceState.swift
//  ScribeKit
//

import Foundation

/// The mutually exclusive states of durable transcript writing.
///
/// Kept separate from ``AudioCaptureState`` and ``TranscriptionState`` for the
/// same reason those are separate from each other: the three fail
/// independently, and a transcript that has stopped being saved while
/// recognition is still running is exactly the situation a user must be told
/// about rather than one that should be unrepresentable.
nonisolated enum TranscriptPersistenceState: Equatable, Sendable {
    /// Nothing is being written and no session is being prepared.
    case idle

    /// The session's folder and transcript file are being created.
    case preparing

    /// Finalised speech is being written to the transcript at this location.
    case saving(SessionArtifactLayout)

    /// The session finished and its transcript was flushed and closed.
    case saved(SessionArtifactLayout)

    /// Writing failed; the message explains what it means for the transcript.
    /// The layout is present when a file had already been created.
    case failed(message: String, layout: SessionArtifactLayout?)

    /// Where the session's artifacts are, once there are any.
    var layout: SessionArtifactLayout? {
        switch self {
        case .idle, .preparing: nil
        case let .saving(layout), let .saved(layout): layout
        case let .failed(_, layout): layout
        }
    }

    /// Whether a session is open and holding a file and a folder lease.
    var isActive: Bool {
        switch self {
        case .preparing, .saving: true
        case .idle, .saved, .failed: false
        }
    }

    /// What went wrong, when something did.
    var failureMessage: String? {
        if case let .failed(message, _) = self { message } else { nil }
    }
}
