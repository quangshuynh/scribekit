//
//  MeetingState.swift
//  ScribeKit
//

import Foundation

/// The mutually exclusive lifecycle states of a meeting session.
///
/// A session is always in exactly one state. Modelling the lifecycle as an
/// enum rather than a set of independent flags makes contradictory
/// combinations (such as "paused while stopping") unrepresentable.
enum MeetingState: String, Codable, Sendable, CaseIterable, Hashable {
    /// No session is running and none is being prepared.
    case idle

    /// The session exists, but capture and transcription have not started yet.
    case preparing

    /// Audio is being captured and transcribed.
    case transcribing

    /// Capture is suspended and can be resumed without ending the session.
    case paused

    /// A previously interrupted session is being restored before it resumes.
    case recovering

    /// The session is finishing: pending work is being flushed before completion.
    case stopping

    /// The session has ended and its artifacts are final.
    case completed

    /// The states this state may legally move to.
    ///
    /// `completed` is terminal and therefore has no successors.
    var allowedTransitions: Set<MeetingState> {
        switch self {
        case .idle: [.preparing, .recovering]
        case .preparing: [.transcribing, .stopping]
        case .transcribing: [.paused, .stopping]
        case .paused: [.transcribing, .stopping]
        case .recovering: [.transcribing, .stopping]
        case .stopping: [.completed]
        case .completed: []
        }
    }

    /// Whether the state represents a session that has ended.
    var isTerminal: Bool { allowedTransitions.isEmpty }

    /// Whether a session in this state is holding capture resources.
    ///
    /// Used by callers that need to know whether teardown work is required,
    /// for example when the application is asked to quit.
    var isActive: Bool {
        switch self {
        case .preparing, .transcribing, .paused, .recovering, .stopping: true
        case .idle, .completed: false
        }
    }

    /// Reports whether moving directly to another state is legal.
    ///
    /// - Parameter state: The candidate destination state.
    /// - Returns: `true` when the transition is permitted. Transitioning to the
    ///   current state is not permitted, because every transition is expected
    ///   to represent an observable lifecycle change.
    func canTransition(to state: MeetingState) -> Bool {
        allowedTransitions.contains(state)
    }
}

/// An error raised when a caller attempts an illegal lifecycle change.
enum MeetingStateError: Error, Equatable, Sendable {
    /// The requested transition is not part of the session lifecycle.
    case invalidTransition(from: MeetingState, to: MeetingState)
}
