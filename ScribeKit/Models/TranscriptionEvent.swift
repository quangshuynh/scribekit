//
//  TranscriptionEvent.swift
//  ScribeKit
//

import Foundation

/// Something a transcriber reported while a recognition run was in progress.
///
/// The cases keep the distinction the recogniser makes, because later work
/// depends on it: only finalised text is transcript material, and a gap in the
/// audio or in recognition is recorded rather than smoothed over.
nonisolated enum TranscriptionEvent: Equatable, Sendable {
    /// A revised hypothesis for the span being spoken now.
    ///
    /// Each partial replaces the one before it. Appending partials to a
    /// transcript would record the same sentence once per word.
    case partial(TranscriptSegment)

    /// A span the recogniser has finalised.
    case final(TranscriptSegment)

    /// Recognition did not cover part of the audio, or stopped.
    case interrupted(TranscriptionInterruption)

    /// The segment carried by this event, when it carries one.
    var segment: TranscriptSegment? {
        switch self {
        case let .partial(segment), let .final(segment): segment
        case .interrupted: nil
        }
    }
}

/// A reason some audio was not, or may not have been, transcribed.
nonisolated enum TranscriptionInterruption: Equatable, Sendable {
    /// Recognition fell behind capture and audio was discarded to keep memory
    /// bounded; the transcript has a gap of this length.
    case audioDropped(seconds: Double)

    /// The recogniser stopped with an error, described by the system.
    case recognitionFailed(message: String)

    /// A message suitable for display.
    var message: String {
        switch self {
        case let .audioDropped(seconds):
            String(format: "Recognition fell behind; %.1f s of audio was not transcribed.", seconds)
        case let .recognitionFailed(message):
            "Recognition stopped: \(message)"
        }
    }
}
