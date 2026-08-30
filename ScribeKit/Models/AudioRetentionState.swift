//
//  AudioRetentionState.swift
//  ScribeKit
//

import Foundation

/// The mutually exclusive states of retained audio writing.
///
/// Separate from ``TranscriptPersistenceState`` for the reason the other
/// subsystem states are separate from each other: the transcript and the audio
/// file are two durable artifacts with two independent ways to fail, and a
/// meeting whose transcript is safe while its audio file is not is exactly the
/// situation a user must be told about rather than one that should be
/// unrepresentable.
///
/// ``idle`` is also what a meeting keeping no audio looks like from start to
/// finish: ``AudioRetentionMode/none`` never opens a file, so it never leaves
/// this state.
nonisolated enum AudioRetentionState: Equatable, Sendable {
    /// No audio file is open, and none is being prepared. This is the whole
    /// life of a meeting that keeps no audio.
    case idle

    /// The audio file is being created.
    case preparing

    /// Captured audio is being written to this file as it arrives.
    case retaining(URL)

    /// The audio file was closed successfully and is readable.
    case retained(URL)

    /// Retention failed; the message says what it means for the audio. The URL
    /// is present when a file had already been created, and that file is left
    /// exactly as it was — ScribeKit never deletes a partly written recording.
    case failed(message: String, url: URL?)

    /// The audio file this state refers to, once there is one.
    var url: URL? {
        switch self {
        case .idle, .preparing: nil
        case let .retaining(url), let .retained(url): url
        case let .failed(_, url): url
        }
    }

    /// Whether a file is open and holding a session's audio.
    var isActive: Bool {
        switch self {
        case .preparing, .retaining: true
        case .idle, .retained, .failed: false
        }
    }

    /// What went wrong, when something did.
    var failureMessage: String? {
        if case let .failed(message, _) = self { message } else { nil }
    }
}
