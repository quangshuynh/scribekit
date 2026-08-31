//
//  TranscriptReview.swift
//  ScribeKit
//

import Foundation

/// Why a finalised span was put forward for review after the meeting.
///
/// Each case names evidence that was actually captured while the span was
/// recognised, and the two are different kinds of thing. ``lowConfidence`` is
/// the recogniser's own judgement, read from Apple's `transcriptionConfidence`
/// attribute; ``nearInterruption`` is ScribeKit's observation of its own
/// pipeline. The interface keeps them apart, so a user is never told the
/// recogniser said something it did not say.
///
/// Nothing here is a correction, a doubt about the words, or a suggestion that
/// the transcript is wrong. A reason says why a passage is worth listening to
/// again.
nonisolated enum TranscriptReviewReason: String, Codable, Equatable, Sendable, CaseIterable {

    /// The recogniser attached a confidence to the span and it was below the
    /// threshold ``TranscriptReviewPolicy/lowConfidence``.
    case lowConfidence

    /// The span is the first one finalised after audio that was never
    /// transcribed.
    case nearInterruption

    /// Whether the reason is the recogniser's own confidence rather than
    /// ScribeKit's observation of it.
    ///
    /// The interface keeps the two apart, because a user reading "confidence
    /// was low" should be reading Apple's judgement and nothing else.
    var isRecognizerConfidence: Bool { self == .lowConfidence }

    /// One sentence saying what was observed, in the terms it was observed in.
    var explanation: String {
        switch self {
        case .lowConfidence:
            "Recognition confidence was low."
        case .nearInterruption:
            "Near audio that was not transcribed."
        }
    }
}

