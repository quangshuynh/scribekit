//
//  StatusTone.swift
//  ScribeKit
//

import SwiftUI

/// How much attention a state asks for, which decides its colour.
///
/// A tone is never the whole message. Everything given a tone is also given a
/// word and a symbol of its own, so a state reads the same to someone who
/// cannot tell the colours apart, in either appearance, and to VoiceOver. The
/// colours are system colours, which macOS adapts to light, dark and increased
/// contrast.
nonisolated enum StatusTone: CaseIterable, Equatable, Sendable {

    /// Nothing to act on; information only.
    case neutral

    /// Ready, finished, or dealt with.
    case positive

    /// Audio is being captured right now.
    case live

    /// Worth a look, but nothing is wrong.
    case attention

    /// Something went partly wrong, or needs doing before a meeting starts.
    case warning

    /// Something failed.
    case critical

    /// The colour the tone is drawn in.
    var color: Color {
        switch self {
        case .neutral: .secondary
        case .positive: .green
        case .live: .red
        case .attention: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}

// MARK: - Domain states

extension MeetingStartReadiness.Status {

    /// The tone a readiness row is drawn in.
    nonisolated var tone: StatusTone {
        switch self {
        case .satisfied: .positive
        case .checking: .neutral
        case .advisory: .attention
        case .blocked: .warning
        }
    }
}

extension TranscriptReviewPriority {

    /// The tone a review passage is drawn in.
    ///
    /// Proportionate on purpose: a flagged passage is worth another listen,
    /// not an error, so even the highest priority is a warning rather than a
    /// failure and the lowest carries no colour at all.
    nonisolated var tone: StatusTone {
        switch self {
        case .high: .warning
        case .medium: .attention
        case .low: .neutral
        }
    }

    /// The symbol drawn beside the priority's name.
    nonisolated var symbolName: String {
        switch self {
        case .high: "exclamationmark.circle"
        case .medium: "questionmark.circle"
        case .low: "circle.dashed"
        }
    }
}

extension TranscriptReviewReason {

    /// The symbol drawn beside the reason's explanation.
    nonisolated var symbolName: String {
        switch self {
        case .lowConfidence: "gauge.with.dots.needle.33percent"
        case .nearInterruption: "waveform.slash"
        }
    }
}

extension HistorySessionStatus {

    /// The tone a past meeting's status is drawn in.
    nonisolated var tone: StatusTone {
        switch self {
        case .completed: .positive
        case .inProgress: .attention
        case .interrupted: .warning
        case .failed: .critical
        case .unrecorded: .neutral
        }
    }

    /// The symbol drawn beside the status's name.
    nonisolated var symbolName: String {
        switch self {
        case .completed: "checkmark.circle"
        case .inProgress: "clock"
        case .interrupted: "bolt.horizontal.circle"
        case .failed: "xmark.octagon"
        case .unrecorded: "doc.text"
        }
    }

    /// Whether a list row should state the status at all.
    ///
    /// A finished meeting is the ordinary case, and a badge on every row would
    /// make the exceptions harder to find. Rows state only the exceptions; the
    /// detail pane and VoiceOver state every status.
    nonisolated var isNoteworthy: Bool { self != .completed }
}

extension CaptureMode {

    /// The symbol drawn beside the mode's name.
    nonisolated var symbolName: String {
        switch self {
        case .applications: "macwindow"
        case .microphone: "mic"
        }
    }
}
