//
//  Embedding.swift
//  DiarizationCore
//

import Accelerate
import AVFAudio
import CoreML
import CreateMLComponents
import Foundation

/// Turns analysis windows into fixed-length vectors that clustering compares.
///
/// Both implementations are Apple-native: nothing is downloaded, nothing is
/// bundled, and neither vector is retained once a run ends. Neither is a
/// *speaker* embedding in the sense the diarization literature means — a
/// network trained to make the same voice close and different voices far.
/// Measuring how far that gap matters is the point of the prototype.
public protocol WindowEmbedding: Sendable {
    var name: String { get }
    func embed(samples: [Float], sampleRate: Double, windows: [TimeRange]) async throws -> [[Float]]
}

/// Mean and standard deviation of c1…c19 over each window: 38 dimensions.
///
/// Per-utterance statistics of MFCCs are the pre-neural speaker feature.
/// Cepstral mean normalisation over the whole recording removes a fixed
/// channel colouring, which is an offline step; the live variant normalises
/// only by what it has seen so far.
public struct MFCCStatisticsEmbedding: WindowEmbedding {
    public let name = "mfcc-stats"
    public init() {}

    public func embed(samples: [Float], sampleRate: Double, windows: [TimeRange]) async throws -> [[Float]] {
        let extractor = MFCCExtractor(sampleRate: sampleRate)
        let cepstra = extractor.compute(samples)
        guard !cepstra.isEmpty else { return windows.map { _ in [Float](repeating: 0, count: 38) } }
        let dims = extractor.coefficients
        return windows.map { window in
            let first = max(0, Int((window.start * sampleRate - Double(extractor.frameLength) / 2) / Double(extractor.hop)))
            let last = min(cepstra.count - 1, Int((window.end * sampleRate - Double(extractor.frameLength) / 2) / Double(extractor.hop)))
            guard last > first else { return [Float](repeating: 0, count: 2 * (dims - 1)) }
            var mean = [Float](repeating: 0, count: dims - 1)
            var square = [Float](repeating: 0, count: dims - 1)
            for f in first...last {
                for d in 1..<dims {
                    mean[d - 1] += cepstra[f][d]
                    square[d - 1] += cepstra[f][d] * cepstra[f][d]
                }
            }
            let n = Float(last - first + 1)
            let m = mean.map { $0 / n }
            let s = zip(square, m).map { sqrt(max(0, $0 / n - $1 * $1)) }
            return m + s
        }
    }
}

/// Apple's general-purpose sound embedding from CreateMLComponents.
///
/// `AudioFeaturePrint` is the feature extractor behind Create ML's sound
/// classifier. It is on-device and ships with macOS, but it was trained to
/// tell *kinds of sound* apart (speech from a dog from a door), not one voice
/// from another. The prints it emits over the window are averaged.
public struct AppleAudioFeaturePrintEmbedding: WindowEmbedding {
    public let name = "audio-featureprint"
    public let printWindow: Double
    public init(printWindow: Double = 0.975) { self.printWindow = printWindow }

    public func embed(samples: [Float], sampleRate: Double, windows: [TimeRange]) async throws -> [[Float]] {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let chunk = Int(sampleRate * 0.5)
        var features = [TemporalFeature<AVAudioPCMBuffer>]()
        var offset = 0
        while offset < samples.count {
            let n = min(chunk, samples.count - offset)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
            buffer.frameLength = AVAudioFrameCount(n)
            samples.withUnsafeBufferPointer { src in
                buffer.floatChannelData![0].update(from: src.baseAddress! + offset, count: n)
            }
            let id = TemporalSegmentIdentifier(source: "fixture", range: offset..<(offset + n), timescale: Int(sampleRate))
            features.append(TemporalFeature(id: id, feature: buffer))
            offset += n
        }
        let stream = AsyncStream<TemporalFeature<AVAudioPCMBuffer>> { continuation in
            for feature in features { continuation.yield(feature) }
            continuation.finish()
        }
        let sequence = AnyTemporalSequence(stream, count: features.count)
        let printer = AudioFeaturePrint(windowDuration: printWindow, overlapFactor: 0.5)
        var prints = [(center: Double, vector: [Float])]()
        for try await item in try printer.applied(to: sequence) {
            let range = item.id.rangeInSeconds
            prints.append(((range.lowerBound + range.upperBound) / 2, item.feature.scalars))
        }
        let dims = prints.first?.vector.count ?? 0
        return windows.map { window in
            var inside = prints.filter { $0.center >= window.start && $0.center <= window.end }
            if inside.isEmpty, let nearest = prints.min(by: { abs($0.center - window.center) < abs($1.center - window.center) }) {
                inside = [nearest]
            }
            guard !inside.isEmpty else { return [Float](repeating: 0, count: dims) }
            var sum = [Float](repeating: 0, count: dims)
            for p in inside { vDSP.add(sum, p.vector, result: &sum) }
            return vDSP.divide(sum, Float(inside.count))
        }
    }
}

/// Vector helpers shared by clustering and scoring.
public enum VectorMath {
    public static func normalized(_ v: [Float]) -> [Float] {
        let norm = sqrt(vDSP.sumOfSquares(v))
        return norm > 0 ? vDSP.divide(v, norm) : v
    }

    /// Cosine distance between two already-normalised vectors.
    public static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        1 - vDSP.dot(a, b)
    }

    /// Z-scores each dimension over the given rows. Offline only: it uses
    /// every window in the recording, including later ones.
    public static func standardized(_ rows: [[Float]]) -> [[Float]] {
        guard let dims = rows.first?.count, rows.count > 1 else { return rows }
        var mean = [Float](repeating: 0, count: dims), square = [Float](repeating: 0, count: dims)
        for row in rows {
            vDSP.add(mean, row, result: &mean)
            vDSP.add(square, vDSP.square(row), result: &square)
        }
        let n = Float(rows.count)
        mean = vDSP.divide(mean, n)
        let std = (0..<dims).map { sqrt(max(1e-8, square[$0] / n - mean[$0] * mean[$0])) }
        return rows.map { row in (0..<dims).map { (row[$0] - mean[$0]) / std[$0] } }
    }
}
