//
//  Scoring.swift
//  DiarizationCore
//

import Foundation

/// Diarization error and its components for one fixture.
///
/// DER follows NIST md-eval on a 10 ms grid: for each scored frame with
/// `R` reference speakers and `H` hypothesis speakers, of which `C` are
/// correct under the optimal one-to-one cluster→speaker mapping,
/// miss += max(0, R−H), false alarm += max(0, H−R), confusion += min(R, H)−C.
/// DER = (miss + false alarm + confusion) / Σ R. Overlapping reference speech
/// is scored, not excluded. A collar of ``collar`` seconds either side of each
/// reference turn boundary is excluded from scoring, as md-eval's `-c` does.
public struct DiarizationScore: Codable, Sendable {
    public var referenceSpeech: Double = 0
    public var missed: Double = 0
    public var falseAlarm: Double = 0
    public var confusion: Double = 0
    /// Reference speech time with no confident attribution under abstaining
    /// scoring (uncertain spans removed from the hypothesis).
    public var unattributed: Double = 0
    /// Time the hypothesis attributed confidently.
    public var confidentlyAttributed: Double = 0
    /// Confusion inside confidently attributed time only.
    public var confidentConfusion: Double = 0

    public init() {}

    public var der: Double { referenceSpeech > 0 ? (missed + falseAlarm + confusion) / referenceSpeech : 0 }
    public var missRate: Double { ratio(missed) }
    public var falseAlarmRate: Double { ratio(falseAlarm) }
    public var confusionRate: Double { ratio(confusion) }
    public var unattributedRate: Double { ratio(unattributed) }
    /// Of the time the system said "this is cluster k" with confidence, the
    /// share where k mapped to the wrong person. The number that matters most
    /// for a label a reader will believe.
    public var confidentErrorRate: Double { confidentlyAttributed > 0 ? confidentConfusion / confidentlyAttributed : 0 }

    private func ratio(_ v: Double) -> Double { referenceSpeech > 0 ? v / referenceSpeech : 0 }
}

/// Speaker-change detection measured against reference turn changes.
public struct ChangeScore: Codable, Sendable {
    public var referenceChanges = 0
    public var hypothesisChanges = 0
    public var matched = 0
    public var meanAbsoluteError: Double = 0
    public var missed: Int { referenceChanges - matched }
    public var falseChanges: Int { hypothesisChanges - matched }
}

/// Cluster structure: did the system split one voice or merge two.
public struct ClusterScore: Codable, Sendable {
    public var referenceSpeakers = 0
    public var hypothesisClusters = 0
    /// Reference speakers spread over more than one cluster (≥10 % of their time each).
    public var splitSpeakers = 0
    /// Clusters holding more than one reference speaker (≥10 % of their time each).
    public var mergedClusters = 0
}

public enum Scoring {

    public static let step = 0.01

    public static func score(
        reference: [ReferenceTurn],
        hypothesis: [HypothesisSegment],
        duration: Double,
        collar: Double = 0.25
    ) -> DiarizationScore {
        let frames = Int(duration / step)
        let speakers = Array(Set(reference.map(\.speaker))).sorted()
        let refIndex = Dictionary(uniqueKeysWithValues: speakers.enumerated().map { ($1, $0) })
        var ref = Array(repeating: [Int](), count: frames)
        var scored = Array(repeating: true, count: frames)
        for turn in reference {
            for f in frameRange(turn.start, turn.end, frames) { ref[f].append(refIndex[turn.speaker]!) }
            for edge in [turn.start, turn.end] where collar > 0 {
                for f in frameRange(edge - collar, edge + collar, frames) { scored[f] = false }
            }
        }
        var hyp = Array(repeating: -1, count: frames)
        var confident = Array(repeating: false, count: frames)
        for segment in hypothesis {
            for f in frameRange(segment.start, segment.end, frames) {
                hyp[f] = segment.cluster
                confident[f] = segment.isConfident
            }
        }
        let mapping = optimalMapping(ref: ref, hyp: hyp, scored: scored, speakerCount: speakers.count)

        var score = DiarizationScore()
        for f in 0..<frames where scored[f] {
            let r = ref[f].count, h = hyp[f] >= 0 ? 1 : 0
            let correct = h == 1 && mapping[hyp[f]].map { ref[f].contains($0) } == true ? 1 : 0
            score.referenceSpeech += Double(r) * step
            score.missed += Double(max(0, r - h)) * step
            score.falseAlarm += Double(max(0, h - r)) * step
            score.confusion += Double(min(r, h) - correct) * step
            let attributed = h == 1 && confident[f]
            score.unattributed += Double(max(0, r - (attributed ? 1 : 0))) * step
            if attributed && r > 0 {
                score.confidentlyAttributed += step
                if correct == 0 { score.confidentConfusion += step }
            }
        }
        return score
    }

