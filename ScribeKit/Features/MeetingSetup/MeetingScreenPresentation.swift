//
//  MeetingScreenPresentation.swift
//  ScribeKit
//

import Foundation

/// Which of its two arrangements the Meeting screen shows.
///
/// Configuring a meeting and following one are different jobs. Setup is a form;
/// a meeting is a transcript with a status line above it. Showing both at once
/// left the transcript competing with a column of disabled controls, so the
/// screen shows one arrangement at a time, decided here from the runtime rather
/// than kept as state of its own — a window rebuilt mid-meeting shows the
/// meeting, and one rebuilt after it shows what the meeting left.
nonisolated enum MeetingScreenLayout: Equatable, Sendable {

    /// The form that configures the next meeting.
    case setup

    /// The running meeting, or the one that has just ended, with its
    /// transcript filling the screen.
    case session

    /// Decides the arrangement.
    ///
    /// A meeting that is starting, running, paused or stopping is shown as a
    /// session. So is one that ended having captured something, until the user
    /// moves on: its transcript and what its ending means stay in view. A
    /// meeting that never started is reported on the setup form instead,
    /// because what the user needs next is to correct the setup.
    ///
    /// - Parameters:
    ///   - isRunning: Whether a meeting is starting, running or stopping.
    ///   - outcome: How the last meeting in this launch ended, if one has.
    init(isRunning: Bool, outcome: MeetingOutcomePresentation.Category?) {
        if isRunning {
            self = .session
            return
        }
        switch outcome {
        case nil, .startFailure?: self = .setup
        case .completed?, .interrupted?, .transcriptFailure?, .audioFailure?, .recognitionFailure?:
            self = .session
        }
    }
}

/// The word, symbol and tone that state what a meeting is doing, at the top
/// of the session arrangement.
///
/// One answer for the whole meeting, derived from the runtime's own status
/// and, once it has ended, from how it ended — the same derivation the menu bar
/// reads its status from, put in the words a status line needs.
nonisolated struct MeetingSessionStatus: Equatable, Sendable {

    /// The status in a word or two, such as `Listening` or `Paused`.
    let title: String

    /// The SF Symbol drawn beside ``title``.
    let symbolName: String

    /// How much attention the status asks for.
    let tone: StatusTone

    /// Derives the status.
    ///
    /// - Parameters:
    ///   - status: What the meeting as a whole is doing.
    ///   - isRecovering: Whether the recogniser is being restarted under a
    ///     running meeting.
    ///   - captureMode: Where the meeting's audio comes from.
    ///   - outcome: How the meeting ended, once it has.
    init(
        status: MeetingRuntimeStatus,
        isRecovering: Bool,
        captureMode: CaptureMode,
        outcome: MeetingOutcomePresentation.Category?
    ) {
        switch status {
        case .preparing:
            (title, symbolName, tone) = ("Starting", "hourglass", .neutral)
        case .transcribing where isRecovering:
            (title, symbolName, tone) = ("Restarting Recognition", "arrow.clockwise.circle", .warning)
        case .transcribing:
            // Listening rather than recording for the microphone: its audio is
            // transcribed and released, never kept.
            title = captureMode == .microphone ? "Listening" : "Capturing"
            (symbolName, tone) = ("circle.fill", .live)
        case .paused:
            (title, symbolName, tone) = ("Paused", "pause.circle", .neutral)
        case .stopping:
            (title, symbolName, tone) = ("Finishing", "hourglass", .neutral)
        case .failed:
            // A failure is reported as one even before the ending has been
            // recorded, while the other subsystems are still closing.
            if outcome == .interrupted {
                (title, symbolName, tone) = ("Interrupted", "bolt.horizontal.circle", .warning)
            } else {
                (title, symbolName, tone) = ("Stopped by an Error", "xmark.octagon", .critical)
            }
        case .idle, .completed:
            switch outcome {
            case .completed?, nil:
                (title, symbolName, tone) = ("Finished", "checkmark.circle", .positive)
            case .interrupted?:
                (title, symbolName, tone) = ("Interrupted", "bolt.horizontal.circle", .warning)
            case .transcriptFailure?, .audioFailure?, .recognitionFailure?, .startFailure?:
                (title, symbolName, tone) = ("Stopped by an Error", "xmark.octagon", .critical)
            }
        }
    }
}
