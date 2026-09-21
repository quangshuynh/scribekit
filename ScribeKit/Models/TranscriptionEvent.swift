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

/// One observation of audio the bounded backlog discarded because recognition
/// had fallen behind capture.
///
/// An observation is not an incident. A recogniser that is behind keeps losing
/// audio for as long as it stays behind, and the pipeline reports what it has
/// lost as it goes rather than waiting for the end of a condition it cannot
/// predict the length of; ``TranscriptGapIncident`` is what turns a run of
/// these back into the single fact they describe.
///
/// ``seconds`` is authoritative and may be summed. The backlog hands each
/// evicted buffer back exactly once, so two observations never describe the
/// same audio twice. ``startTime`` and ``endTime`` bound where the loss fell;
/// the audio between them was *not* necessarily all lost, because the
/// recogniser goes on consuming buffers while it is dropping others.
nonisolated struct DroppedAudio: Equatable, Sendable {

    /// How much audio was discarded, in seconds. Distinct audio in every
    /// report, so a total over reports is a real total.
    let seconds: Double

    /// Seconds from the start of the run to the first audio this report
    /// covers, or `nil` when the buffer carried no usable timing.
    let startTime: Double?

    /// Seconds from the start of the run to the end of the last audio this
    /// report covers, or `nil` when the buffer carried no usable timing.
    let endTime: Double?

    /// Whether the backlog has demonstrably caught up, so no further audio can
    /// be lost to the condition this report belongs to.
    ///
    /// This is the evidence that separates one gap incident from the next, and
    /// it is an observation of the backlog rather than a delay: the queue has
    /// accepted a full backlog's worth of audio without having to evict any of
    /// it, which it could not have done while still full. A report that closes
    /// an incident may carry no audio at all — recognition catching up is news
    /// whether or not anything was left unreported when it did.
    let closesIncident: Bool

    /// Creates an observation.
    ///
    /// - Parameters:
    ///   - seconds: How much audio was discarded.
    ///   - startTime: Where the first discarded audio fell in the run.
    ///   - endTime: Where the last discarded audio ended in the run.
    ///   - closesIncident: Whether the backlog has caught up.
    init(
        seconds: Double,
        startTime: Double? = nil,
        endTime: Double? = nil,
        closesIncident: Bool = false
    ) {
        self.seconds = seconds
        self.startTime = startTime
        self.endTime = endTime
        self.closesIncident = closesIncident
    }
}

/// A reason some audio was not, or may not have been, transcribed.
nonisolated enum TranscriptionInterruption: Equatable, Sendable {
    /// Recognition fell behind capture and audio was discarded to keep memory
    /// bounded.
    ///
    /// One of these is an observation of a continuing condition, not a gap in
    /// its own right: see ``DroppedAudio``.
    case audioDropped(DroppedAudio)

    /// The recogniser stopped with an error, described by the system.
    case recognitionFailed(message: String)

    /// Reports discarded audio without naming the payload type.
    ///
    /// A convenience for the places that describe a single loss — the
    /// recogniser's own reporting path and tests — so the common case reads as
    /// one call rather than two.
    ///
    /// - Parameters:
    ///   - seconds: How much audio was discarded.
    ///   - startTime: Where the first discarded audio fell in the run.
    ///   - endTime: Where the last discarded audio ended in the run.
    ///   - closesIncident: Whether the backlog has caught up.
    /// - Returns: The interruption.
    static func audioDropped(
        seconds: Double,
        startTime: Double? = nil,
        endTime: Double? = nil,
        closesIncident: Bool = false
    ) -> TranscriptionInterruption {
        .audioDropped(DroppedAudio(
            seconds: seconds,
            startTime: startTime,
            endTime: endTime,
            closesIncident: closesIncident
        ))
    }

    /// The discarded audio this interruption reports, when it reports any.
    var droppedAudio: DroppedAudio? {
        switch self {
        case let .audioDropped(drop): drop
        case .recognitionFailed: nil
        }
    }

    /// A message suitable for display, or `nil` when the interruption carries
    /// nothing to tell the user about.
    ///
    /// A report that only says recognition caught up is one of those: it
    /// closes an incident and has no loss of its own to describe, and showing
    /// it as an interruption would put "0.0 s of audio was not transcribed" on
    /// the screen at the moment the trouble ended.
    var message: String? {
        switch self {
        case let .audioDropped(drop):
            drop.seconds > 0
                ? String(
                    format: "Recognition fell behind; %.1f s of audio was not transcribed.",
                    drop.seconds
                )
                : nil
        case let .recognitionFailed(message):
            "Recognition stopped: \(message)"
        }
    }
}
