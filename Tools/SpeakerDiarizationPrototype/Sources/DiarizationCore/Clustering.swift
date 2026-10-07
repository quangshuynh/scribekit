//
//  Clustering.swift
//  DiarizationCore
//

import Foundation

/// How the prototype groups windows into anonymous clusters.
public struct ClusteringConfiguration: Sendable, Equatable {
    public enum Mode: String, Sendable {
        /// Agglomerative clustering over the whole recording once it has ended.
        /// Every decision may use every window, earlier or later.
        case postMeeting
        /// Causal leader clustering. Each window is assigned when it arrives,
        /// against what has been seen so far, and the assignment is never
        /// revised — the only behaviour compatible with an append-only
        /// transcript written as the meeting runs.
        case live
    }

    public var mode: Mode
    /// Cosine distance below which two clusters (or a window and a cluster)
    /// are treated as the same voice.
    public var threshold: Float
    /// Required gap between the distance to the assigned cluster and to the
    /// best alternative. Windows below it are reported as uncertain.
    public var margin: Float
    /// Seconds of window evidence a cluster needs before any of its windows is
    /// attributed confidently.
    public var minimumClusterEvidence: Double
    public var standardize: Bool

    public init(mode: Mode, threshold: Float, margin: Float, minimumClusterEvidence: Double = 2.0, standardize: Bool = true) {
        self.mode = mode
        self.threshold = threshold
        self.margin = margin
        self.minimumClusterEvidence = minimumClusterEvidence
        self.standardize = standardize
    }
}

/// Per-window outcome of clustering.
public struct WindowAssignment: Sendable {
    public let window: TimeRange
    public let cluster: Int
    /// Distance to the best alternative minus distance to the assigned
    /// cluster. Larger is better separated; it is *not* a probability.
    public let margin: Float
    public let isConfident: Bool
}

public enum Clustering {

    public static func assign(
        embeddings raw: [[Float]],
        windows: [TimeRange],
        configuration: ClusteringConfiguration
    ) -> [WindowAssignment] {
        guard !raw.isEmpty else { return [] }
        switch configuration.mode {
        case .postMeeting:
            let rows = (configuration.standardize ? VectorMath.standardized(raw) : raw).map(VectorMath.normalized)
            let labels = agglomerative(rows, threshold: configuration.threshold)
            return score(rows: rows, labels: labels, windows: windows, configuration: configuration)
        case .live:
            return leader(raw, windows: windows, configuration: configuration)
        }
    }

    /// Average-linkage agglomerative clustering with Lance–Williams updates.
    /// O(n²) memory and O(n³) time in the number of windows.
    static func agglomerative(_ rows: [[Float]], threshold: Float) -> [Int] {
        let n = rows.count
        var distance = [Float](repeating: 0, count: n * n)
        for i in 0..<n { for j in (i + 1)..<max(i + 1, n) {
            let d = VectorMath.cosineDistance(rows[i], rows[j])
            distance[i * n + j] = d
            distance[j * n + i] = d
        } }
        var active = Array(repeating: true, count: n)
        var size = Array(repeating: 1, count: n)
        var parent = Array(0..<n)
        while true {
            var best = Float.greatestFiniteMagnitude, bi = -1, bj = -1
            for i in 0..<n where active[i] {
                for j in (i + 1)..<max(i + 1, n) where active[j] && distance[i * n + j] < best {
                    best = distance[i * n + j]; bi = i; bj = j
                }
            }
            guard bi >= 0, best < threshold else { break }
            for k in 0..<n where active[k] && k != bi && k != bj {
                let merged = (Float(size[bi]) * distance[bi * n + k] + Float(size[bj]) * distance[bj * n + k]) / Float(size[bi] + size[bj])
                distance[bi * n + k] = merged
                distance[k * n + bi] = merged
            }
            size[bi] += size[bj]
            active[bj] = false
            for k in 0..<n where parent[k] == bj { parent[k] = bi }
        }
        return parent
    }

