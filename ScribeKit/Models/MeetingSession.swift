//
//  MeetingSession.swift
//  ScribeKit
//

import Foundation

/// Metadata describing a single meeting the user has configured or recorded.
///
/// The session owns descriptive state only. Transcript content, captured
/// audio and their on-disk representation are deliberately kept outside this
/// type so that the raw transcript is never coupled to session bookkeeping.
nonisolated struct MeetingSession: Identifiable, Hashable, Codable, Sendable {
    /// Stable identity for the session, independent of its title.
    let id: UUID

    /// The user-entered meeting title, which may be empty.
    var title: String

    /// When the session was created, used for ordering and file naming.
    let createdAt: Date

    /// How much captured audio this session keeps once it ends.
    var audioRetention: AudioRetentionMode

    /// The audio sources the user selected for this session.
    var selectedSources: [CaptureSource]

    /// Where the session's artifacts are written.
    var destination: URL

    /// The session's current position in its lifecycle.
    private(set) var state: MeetingState

    /// Creates a session description.
    ///
    /// - Parameters:
    ///   - id: Identity for the session. Defaults to a fresh identifier.
    ///   - title: The user-entered meeting title. May be empty; use
    ///     ``displayTitle`` when presenting it.
    ///   - createdAt: Creation timestamp. Defaults to the current date.
    ///   - audioRetention: Audio retention choice. Defaults to
    ///     ``AudioRetentionMode/none``.
    ///   - selectedSources: The chosen audio sources. Defaults to empty.
    ///   - destination: Directory where session artifacts will be stored.
    ///   - state: Initial lifecycle state. Defaults to ``MeetingState/idle``.
    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        audioRetention: AudioRetentionMode = .default,
        selectedSources: [CaptureSource] = [],
        destination: URL,
        state: MeetingState = .idle
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.audioRetention = audioRetention
        self.selectedSources = selectedSources
        self.destination = destination
        self.state = state
    }

    /// Fallback title used when the user has not entered one.
    static let untitledPlaceholder = "Untitled Meeting"

    /// The title to show in the interface, with surrounding whitespace removed
    /// and a placeholder substituted for an effectively empty title.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.untitledPlaceholder : trimmed
    }

    /// Moves the session to another lifecycle state.
    ///
    /// - Parameter newState: The state to move to.
    /// - Throws: ``MeetingStateError/invalidTransition(from:to:)`` when the
    ///   transition is not part of the session lifecycle. The session is left
    ///   unchanged in that case.
    mutating func transition(to newState: MeetingState) throws {
        guard state.canTransition(to: newState) else {
            throw MeetingStateError.invalidTransition(from: state, to: newState)
        }
        state = newState
    }
}
