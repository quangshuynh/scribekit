//
//  ScoringTests.swift
//  DiarizationCoreTests
//

import Foundation
import Testing
@testable import DiarizationCore

struct ScoringTests {

    let reference = [
        ReferenceTurn(speaker: "A", start: 0, end: 4),
        ReferenceTurn(speaker: "B", start: 4, end: 8),
    ]

    @Test func perfectHypothesisScoresZeroWhateverTheClusterNumbers() {
        let hypothesis = [
            HypothesisSegment(start: 0, end: 4, cluster: 7, isConfident: true),
            HypothesisSegment(start: 4, end: 8, cluster: 2, isConfident: true),
        ]
        let score = Scoring.score(reference: reference, hypothesis: hypothesis, duration: 8, collar: 0)
        #expect(abs(score.der) < 1e-9)
        #expect(abs(score.referenceSpeech - 8) < 1e-6)
    }

    @Test func oneClusterForTwoSpeakersIsHalfConfusion() {
        let hypothesis = [HypothesisSegment(start: 0, end: 8, cluster: 0, isConfident: true)]
        let score = Scoring.score(reference: reference, hypothesis: hypothesis, duration: 8, collar: 0)
        #expect(abs(score.confusion - 4) < 1e-6)
        #expect(abs(score.der - 0.5) < 1e-6)
        let clusters = Scoring.clusters(reference: reference, hypothesis: hypothesis, duration: 8)
        #expect(clusters.mergedClusters == 1)
        #expect(clusters.splitSpeakers == 0)
    }

    @Test func missAndFalseAlarmAreSeparated() {
        let hypothesis = [
            HypothesisSegment(start: 1, end: 4, cluster: 0, isConfident: true),
            HypothesisSegment(start: 4, end: 9, cluster: 1, isConfident: true),
        ]
        let score = Scoring.score(reference: reference, hypothesis: hypothesis, duration: 10, collar: 0)
        #expect(abs(score.missed - 1) < 1e-6)
        #expect(abs(score.falseAlarm - 1) < 1e-6)
        #expect(abs(score.confusion) < 1e-6)
    }

    @Test func collarExcludesTimeAroundBoundaries() {
        let hypothesis = [
            HypothesisSegment(start: 0, end: 4.2, cluster: 0, isConfident: true),
            HypothesisSegment(start: 4.2, end: 8, cluster: 1, isConfident: true),
        ]
        let strict = Scoring.score(reference: reference, hypothesis: hypothesis, duration: 8, collar: 0)
        let forgiving = Scoring.score(reference: reference, hypothesis: hypothesis, duration: 8, collar: 0.25)
        #expect(abs(strict.confusion - 0.2) < 1e-6)
        #expect(abs(forgiving.confusion) < 1e-6)
    }

    @Test func uncertainSpansAreUnattributedAndLeaveConfidentErrorAlone() {
        let hypothesis = [
            HypothesisSegment(start: 0, end: 4, cluster: 0, isConfident: true),
            HypothesisSegment(start: 4, end: 6, cluster: 0, isConfident: false),
            HypothesisSegment(start: 6, end: 8, cluster: 1, isConfident: true),
        ]
        let score = Scoring.score(reference: reference, hypothesis: hypothesis, duration: 8, collar: 0)
        #expect(abs(score.unattributed - 2) < 1e-6)
        #expect(abs(score.confidentlyAttributed - 6) < 1e-6)
        #expect(abs(score.confidentErrorRate) < 1e-9)
        #expect(abs(score.confusion - 2) < 1e-6, "forced scoring still counts the wrong uncertain span")
    }

    @Test func overlappingReferenceSpeechCountsTheSecondSpeakerAsMissed() {
        let overlapping = [
            ReferenceTurn(speaker: "A", start: 0, end: 4),
            ReferenceTurn(speaker: "B", start: 3, end: 6),
        ]
        let hypothesis = [
            HypothesisSegment(start: 0, end: 4, cluster: 0, isConfident: true),
            HypothesisSegment(start: 4, end: 6, cluster: 1, isConfident: true),
        ]
        let score = Scoring.score(reference: overlapping, hypothesis: hypothesis, duration: 6, collar: 0)
        #expect(abs(score.referenceSpeech - 7) < 1e-6)
        #expect(abs(score.missed - 1) < 1e-6)
    }

