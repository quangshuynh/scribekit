//
//  MeetingMenuBarPresentation.swift
//  ScribeKit
//

import Foundation

/// What the menu bar shows about the meeting, derived from runtime state.
///
/// The menu bar is a second view of the one meeting, not a second application:
/// it answers what is running, what it is called, how it is configured and
/// where its files are, and it offers Stop, the main window and Quit. Nothing
/// here decides anything, and nothing here is a state of its own — the whole
/// value is a function of ``MeetingRuntimeStatus`` and the meeting's snapshot,
/// so what the menu says and what the window says are the same claim rendered
/// twice.
///
/// The elapsed time is deliberately not part of it. It changes every second
/// and everything else here does not, so it is read from the runtime's clock
/// where it is displayed rather than rebuilding this value once a second.
nonisolated struct MeetingMenuBarPresentation: Equatable, Sendable {

    /// The SF Symbol shown in the menu bar itself.
    let symbolName: String

    /// What the menu bar item announces to assistive technology.
    let accessibilityLabel: String

    /// The meeting's title, when there is a meeting to name.
    let title: String?

    /// A short phrase naming the state, shown above the details.
    let statusLine: String

    /// The meeting's fixed configuration, one phrase per line.
    let details: [String]

    /// What went wrong, when something did.
    let failureMessage: String?

    /// Whether the elapsed time is worth showing.
    let showsElapsed: Bool

    /// Whether the Stop item should be offered.
    let canStop: Bool

    /// Whether the Pause item should be offered.
    let canPause: Bool

    /// Whether the Resume item should be offered.
    let canResume: Bool

    /// The transcript to reveal in the Finder, when one exists.
    let transcriptURL: URL?

    /// The retained recording to reveal in the Finder, when one exists.
    let audioURL: URL?

    /// Builds the presentation for one moment of runtime state.
    ///
    /// - Parameters:
    ///   - status: What the meeting as a whole is doing.
    ///   - meeting: The meeting's fixed configuration, when one has started.
    ///   - transcript: Where the transcript is, when it has been created.
    ///   - audio: Where the retained recording is, when there is one.
    ///   - canStop: Whether the runtime would act on a stop request.
    ///   - canPause: Whether the runtime would act on a pause request.
    ///   - canResume: Whether the runtime would act on a resume request.
    init(
        status: MeetingRuntimeStatus,
        meeting: MeetingSnapshot?,
        transcript: URL?,
        audio: URL?,
        canStop: Bool,
        canPause: Bool = false,
        canResume: Bool = false
    ) {
        self.title = meeting?.title
        self.failureMessage = status.failureMessage
        self.transcriptURL = transcript
        self.audioURL = audio
        self.canStop = canStop
        self.canPause = canPause
        self.canResume = canResume
        self.showsElapsed = status.isActive

        switch status {
        case .idle:
            symbolName = "waveform"
            statusLine = "No meeting running"
        case .preparing:
            symbolName = "hourglass"
            statusLine = "Starting…"
        case .transcribing:
            symbolName = "waveform.circle.fill"
            statusLine = "Transcribing"
        case .paused:
            symbolName = "pause.circle.fill"
            statusLine = "Paused"
        case .stopping:
            symbolName = "hourglass"
            statusLine = "Stopping…"
        case .completed:
            symbolName = "checkmark.circle"
            statusLine = "Meeting finished"
        case .failed:
            symbolName = "exclamationmark.triangle.fill"
            statusLine = "Meeting failed"
        }

        if let title = meeting?.title {
            accessibilityLabel = "ScribeKit. \(statusLine). \(title)"
        } else {
            accessibilityLabel = "ScribeKit. \(statusLine)"
        }

        var details: [String] = []
        if status.isActive, let meeting {
            if let sources = meeting.sourceSummary {
                details.append(status == .paused ? "Paused; \(sources) not being captured" : "Capturing \(sources)")
            }
            details.append(Self.retentionDescription(meeting.audioRetention))
        }
        self.details = details
    }

    /// Describes what a meeting is keeping of its audio, in the menu's voice.
    ///
    /// - Parameter mode: The meeting's retention choice.
    /// - Returns: One phrase.
    private static func retentionDescription(_ mode: AudioRetentionMode) -> String {
        switch mode {
        case .none: "Keeping the transcript only"
        case .raw: "Keeping raw audio"
        case .compressed: "Keeping compressed audio"
        }
    }
}