    public static func changes(reference: [ReferenceTurn], hypothesis: [HypothesisSegment], tolerance: Double = 0.5) -> ChangeScore {
        let sortedRef = reference.sorted { $0.start < $1.start }
        var refChanges = [Double]()
        for (a, b) in zip(sortedRef, sortedRef.dropFirst()) where a.speaker != b.speaker {
            refChanges.append((a.end + b.start) / 2)
        }
        var hypChanges = [Double]()
        var previous: HypothesisSegment?
        for segment in hypothesis.sorted(by: { $0.start < $1.start }) {
            if let p = previous, p.cluster != segment.cluster { hypChanges.append((p.end + segment.start) / 2) }
            previous = segment
        }
        var pairs = [(Double, Int, Int)]()
        for (i, r) in refChanges.enumerated() {
            for (j, h) in hypChanges.enumerated() where abs(r - h) <= tolerance { pairs.append((abs(r - h), i, j)) }
        }
        pairs.sort { $0.0 < $1.0 }
        var usedRef = Set<Int>(), usedHyp = Set<Int>()
        var result = ChangeScore(referenceChanges: refChanges.count, hypothesisChanges: hypChanges.count)
        var errorSum = 0.0
        for (error, i, j) in pairs where !usedRef.contains(i) && !usedHyp.contains(j) {
            usedRef.insert(i); usedHyp.insert(j)
            result.matched += 1
            errorSum += error
        }
        result.meanAbsoluteError = result.matched > 0 ? errorSum / Double(result.matched) : 0
        return result
    }

    public static func clusters(reference: [ReferenceTurn], hypothesis: [HypothesisSegment], duration: Double) -> ClusterScore {
        let frames = Int(duration / step)
        let speakers = Array(Set(reference.map(\.speaker))).sorted()
        var ref = Array(repeating: -1, count: frames)
        for turn in reference {
            for f in frameRange(turn.start, turn.end, frames) { ref[f] = speakers.firstIndex(of: turn.speaker)! }
        }
        let clusterCount = (hypothesis.map(\.cluster).max() ?? -1) + 1
        var overlap = Array(repeating: [Double](repeating: 0, count: max(1, clusterCount)), count: speakers.count)
        for segment in hypothesis {
            for f in frameRange(segment.start, segment.end, frames) where ref[f] >= 0 { overlap[ref[f]][segment.cluster] += step }
        }
        var result = ClusterScore(referenceSpeakers: speakers.count, hypothesisClusters: Set(hypothesis.map(\.cluster)).count)
        for s in 0..<speakers.count {
            let total = overlap[s].reduce(0, +)
            if total > 0, overlap[s].filter({ $0 >= 0.1 * total }).count > 1 { result.splitSpeakers += 1 }
        }
        for c in 0..<clusterCount {
            let column = (0..<speakers.count).map { overlap[$0][c] }
            let total = column.reduce(0, +)
            if total > 0, column.filter({ $0 >= 0.1 * total }).count > 1 { result.mergedClusters += 1 }
        }
        return result
    }

    static func frameRange(_ start: Double, _ end: Double, _ frames: Int) -> Range<Int> {
        let a = max(0, Int((start / step).rounded())), b = min(frames, Int((end / step).rounded()))
        return a < b ? a..<b : 0..<0
    }

    /// One-to-one mapping from hypothesis cluster to reference speaker that
    /// maximises overlapping scored time (Hungarian algorithm). Unmapped
    /// clusters are always wrong.
    static func optimalMapping(ref: [[Int]], hyp: [Int], scored: [Bool], speakerCount: Int) -> [Int?] {
        let clusters = (hyp.max() ?? -1) + 1
        guard clusters > 0, speakerCount > 0 else { return Array(repeating: nil, count: max(0, clusters)) }
        var overlap = Array(repeating: [Double](repeating: 0, count: speakerCount), count: clusters)
        for f in 0..<hyp.count where scored[f] && hyp[f] >= 0 {
            for s in ref[f] { overlap[hyp[f]][s] += 1 }
        }
        let n = max(clusters, speakerCount)
        let maxValue = overlap.flatMap { $0 }.max() ?? 0
        var cost = Array(repeating: Array(repeating: maxValue, count: n), count: n)
        for c in 0..<clusters { for s in 0..<speakerCount { cost[c][s] = maxValue - overlap[c][s] } }
        let assignment = hungarian(cost)
        return (0..<clusters).map { c in
            let s = assignment[c]
            return s < speakerCount && overlap[c][s] > 0 ? s : nil
        }
    }

    /// Minimum-cost assignment for a square matrix. Returns the column for each row.
    static func hungarian(_ cost: [[Double]]) -> [Int] {
        let n = cost.count
        var u = [Double](repeating: 0, count: n + 1), v = [Double](repeating: 0, count: n + 1)
        var p = [Int](repeating: 0, count: n + 1), way = [Int](repeating: 0, count: n + 1)
        for i in 1...n {
            p[0] = i
            var j0 = 0
            var minv = [Double](repeating: .infinity, count: n + 1)
            var used = [Bool](repeating: false, count: n + 1)
            repeat {
                used[j0] = true
                let i0 = p[j0]
                var delta = Double.infinity, j1 = 0
                for j in 1...n where !used[j] {
                    let cur = cost[i0 - 1][j - 1] - u[i0] - v[j]
                    if cur < minv[j] { minv[j] = cur; way[j] = j0 }
                    if minv[j] < delta { delta = minv[j]; j1 = j }
                }
                for j in 0...n {
                    if used[j] { u[p[j]] += delta; v[j] -= delta } else { minv[j] -= delta }
                }
                j0 = j1
            } while p[j0] != 0
            repeat {
                let j1 = way[j0]
                p[j0] = p[j1]
                j0 = j1
            } while j0 != 0
        }
        var result = [Int](repeating: 0, count: n)
        for j in 1...n where p[j] > 0 { result[p[j] - 1] = j - 1 }
        return result
    }
}
