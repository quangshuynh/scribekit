//
//  TranscriptReviewTests.swift
//  ScribeKitTests
//

import Foundation
import Speech
import Testing
@testable import ScribeKit

@Suite("Transcript review")
struct TranscriptReviewTests {

    // MARK: - The signal the recogniser actually provides

    @Test("The lowest word confidence in a span is the span's confidence")
    func confidenceIsTheWeakestWord() {
        var text = AttributedString("borehole telemetry")
        var weak = AttributedString(" boat hole")
        weak.transcriptionConfidence = 0.144
        text.transcriptionConfidence = 0.98
        text.append(weak)

        #expect(AppleSpeechTranscriber.confidence(of: text) == 0.144)
    }

    @Test("A span the recogniser attached no confidence to has none")
    func absentConfidenceIsNotInvented() {
        #expect(AppleSpeechTranscriber.confidence(of: AttributedString("no attributes here")) == nil)
    }

    // MARK: - Which spans are put forward, and how urgently

    /// One row of the assessment table.
    struct AssessmentCase: Sendable {
        let name: String
        let confidence: Double?
        let followsInterruption: Bool
        let reasons: [TranscriptReviewReason]
        let priority: TranscriptReviewPriority?
    }

    @Test("Reasons and priority follow only from captured evidence", arguments: [
        AssessmentCase(
            name: "a confident span nothing else touched is not a candidate",
            confidence: 0.95, followsInterruption: false, reasons: [], priority: nil
        ),
        AssessmentCase(
            name: "a span with no reported confidence is not a candidate on its own",
            confidence: nil, followsInterruption: false, reasons: [], priority: nil
        ),
        AssessmentCase(
            name: "confidence just above the threshold is not low",
            confidence: 0.51, followsInterruption: false, reasons: [], priority: nil
        ),
        AssessmentCase(
            name: "confidence at the threshold is low",
            confidence: 0.5, followsInterruption: false,
            reasons: [.lowConfidence], priority: .medium
        ),
        AssessmentCase(
            name: "badly low confidence is high priority on its own",
            confidence: 0.144, followsInterruption: false,
            reasons: [.lowConfidence], priority: .high
        ),
        AssessmentCase(
            name: "low confidence beside missing audio is high priority",
            confidence: 0.4, followsInterruption: true,
            reasons: [.lowConfidence, .nearInterruption], priority: .high
        ),
        AssessmentCase(
            name: "a confident span after missing audio is low priority",
            confidence: 0.95, followsInterruption: true,
            reasons: [.nearInterruption], priority: .low
        ),
        AssessmentCase(
            name: "an unmeasured span after missing audio is still low priority",
            confidence: nil, followsInterruption: true,
            reasons: [.nearInterruption], priority: .low
        )
    ])
    func assessment(_ testCase: AssessmentCase) {
        let segment = TranscriptSegment(
            text: "the quarterly figures",
            startTime: 12,
            endTime: 15,
            state: .final,
            localeIdentifier: "en-US",
            confidence: testCase.confidence
        )

        let candidate = TranscriptReviewPolicy.candidate(
            for: segment,
            spanIndex: 3,
            followsInterruption: testCase.followsInterruption
        )

        #expect(candidate?.reasons ?? [] == testCase.reasons, "\(testCase.name)")
        #expect(candidate?.priority == testCase.priority, "\(testCase.name)")
    }

    @Test("A candidate keeps the span's audio-relative offsets exactly")
    func candidateKeepsOffsets() throws {
        let segment = TranscriptSegment(
            text: "anisotropic diffusion",
            startTime: 133.25,
            endTime: 137.5,
            state: .final,
            localeIdentifier: "en-US",
            confidence: 0.2
        )

        let candidate = try #require(
            TranscriptReviewPolicy.candidate(for: segment, spanIndex: 7, followsInterruption: false)
        )
        #expect(candidate.spanIndex == 7)
        #expect(candidate.startTime == 133.25)
        #expect(candidate.endTime == 137.5)
        #expect(candidate.confidence == 0.2)
    }

    // MARK: - The persisted sidecar

    @Test("Review metadata survives a round trip and states its version")
    func metadataRoundTrip() throws {
        let metadata = SessionReviewMetadata(
            sessionID: UUID(),
            recognizerConfidenceAvailable: true,
            candidates: [
                TranscriptReviewCandidate(
                    spanIndex: 2, startTime: 10, endTime: 12, confidence: 0.3, reasons: [.lowConfidence]
                ),
                TranscriptReviewCandidate(
                    spanIndex: 5, startTime: 30, endTime: 33, confidence: nil, reasons: [.nearInterruption]
                )
            ]
        )

        let decoded = try SessionReviewMetadata.decoded(from: metadata.encoded())

        #expect(decoded == metadata)
        #expect(decoded.schemaVersion == SessionReviewMetadata.currentSchemaVersion)
    }

    @Test("A sidecar from a newer ScribeKit is refused rather than misread")
    func newerSchemaIsRefused() throws {
        let future = SessionReviewMetadata(
            schemaVersion: 99,
            sessionID: UUID(),
            recognizerConfidenceAvailable: false,
            candidates: []
        )
        let data = try future.encoded()

        #expect(throws: SessionReviewError.unsupportedSchemaVersion(99)) {
            try SessionReviewMetadata.decoded(from: data)
        }
    }

    @Test("Damaged sidecar bytes are refused")
    func damagedSidecarIsRefused() {
        #expect(throws: SessionReviewError.malformed) {
            try SessionReviewMetadata.decoded(from: Data("{ not json".utf8))
        }
    }

    @Test("Candidates are offered in transcript order whatever order they were stored in")
    func candidatesAreOrdered() {
        let metadata = SessionReviewMetadata(
            sessionID: UUID(),
            recognizerConfidenceAvailable: true,
            candidates: [
                TranscriptReviewCandidate(spanIndex: 9, startTime: 90, endTime: 91, confidence: 0.1, reasons: [.lowConfidence]),
                TranscriptReviewCandidate(spanIndex: 1, startTime: 10, endTime: 11, confidence: 0.2, reasons: [.lowConfidence]),
                TranscriptReviewCandidate(spanIndex: 4, startTime: 40, endTime: 41, confidence: 0.3, reasons: [.lowConfidence])
            ]
        )

        #expect(metadata.orderedCandidates.map(\.spanIndex) == [1, 4, 9])
    }
}
