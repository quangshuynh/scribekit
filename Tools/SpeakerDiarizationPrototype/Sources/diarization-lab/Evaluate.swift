//
//  Evaluate.swift
//  diarization-lab
//

import DiarizationCore
import Foundation

enum ActivitySource: String, CaseIterable {
    /// Reference turns as speech regions: isolates clustering from detection.
    case oracle
    /// The prototype's own energy detector: the end-to-end number.
    case system
}

struct FixtureResult: Codable {
    let fixture: String
    let summary: String
    let score: DiarizationScore
    let changes: ChangeScore
    let clusters: ClusterScore
}

struct ConfigurationResult: Codable {
    let embedding: String
    let mode: String
    let activity: String
    let threshold: Float
    let margin: Float
    let fixtures: [FixtureResult]
    let pooled: DiarizationScore
}

struct Evaluator {
    let fixtures: [(RenderedFixture, [Float])]
    let embeddings: [any WindowEmbedding] = [MFCCStatisticsEmbedding(), AppleAudioFeaturePrintEmbedding()]
    let windowing = AnalysisWindowing()
    let thresholds: [Float] = stride(from: 0.10, through: 1.40, by: 0.05).map { Float($0) }
    let margins: [Float] = [0, 0.02, 0.05, 0.08, 0.12, 0.16, 0.2, 0.25, 0.3]
    let confidentErrorTarget = 0.02

    struct Prepared {
        let windows: [TimeRange]
        let vectors: [[Float]]
    }

    private var cache = [String: Prepared]()

    init(fixtures: [(RenderedFixture, [Float])]) { self.fixtures = fixtures }

