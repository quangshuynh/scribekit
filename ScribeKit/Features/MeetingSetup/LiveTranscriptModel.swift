//
//  LiveTranscriptModel.swift
//  ScribeKit
//

import Foundation

/// The transcript as it stands during a live recognition run.
///
/// The model applies the distinction the recogniser makes. Finalised spans
/// accumulate; the partial hypothesis is a single value that each new partial
/// replaces, so a sentence heard word by word leaves one entry rather than one
/// entry per word. Nothing is written to disk here — this interval keeps the
/// transcript in memory only.
@MainActor
@Observable
final class LiveTranscriptModel {

    /// Spans the recogniser has finalised, in the order it finalised them.
    private(set) var finalizedSegments: [TranscriptSegment] = []

    /// The hypothesis for what is being said now, replaced by each new partial
    /// and cleared when the span is finalised.
    private(set) var partialSegment: TranscriptSegment?

    /// When the current run started, so a segment's audio-relative time can be
    /// read as a wall-clock time later.
    private(set) var startedAt: Date?

    /// Audio the pipeline could not transcribe, in seconds.
    ///
    /// The transcript has gaps of this total length. It is reported rather
    /// than hidden, because a transcript that silently omits speech is worse
    /// than one that says it did.
    private(set) var untranscribedSeconds: Double = 0

    /// The most recent interruption, kept so the interface can explain the
    /// gap. Only the latest is retained; a run does not accumulate a log.
    private(set) var lastInterruption: TranscriptionInterruption?

    /// Whether anything has been recognised yet.
    var isEmpty: Bool { finalizedSegments.isEmpty && partialSegment == nil }

    /// Clears the transcript and marks the start of a run.
    ///
    /// - Parameter date: The moment the run started. Now by default.
    func begin(at date: Date = .now) {
        finalizedSegments = []
        partialSegment = nil
        untranscribedSeconds = 0
        lastInterruption = nil
        startedAt = date
    }

    /// Clears the transcript and forgets the run.
    func reset() {
        begin()
        startedAt = nil
    }

    /// Applies one transcription event.
    ///
    /// - Parameter event: What the transcriber reported.
    func apply(_ event: TranscriptionEvent) {
        switch event {
        case let .partial(segment):
            partialSegment = segment.displayText.isEmpty ? nil : segment
        case let .final(segment):
            partialSegment = nil
            guard !segment.displayText.isEmpty else { return }
            finalizedSegments.append(segment)
        case let .interrupted(interruption):
            lastInterruption = interruption
            switch interruption {
            case let .audioDropped(seconds, _):
                untranscribedSeconds += seconds
            case .recognitionFailed:
                // The hypothesis was never finalised and the recogniser that
                // produced it has stopped, so it is not transcript material.
                partialSegment = nil
            }
        }
    }

    /// The wall-clock time a segment's audio began, when the run's start is
    /// known.
    ///
    /// - Parameter segment: The segment to place in time.
    /// - Returns: The moment the span began, or `nil` before a run has started.
    func wallClockStart(of segment: TranscriptSegment) -> Date? {
        startedAt?.addingTimeInterval(segment.startTime)
    }
}
