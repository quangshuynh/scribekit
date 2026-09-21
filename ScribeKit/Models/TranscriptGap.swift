//
//  TranscriptGap.swift
//  ScribeKit
//

import Foundation

/// A stretch of a meeting that was captured but never transcribed.
///
/// Gaps are transcript material in their own right: a file that silently omits
/// speech is worse than one that says where it stopped listening. The type is
/// framework-independent and carries only what the pipeline actually knows —
/// a position when there is one, and never an invented one.
///
/// A gap describes one *incident* rather than one observation. A recogniser
/// that has fallen behind loses audio repeatedly for as long as it stays
/// behind, and each of those losses is an observation of the same condition;
/// ``TranscriptGapIncident`` accumulates them and produces a single gap when
/// the condition ends. That is why the affected range and the amount of audio
/// lost are two separate facts here: the range is when the incident was going
/// on, and ``duration`` is how much audio inside it was actually discarded.
/// They are equal only for a gap that lost every second of its own range.
nonisolated struct TranscriptGap: Equatable, Sendable {

    /// Why the audio was not transcribed.
    enum Reason: Equatable, Sendable {
        /// Recognition fell behind capture and the oldest audio was dropped to
        /// keep the backlog bounded.
        case audioDropped

        /// The recogniser stopped by itself and was restarted; audio that
        /// arrived while it was down reached no recogniser.
        case recognizerRestarted
    }

    /// Seconds from the start of the meeting to the first audio the incident
    /// affected, when the pipeline knows where it fell.
    ///
    /// `nil` means only the length is known. Dropped audio carries the time of
    /// the buffer that was discarded; time lost to a recogniser being rebuilt
    /// does not, because no audio clock was running to place it against.
    let startTime: Double?

    /// Seconds from the start of the meeting to the end of the last audio the
    /// incident affected, when the pipeline knows it.
    ///
    /// With ``startTime`` this bounds the incident: nothing outside the range
    /// was affected by it. It does **not** say that everything inside the
    /// range was lost — audio between two discarded stretches may have been
    /// transcribed normally, and ``duration`` is what says how much was not.
    let endTime: Double?

    /// How much audio inside the incident was not transcribed, in seconds.
    ///
    /// This is a sum over distinct, non-overlapping stretches of discarded
    /// audio, never a measure of the range they fell in.
    let duration: Double

    /// What caused it.
    let reason: Reason

    /// Creates a gap.
    ///
    /// - Parameters:
    ///   - startTime: Seconds from the start of the meeting to the first
    ///     affected audio, or `nil` when the position is not known.
    ///   - endTime: Seconds from the start of the meeting to the end of the
    ///     last affected audio, or `nil` when the incident has no known extent
    ///     beyond its start.
    ///   - duration: How much audio was not transcribed, in seconds.
    ///   - reason: What caused the gap.
    init(startTime: Double? = nil, endTime: Double? = nil, duration: Double, reason: Reason) {
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.reason = reason
    }

    /// Seconds between the first and the last audio the incident affected,
    /// when both ends are known.
    var affectedSpan: Double? {
        guard let startTime, let endTime else { return nil }
        return max(0, endTime - startTime)
    }

    /// Whether the gap covers a stretch of the meeting wide enough to state as
    /// a range rather than as a position.
    ///
    /// The threshold is a whole second because that is the resolution a
    /// transcript's clock times are written at: an incident narrower than one
    /// second would be rendered as a range whose two ends are the same time,
    /// which says less than naming the moment it happened. A wider one is
    /// written as a range, and the range is always accompanied by how much
    /// audio was actually lost, because the two are different quantities.
    var spansRange: Bool { (affectedSpan ?? 0) >= 1 }

    /// A phrase naming the cause, used in the transcript and the interface.
    var reasonDescription: String {
        switch reason {
        case .audioDropped: "recognition fell behind capture"
        case .recognizerRestarted: "the recogniser was restarted"
        }
    }
}