    static func oracleRegions(_ turns: [ReferenceTurn]) -> [TimeRange] {
        var merged = [TimeRange]()
        for t in turns.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, t.start <= last.end {
                merged[merged.count - 1] = TimeRange(start: last.start, end: max(last.end, t.end))
            } else {
                merged.append(TimeRange(start: t.start, end: t.end))
            }
        }
        return merged
    }

    mutating func prepared(_ index: Int, _ embedding: any WindowEmbedding, _ activity: ActivitySource) async throws -> Prepared {
        let (fixture, samples) = fixtures[index]
        let key = "\(fixture.name)|\(embedding.name)|\(activity.rawValue)"
        if let hit = cache[key] { return hit }
        let regions = activity == .oracle
            ? Self.oracleRegions(fixture.turns)
            : EnergySpeechActivity().regions(in: samples, sampleRate: fixture.sampleRate)
        let windows = windowing.windows(for: regions)
        let vectors = try await embedding.embed(samples: samples, sampleRate: fixture.sampleRate, windows: windows)
        let result = Prepared(windows: windows, vectors: vectors)
        cache[key] = result
        return result
    }

    mutating func run(
        indices: [Int], embedding: any WindowEmbedding, activity: ActivitySource, configuration: ClusteringConfiguration
    ) async throws -> ConfigurationResult {
        var results = [FixtureResult]()
        var pooled = DiarizationScore()
        for i in indices {
            let (fixture, _) = fixtures[i]
            let prepared = try await prepared(i, embedding, activity)
            let segments = hypothesis(prepared, fixture: fixture, configuration: configuration)
            let score = Scoring.score(reference: fixture.turns, hypothesis: segments, duration: fixture.duration)
            results.append(FixtureResult(
                fixture: fixture.name, summary: fixture.summary, score: score,
                changes: Scoring.changes(reference: fixture.turns, hypothesis: segments),
                clusters: Scoring.clusters(reference: fixture.turns, hypothesis: segments, duration: fixture.duration)
            ))
            pooled.referenceSpeech += score.referenceSpeech
            pooled.missed += score.missed
            pooled.falseAlarm += score.falseAlarm
            pooled.confusion += score.confusion
            pooled.unattributed += score.unattributed
            pooled.confidentlyAttributed += score.confidentlyAttributed
            pooled.confidentConfusion += score.confidentConfusion
        }
        return ConfigurationResult(
            embedding: embedding.name, mode: configuration.mode.rawValue, activity: activity.rawValue,
            threshold: configuration.threshold, margin: configuration.margin, fixtures: results, pooled: pooled
        )
    }

    func hypothesis(_ prepared: Prepared, fixture: RenderedFixture, configuration: ClusteringConfiguration) -> [HypothesisSegment] {
        let assignments = Clustering.assign(embeddings: prepared.vectors, windows: prepared.windows, configuration: configuration)
        return Clustering.segments(from: assignments, duration: fixture.duration)
    }

    /// Chooses the threshold by pooled forced DER on the dev split with oracle
    /// activity, then the smallest margin that keeps dev confident error at or
    /// below the target. The test split plays no part.
    mutating func tune(embedding: any WindowEmbedding, mode: ClusteringConfiguration.Mode) async throws -> (Float, Float, String) {
        let dev = fixtures.indices.filter { fixtures[$0].0.split == "dev" }
        var best: (Float, Double) = (thresholds[0], .infinity)
        for threshold in thresholds {
            let r = try await run(indices: dev, embedding: embedding, activity: .oracle,
                                  configuration: ClusteringConfiguration(mode: mode, threshold: threshold, margin: 0))
            if r.pooled.der < best.1 { best = (threshold, r.pooled.der) }
        }
        var chosenMargin: Float?
        var lowest: (Float, Double) = (margins.last!, .infinity)
        var log = String(format: "threshold %.2f (dev DER %.1f%%); margins:", best.0, best.1 * 100)
        for margin in margins {
            let r = try await run(indices: dev, embedding: embedding, activity: .oracle,
                                  configuration: ClusteringConfiguration(mode: mode, threshold: best.0, margin: margin))
            log += String(format: " %.2f→err %.1f%%/unattr %.0f%%", margin, r.pooled.confidentErrorRate * 100, r.pooled.unattributedRate * 100)
            if chosenMargin == nil, r.pooled.confidentErrorRate <= confidentErrorTarget, r.pooled.confidentlyAttributed > 0 { chosenMargin = margin }
            if r.pooled.confidentErrorRate < lowest.1 { lowest = (margin, r.pooled.confidentErrorRate) }
        }
        let margin = chosenMargin ?? lowest.0
        log += chosenMargin == nil ? " — target not reachable on dev; using lowest-error margin" : ""
        return (best.0, margin, log)
    }
}

// MARK: - Report

enum Report {
    static func pct(_ v: Double) -> String { String(format: "%.1f", v * 100) }

    static func table(_ result: ConfigurationResult) -> String {
        var s = """
        | Fixture | DER | Miss | FA | Conf. | Unattr. | Conf.-err | Spk/Clu | Split/Merge | Changes ref/hit/false | Bound. MAE |
        | --- | ---: | ---: | ---: | ---: | ---: | ---: | :---: | :---: | :---: | ---: |

        """
        for f in result.fixtures {
            s += "| \(f.fixture) | \(pct(f.score.der)) | \(pct(f.score.missRate)) | \(pct(f.score.falseAlarmRate)) | \(pct(f.score.confusionRate)) | \(pct(f.score.unattributedRate)) | \(pct(f.score.confidentErrorRate)) | \(f.clusters.referenceSpeakers)/\(f.clusters.hypothesisClusters) | \(f.clusters.splitSpeakers)/\(f.clusters.mergedClusters) | \(f.changes.referenceChanges)/\(f.changes.matched)/\(f.changes.falseChanges) | \(f.changes.matched > 0 ? String(format: "%.2f s", f.changes.meanAbsoluteError) : "–") |\n"
        }
        let p = result.pooled
        s += "| **pooled** | **\(pct(p.der))** | \(pct(p.missRate)) | \(pct(p.falseAlarmRate)) | \(pct(p.confusionRate)) | \(pct(p.unattributedRate)) | **\(pct(p.confidentErrorRate))** | | | | |\n"
        return s
    }