    /// Margins and confidence for a finished clustering, with clusters
    /// renumbered in order of first appearance.
    static func score(rows: [[Float]], labels: [Int], windows: [TimeRange], configuration: ClusteringConfiguration) -> [WindowAssignment] {
        var order = [Int: Int]()
        for label in labels where order[label] == nil { order[label] = order.count }
        let renumbered = labels.map { order[$0]! }
        let count = order.count
        let dims = rows[0].count
        var sums = Array(repeating: [Float](repeating: 0, count: dims), count: count)
        var evidence = [Double](repeating: 0, count: count)
        for (i, label) in renumbered.enumerated() {
            for d in 0..<dims { sums[label][d] += rows[i][d] }
            evidence[label] += windows[i].duration
        }
        let centroids = sums.map(VectorMath.normalized)
        return renumbered.enumerated().map { i, label in
            let own = VectorMath.cosineDistance(rows[i], centroids[label])
            var alternative = configuration.threshold
            for c in 0..<count where c != label {
                alternative = min(alternative, VectorMath.cosineDistance(rows[i], centroids[c]))
            }
            let margin = alternative - own
            let confident = margin >= configuration.margin && evidence[label] >= configuration.minimumClusterEvidence
            return WindowAssignment(window: windows[i], cluster: label, margin: margin, isConfident: confident)
        }
    }

    /// Causal clustering with running standardisation. Nothing after a
    /// window is used to decide it.
    static func leader(_ raw: [[Float]], windows: [TimeRange], configuration: ClusteringConfiguration) -> [WindowAssignment] {
        let dims = raw[0].count
        var mean = [Float](repeating: 0, count: dims), m2 = [Float](repeating: 0, count: dims)
        var seen: Float = 0
        var sums = [[Float]](), evidence = [Double]()
        var result = [WindowAssignment]()
        for (i, vector) in raw.enumerated() {
            seen += 1
            for d in 0..<dims {
                let delta = vector[d] - mean[d]
                mean[d] += delta / seen
                m2[d] += delta * (vector[d] - mean[d])
            }
            var row = vector
            if configuration.standardize && seen > 1 {
                row = (0..<dims).map { (vector[$0] - mean[$0]) / sqrt(max(1e-8, m2[$0] / seen)) }
            }
            row = VectorMath.normalized(row)
            let distances = sums.map { VectorMath.cosineDistance(row, VectorMath.normalized($0)) }
            let ranked = distances.enumerated().sorted { $0.element < $1.element }
            if let nearest = ranked.first, nearest.element < configuration.threshold {
                let alternative = ranked.count > 1 ? min(configuration.threshold, ranked[1].element) : configuration.threshold
                let margin = alternative - nearest.element
                for d in 0..<dims { sums[nearest.offset][d] += row[d] }
                evidence[nearest.offset] += windows[i].duration
                let confident = margin >= configuration.margin
                    && evidence[nearest.offset] >= configuration.minimumClusterEvidence
                result.append(WindowAssignment(window: windows[i], cluster: nearest.offset, margin: margin, isConfident: confident))
            } else {
                sums.append(row)
                evidence.append(windows[i].duration)
                // A window that opened a new cluster is a hypothesis of a new
                // voice, never a confident attribution.
                result.append(WindowAssignment(window: windows[i], cluster: sums.count - 1, margin: 0, isConfident: false))
            }
        }
        return result
    }

    /// Converts window assignments to contiguous segments on a 10 ms grid.
    /// Each frame takes the assignment of the covering window whose centre is
    /// nearest; frames no window covers are left unattributed.
    public static func segments(from assignments: [WindowAssignment], duration: Double, step: Double = 0.01) -> [HypothesisSegment] {
        let sorted = assignments.sorted { $0.window.start < $1.window.start }
        let frames = Int(duration / step)
        var segments = [HypothesisSegment]()
        var current: (start: Double, cluster: Int, confident: Bool)?
        var lowest = 0
        for f in 0..<frames {
            let t = (Double(f) + 0.5) * step
            while lowest < sorted.count && sorted[lowest].window.end < t { lowest += 1 }
            var best: WindowAssignment?
            var k = lowest
            while k < sorted.count && sorted[k].window.start <= t {
                let w = sorted[k]
                if w.window.end >= t, best == nil || abs(w.window.center - t) < abs(best!.window.center - t) { best = w }
                k += 1
            }
            let label = best.map { ($0.cluster, $0.isConfident) }
            if let c = current, label == nil || label!.0 != c.cluster || label!.1 != c.confident {
                segments.append(HypothesisSegment(start: c.start, end: Double(f) * step, cluster: c.cluster, isConfident: c.confident))
                current = nil
            }
            if current == nil, let label { current = (Double(f) * step, label.0, label.1) }
        }
        if let c = current {
            segments.append(HypothesisSegment(start: c.start, end: Double(frames) * step, cluster: c.cluster, isConfident: c.confident))
        }
        return segments
    }
}
