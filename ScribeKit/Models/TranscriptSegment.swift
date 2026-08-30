//
//  TranscriptSegment.swift
//  ScribeKit
//

import Foundation

/// One span of recognised speech, as the recogniser reported it.
///
/// A segment is the unit later intervals persist, so its timing is expressed
/// against the audio rather than against the moment the interface happened to
/// receive it: ``startTime`` and ``endTime`` are seconds from the first frame
/// of captured audio in this recognition run. The wall-clock time of a segment
/// is that offset added to the session's start date, which the session owns.
///
/// The text is exactly what the recogniser returned. ScribeKit does not
/// capitalise, punctuate, expand, correct or otherwise rewrite it.
nonisolated struct TranscriptSegment: Identifiable, Equatable, Sendable {

    /// Whether the recogniser considers a span settled.
    enum RecognitionState: Equatable, Sendable {
        /// A hypothesis that the recogniser may still revise or replace.
        ///
        /// Partial text is ephemeral. It is shown live and then discarded; it
        /// is never appended to the transcript, because the recogniser will
        /// restate the same span as a finalised segment.
        case partial

        /// Text the recogniser has finalised and will not revise.
        case final
    }

    /// Identity for this segment, stable for as long as it exists.
    let id: UUID

    /// The recognised text, unmodified.
    let text: String

    /// Seconds from the start of this recognition run to the start of the span.
    let startTime: Double

    /// Seconds from the start of this recognition run to the end of the span.
    let endTime: Double

    /// Whether the recogniser has finalised the span.
    let state: RecognitionState

    /// The BCP-47 identifier of the locale the span was recognised in.
    let localeIdentifier: String

    /// The recogniser's own confidence in the span, when it reported one.
    ///
    /// This is Apple's `transcriptionConfidence` attribute, requested through
    /// `SpeechTranscriber.ResultAttributeOption` and read from the result's
    /// runs: the lowest value any run of the span carried, because the weakest
    /// word is what a reviewer would want to hear again. It is `nil` when the
    /// recogniser attached no confidence to the span, which is a fact about
    /// this result rather than a reason to invent a number for it.
    ///
    /// ScribeKit does not interpret the value as a percentage and never shows
    /// it as one. It is compared against thresholds to decide whether a span
    /// is worth reviewing, and nothing else.
    let confidence: Double?

    /// Creates a segment.
    ///
    /// - Parameters:
    ///   - id: Identity for the segment. A fresh value by default.
    ///   - text: The recognised text, exactly as reported.
    ///   - startTime: Seconds from the start of the recognition run.
    ///   - endTime: Seconds from the start of the recognition run.
    ///   - state: Whether the recogniser has finalised the span.
    ///   - localeIdentifier: The BCP-47 locale the span was recognised in.
    ///   - confidence: The recogniser's own confidence, when it reported one.
    init(
        id: UUID = UUID(),
        text: String,
        startTime: Double,
        endTime: Double,
        state: RecognitionState,
        localeIdentifier: String,
        confidence: Double? = nil
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.state = state
        self.localeIdentifier = localeIdentifier
        self.confidence = confidence
    }

    /// How long the span lasts, in seconds, or zero when the recogniser gave
    /// an end before its start.
    var duration: Double { max(0, endTime - startTime) }

    /// The text with the whitespace that joins it to the previous span
    /// removed, for display in a list of separate segments.
    ///
    /// Recognised spans carry the space that separates them from the segment
    /// before, which matters when the transcript is written as running text
    /// and is noise when each segment is a row. The stored ``text`` is left
    /// untouched.
    var displayText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}