    static func timeline(reference: [ReferenceTurn], hypothesis: [HypothesisSegment]) -> String {
        var s = "Reference                         Hypothesis\n"
        let refLines = reference.map { String(format: "%6.1f–%6.1f  %@", $0.start, $0.end, $0.speaker) }
        let hypLines = hypothesis.filter { $0.end - $0.start >= 0.1 }.map {
            String(format: "%6.1f–%6.1f  %@", $0.start, $0.end, $0.isConfident ? "Speaker \($0.cluster + 1)" : "uncertain (cluster \($0.cluster + 1))")
        }
        for i in 0..<max(refLines.count, hypLines.count) {
            let left = i < refLines.count ? refLines[i] : ""
            s += left.padding(toLength: 34, withPad: " ", startingAt: 0) + (i < hypLines.count ? hypLines[i] : "") + "\n"
        }
        return s
    }
}

// MARK: - Separability

/// Threshold-free embedding quality: for every pair of single-speaker windows
/// within one recording, is the cosine distance smaller for the same speaker
/// than for different speakers? Reported as the equal error rate of that
/// same/different decision — the rate at which the best possible single
/// threshold calls a same-speaker pair different as often as it calls a
/// different-speaker pair the same. No clustering, no tuning.
struct Separability: Codable {
    let embedding: String
    let fixture: String
    let samePairs: Int
    let differentPairs: Int
    let equalErrorRate: Double
}

extension Evaluator {
    mutating func separability(embedding: any WindowEmbedding, indices: [Int]) async throws -> [Separability] {
        var rows = [Separability]()
        var pooledSame = [Float](), pooledDifferent = [Float]()
        for i in indices {
            let fixture = fixtures[i].0
            let prepared = try await prepared(i, embedding, .oracle)
            var labelled = [(String, [Float])]()
            for (w, v) in zip(prepared.windows, prepared.vectors) {
                let speakers = fixture.turns.filter { $0.start < w.end && $0.end > w.start }
                if speakers.count == 1 { labelled.append((speakers[0].speaker, v)) }
            }
            guard Set(labelled.map(\.0)).count > 1 else { continue }
            let vectors = VectorMath.standardized(labelled.map(\.1)).map(VectorMath.normalized)
            var same = [Float](), different = [Float]()
            for a in 0..<vectors.count {
                for b in (a + 1)..<vectors.count {
                    let d = VectorMath.cosineDistance(vectors[a], vectors[b])
                    if labelled[a].0 == labelled[b].0 { same.append(d) } else { different.append(d) }
                }
            }
            pooledSame += same; pooledDifferent += different
            rows.append(Separability(embedding: embedding.name, fixture: fixture.name, samePairs: same.count, differentPairs: different.count, equalErrorRate: Self.eer(same, different)))
        }
        rows.append(Separability(embedding: embedding.name, fixture: "pooled", samePairs: pooledSame.count, differentPairs: pooledDifferent.count, equalErrorRate: Self.eer(pooledSame, pooledDifferent)))
        return rows
    }

    static func eer(_ same: [Float], _ different: [Float]) -> Double {
        let candidates = (same + different).sorted()
        var best = 1.0, gap = Double.infinity
        let s = same.sorted(), d = different.sorted()
        for t in candidates {
            let falseReject = Double(s.count - s.partitioningIndex { $0 > t }) / Double(s.count)   // same, but farther than t
            let falseAccept = Double(d.partitioningIndex { $0 > t }) / Double(d.count)             // different, but within t
            if abs(falseReject - falseAccept) < gap { gap = abs(falseReject - falseAccept); best = (falseReject + falseAccept) / 2 }
        }
        return best
    }
}

extension Array where Element: Comparable {
    func partitioningIndex(where predicate: (Element) -> Bool) -> Int {
        var low = 0, high = count
        while low < high {
            let mid = (low + high) / 2
            if predicate(self[mid]) { high = mid } else { low = mid + 1 }
        }
        return low
    }
}
