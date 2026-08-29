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

    /// Seconds from the start of the run to the start of the gap, when the
    /// pipeline knows where it fell.
    ///
    /// `nil` means only the length is known. Dropped audio carries the time of
    /// the buffer that was discarded; time lost to a recogniser being rebuilt
    /// does not, because no audio clock was running to place it against.
    let startTime: Double?

    /// How long the untranscribed stretch lasted, in seconds.
    let duration: Double

    /// What caused it.
    let reason: Reason

    /// Creates a gap.
    ///
    /// - Parameters:
    ///   - startTime: Seconds from the start of the run, or `nil` when the
    ///     position is not known.
    ///   - duration: How much audio was not transcribed, in seconds.
    ///   - reason: What caused the gap.
    init(startTime: Double? = nil, duration: Double, reason: Reason) {
        self.startTime = startTime
        self.duration = duration
        self.reason = reason
    }

    /// A phrase naming the cause, used in the transcript and the interface.
    var reasonDescription: String {
        switch reason {
        case .audioDropped: "recognition fell behind capture"
        case .recognizerRestarted: "the recogniser was restarted"
        }
    }
}
