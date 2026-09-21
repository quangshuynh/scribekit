//
//  TranscriptGapIncident.swift
//  ScribeKit
//

import Foundation

/// One continuing condition that is costing a meeting audio, accumulated from
/// the observations the pipeline reports about it.
///
/// A recogniser that has fallen behind capture does not lose audio once. It
/// loses the oldest buffer in the backlog, then the next, for as long as it
/// stays behind, and the pipeline reports each accumulated fraction of a
/// second as it happens. Written out one by one those reports are a truthful
/// but unreadable document: a meeting that spent four minutes behind produces
/// hundreds of near-identical blockquotes. An incident is the same information
/// said once — when it began, when it stopped, and how much audio it cost.
///
/// The type keeps two quantities that must never be confused. ``startTime``
/// and ``endTime`` bound *when the condition was going on*; ``lostSeconds`` is
/// how much audio inside that range was actually discarded. Between two
/// discarded stretches the recogniser may have transcribed normally, so the
/// range is an upper bound on the damage and never a statement of it.
///
/// ``lostSeconds`` is a sum, and it is only allowed to be one because of what
/// an observation means: the bounded backlog hands back each buffer it evicts
/// exactly once, so the stretches being added are distinct audio that cannot
/// overlap. Nothing here derives a length from the range, and nothing derives
/// a range from a length.
///
/// The incident is a value type with no I/O. What decides where one incident
/// ends and the next begins is evidence from the audio pipeline rather than a
/// delay chosen for the interface: see ``DroppedAudio/closesIncident``.
nonisolated struct TranscriptGapIncident: Equatable, Sendable {

    /// What is causing the loss. Only ``TranscriptGap/Reason/audioDropped``
    /// accumulates; a recogniser restart is a single measured event, reported
    /// on its own.
    let reason: TranscriptGap.Reason

    /// Seconds from the start of the meeting to the first audio this incident
    /// affected, when the pipeline knew where it fell.
    private(set) var startTime: Double?

    /// Seconds from the start of the meeting to the end of the last audio this
    /// incident affected, when the pipeline knew where it fell.
    private(set) var endTime: Double?

    /// How much audio this incident has cost, in seconds.
    private(set) var lostSeconds: Double

    /// How many observations have been folded into it, which is how many
    /// blockquotes the transcript would have carried without coalescing.
    private(set) var observationCount: Int

    /// Whether the evidence says the condition has ended.
    private(set) var isClosed: Bool

    /// Opens an incident from the first observation of a condition.
    ///
    /// - Parameter drop: What the pipeline reported.
    init(_ drop: DroppedAudio) {
        reason = .audioDropped
        startTime = drop.startTime
        endTime = drop.endTime
        lostSeconds = drop.seconds
        observationCount = 1
        isClosed = drop.closesIncident
    }

    /// Folds a further observation of the same condition into the incident.
    ///
    /// The range only ever widens and the loss only ever grows: an observation
    /// reports audio the backlog has already discarded, so nothing it carries
    /// can withdraw something an earlier one established.
    ///
    /// - Parameter drop: What the pipeline reported.
    mutating func extend(with drop: DroppedAudio) {
        if let start = drop.startTime {
            startTime = startTime.map { min($0, start) } ?? start
        }
        if let end = drop.endTime {
            endTime = endTime.map { max($0, end) } ?? end
        }
        lostSeconds += drop.seconds
        observationCount += 1
        isClosed = isClosed || drop.closesIncident
    }

    /// Whether this incident should absorb an observation rather than a new
    /// incident being opened for it.
    ///
    /// The rule is the pipeline's own evidence and nothing else. An
    /// observation that follows one which closed the incident belongs to a
    /// separate condition, because closure means the backlog demonstrably
    /// caught up in between; an observation that does not belongs to this one.
    /// There is deliberately no wall-clock or interface-driven timer here: the
    /// meeting's own clocks are not what decides whether recognition recovered.
    ///
    /// Boundaries the pipeline cannot see — a pause, a recogniser restart, the
    /// end of the meeting — are enforced by whoever owns the incident closing
    /// it explicitly, never by weakening this rule.
    ///
    /// - Parameter drop: What the pipeline reported.
    /// - Returns: `true` when the observation continues this incident.
    func accepts(_ drop: DroppedAudio) -> Bool { !isClosed }

    /// Whether anything has actually been lost yet.
    ///
    /// A report that only carries the news that recognition caught up closes
    /// an incident without adding to it, and an incident that never held any
    /// loss is not transcript material.
    var isEmpty: Bool { lostSeconds <= 0 }

    /// The incident as the durable gap marker it becomes.
    var gap: TranscriptGap {
        TranscriptGap(
            startTime: startTime,
            endTime: endTime,
            duration: lostSeconds,
            reason: reason
        )
    }
}