    @Test func changePointsMatchWithinToleranceOnlyOnce() {
        let hypothesis = [
            HypothesisSegment(start: 0, end: 4.3, cluster: 0, isConfident: true),
            HypothesisSegment(start: 4.3, end: 6, cluster: 1, isConfident: true),
            HypothesisSegment(start: 6, end: 8, cluster: 0, isConfident: true),
        ]
        let changes = Scoring.changes(reference: reference, hypothesis: hypothesis)
        #expect(changes.referenceChanges == 1)
        #expect(changes.hypothesisChanges == 2)
        #expect(changes.matched == 1)
        #expect(changes.falseChanges == 1)
        #expect(abs(changes.meanAbsoluteError - 0.3) < 1e-9)
    }

    @Test func hungarianFindsTheCheapestAssignment() {
        let cost: [[Double]] = [[4, 1, 3], [2, 0, 5], [3, 2, 2]]
        #expect(Scoring.hungarian(cost) == [1, 0, 2])
    }
}

struct ClusteringTests {

    func windows(_ n: Int) -> [TimeRange] {
        (0..<n).map { TimeRange(start: Double($0), end: Double($0) + 1.5) }
    }

    @Test func separatedVoicesFormTwoClustersNumberedByFirstAppearance() {
        let a: [Float] = [1, 0, 0, 0], b: [Float] = [0, 1, 0, 0]
        let rows = [b, b, a, a, b, a].map { v in v.map { $0 + 0.01 } }
        let configuration = ClusteringConfiguration(mode: .postMeeting, threshold: 0.5, margin: 0.1, minimumClusterEvidence: 0, standardize: false)
        let result = Clustering.assign(embeddings: rows, windows: windows(6), configuration: configuration)
        #expect(result.map(\.cluster) == [0, 0, 1, 1, 0, 1])
        #expect(result.allSatisfy { $0.isConfident })
    }

    @Test func thinlySupportedClustersAreNeverConfident() {
        let a: [Float] = [1, 0, 0], b: [Float] = [0, 1, 0]
        let configuration = ClusteringConfiguration(mode: .postMeeting, threshold: 0.5, margin: 0, minimumClusterEvidence: 2, standardize: false)
        let result = Clustering.assign(embeddings: [a, a, b], windows: windows(3), configuration: configuration)
        #expect(result[2].cluster == 1)
        #expect(!result[2].isConfident)
        #expect(result[0].isConfident)
    }

    @Test func liveModeNeverCallsTheFirstWindowOfANewVoiceConfident() {
        let a: [Float] = [1, 0, 0], b: [Float] = [0, 1, 0]
        let configuration = ClusteringConfiguration(mode: .live, threshold: 0.5, margin: 0, minimumClusterEvidence: 0, standardize: false)
        let result = Clustering.assign(embeddings: [a, a, b, b], windows: windows(4), configuration: configuration)
        #expect(result.map(\.cluster) == [0, 0, 1, 1])
        #expect(result.map(\.isConfident) == [false, true, false, true])
    }

    @Test func segmentsFollowTheNearestWindowAndLeaveGapsUnattributed() {
        let assignments = [
            WindowAssignment(window: TimeRange(start: 0, end: 1), cluster: 0, margin: 1, isConfident: true),
            WindowAssignment(window: TimeRange(start: 2, end: 3), cluster: 1, margin: 1, isConfident: false),
        ]
        let segments = Clustering.segments(from: assignments, duration: 3)
        #expect(segments.count == 2)
        #expect(segments[0].cluster == 0 && segments[0].isConfident)
        #expect(segments[1].cluster == 1 && !segments[1].isConfident)
        #expect(abs(segments[1].start - 2) < 0.011)
    }
}

struct FeatureTests {

    @Test func mfccIsDeterministicAndSeparatesDifferentSpectra() {
        let rate = 16_000.0
        func tone(_ hz: Double) -> [Float] { (0..<16_000).map { Float(sin(2 * .pi * hz * Double($0) / rate)) * 0.3 } }
        let extractor = MFCCExtractor()
        let low = extractor.compute(tone(300)), again = extractor.compute(tone(300)), high = extractor.compute(tone(3_000))
        #expect(low == again)
        #expect(low.count == (16_000 - 400) / 160 + 1)
        #expect(low[50][1] != high[50][1])
    }

    @Test func activityFindsTheLoudPartOnly() {
        var samples = [Float](repeating: 0.001, count: 48_000)
        for i in 16_000..<32_000 { samples[i] = Float(sin(Double(i) * 0.3)) * 0.3 }
        let regions = EnergySpeechActivity().regions(in: samples, sampleRate: 16_000)
        #expect(regions.count == 1)
        #expect(abs(regions[0].start - 1.0) < 0.2)
        #expect(abs(regions[0].end - 2.0) < 0.2)
    }
}