/// How much attention a review candidate is worth, in three steps.
///
/// Three words rather than a number: the evidence behind a candidate is a
/// threshold comparison and a count, and rendering that as a percentage would
/// state a precision nothing measured.
nonisolated enum TranscriptReviewPriority: String, Codable, Equatable, Sendable, CaseIterable {
    /// The recogniser itself was unsure, and either badly so or with audio
    /// missing right beside the span.
    case high

    /// The recogniser was unsure.
    case medium

    /// The recogniser was sure enough, but the span sits against audio that
    /// was never transcribed.
    case low

    /// A short label for the interface.
    var displayName: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    /// Ordering from most to least worth attention, for a deterministic sort.
    var rank: Int {
        switch self {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
    }
}

/// One finalised span ScribeKit puts forward for review, and the evidence for
/// it.
///
/// The candidate holds no transcript text. It names a span by its position in
/// the written document, so the words shown for review are read back from
/// `transcript.md` itself and cannot drift from it or be a second copy of it.
///
/// ``startTime`` and ``endTime`` are the segment's audio-relative offsets:
/// seconds from the first captured frame, which is the same frame a retained
/// recording starts at. That is what makes a seek exact rather than derived
/// from the transcript's twelve-hour clock.
nonisolated struct TranscriptReviewCandidate: Codable, Equatable, Sendable, Identifiable {

    /// The span's position in the transcript, counting finalised spans from
    /// zero — the same index ``TranscriptSpan/index`` carries.
    let spanIndex: Int

    /// Seconds from the first captured frame to the start of the span.
    let startTime: Double

    /// Seconds from the first captured frame to the end of the span.
    let endTime: Double

    /// The recogniser's own confidence in the span: the lowest value any word
    /// of it carried, or `nil` when the recogniser attached none.
    let confidence: Double?

    /// Why the span was put forward, in the order the reasons are declared.
    let reasons: [TranscriptReviewReason]

    /// The span's position, which identifies the candidate within a session.
    var id: Int { spanIndex }

    /// Creates a candidate.
    ///
    /// - Parameters:
    ///   - spanIndex: The span's position in the transcript.
    ///   - startTime: Seconds from the first captured frame to its start.
    ///   - endTime: Seconds from the first captured frame to its end.
    ///   - confidence: The recogniser's own confidence, when it reported one.
    ///   - reasons: Why the span was put forward.
    init(
        spanIndex: Int,
        startTime: Double,
        endTime: Double,
        confidence: Double?,
        reasons: [TranscriptReviewReason]
    ) {
        self.spanIndex = spanIndex
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.reasons = reasons
    }

    /// How much attention the candidate is worth.
    ///
    /// Deterministic, and derived from the reasons and the confidence alone:
    /// the recogniser doubting itself outranks ScribeKit noticing something,
    /// and doubt that is severe, or that coincides with missing audio,
    /// outranks doubt on its own.
    var priority: TranscriptReviewPriority {
        let recogniserWasUnsure = reasons.contains(.lowConfidence)
        if recogniserWasUnsure {
            let veryLow = (confidence ?? 1) <= TranscriptReviewPolicy.veryLowConfidence
            return veryLow || reasons.count > 1 ? .high : .medium
        }
        return reasons.count > 1 ? .medium : .low
    }

    /// One sentence describing the candidate for assistive technology.
    ///
    /// The screen states a flagged passage in four parts — when it was said,
    /// how much attention it is worth, why it was put forward and whether it
    /// has been dealt with — spread across a row that also carries controls.
    /// Read as separate elements those parts arrive without each other, so the
    /// row states them once, here, in the order the screen shows them.
    ///
    /// It is one string rather than a label and a value because the row is a
    /// static-text leaf, and such an element publishes a single string.
    ///
    /// - Parameters:
    ///   - timestamp: The wall-clock time the transcript wrote for the span.
    ///   - text: The span's recognised words, exactly as the transcript has
    ///     them.
    ///   - isReviewed: Whether the user has marked the passage reviewed.
    ///   - hasAudio: Whether the meeting kept a recording to play.
    /// - Returns: The description.
    func accessibilityDescription(
        timestamp: String,
        text: String,
        isReviewed: Bool,
        hasAudio: Bool
    ) -> String {
        var parts = [
            "\(timestamp). \(priority.displayName) priority.",
            isReviewed ? "Reviewed." : "Needs review.",
            text
        ]
        parts.append(contentsOf: reasons.map(\.explanation))
        parts.append(hasAudio
                     ? "Audio is available for this passage."
                     : "This meeting kept no recording, so there is no audio to play.")
        return parts.joined(separator: " ")
    }
}

/// The rules that turn captured evidence into a review candidate.
///
/// Everything here is a pure function of what was recorded while a span was
/// recognised, so the same session always produces the same candidates in the
/// same order, and the thresholds are stated in one place rather than spread
/// through the code that applies them.
nonisolated enum TranscriptReviewPolicy {

    /// Confidence at or below which the recogniser is treated as unsure.
    ///
    /// Apple attaches `transcriptionConfidence` to the runs of a finalised
    /// result as a `Double` and documents no scale for it, so the threshold
    /// was measured rather than assumed. Synthesised speech through this Mac's
    /// en-US model gave correctly recognised spans a lowest-word confidence of
    /// 0.60 to 0.98, while a span containing two misrecognised words bottomed
    /// out at 0.14 and one containing a mis-split word at 0.33. The two
    /// populations do not overlap, and this sits between them.
    ///
    /// The value is used for this comparison and nothing else. ScribeKit never
    /// shows it, or anything derived from it, as a number or a percentage.
    static let lowConfidence = 0.5

    /// Confidence at or below which a span is treated as badly unsure, which
    /// is where the clearly wrong words in that measurement fell.
    static let veryLowConfidence = 0.25

    /// Assesses one finalised span.
    ///
    /// - Parameters:
    ///   - segment: The span the recogniser finalised, carrying whatever
    ///     confidence it reported.
    ///   - spanIndex: The span's position in the transcript.
    ///   - followsInterruption: Whether the span is the first one finalised
    ///     after audio that was never transcribed.
    /// - Returns: A candidate, or `nil` when nothing about the span asks for
    ///   review.
    static func candidate(
        for segment: TranscriptSegment,
        spanIndex: Int,
        followsInterruption: Bool
    ) -> TranscriptReviewCandidate? {
        var reasons: [TranscriptReviewReason] = []
        if let confidence = segment.confidence, confidence <= lowConfidence {
            reasons.append(.lowConfidence)
        }
        if followsInterruption {
            reasons.append(.nearInterruption)
        }
        guard !reasons.isEmpty else { return nil }

        return TranscriptReviewCandidate(
            spanIndex: spanIndex,
            startTime: segment.startTime,
            endTime: segment.endTime,
            confidence: segment.confidence,
            reasons: reasons
        )
    }
}
