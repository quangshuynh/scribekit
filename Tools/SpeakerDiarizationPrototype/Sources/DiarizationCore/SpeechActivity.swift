//
//  SpeechActivity.swift
//  DiarizationCore
//

import Accelerate
import Foundation

/// An adaptive energy detector for where speech may be.
///
/// Deliberately simple: anything louder than the recording's own noise floor
/// by enough is "activity". It cannot tell speech from music, and the
/// evaluation counts what that costs as false alarm rather than hiding it.
/// The diarizer can also be run against the reference speech regions
/// ("oracle activity") so that clustering quality is measured separately from
/// activity detection, which is standard practice in diarization reporting.
public struct EnergySpeechActivity: Sendable {
    public var minimumRiseDecibels: Float = 8
    public var hangover: Double = 0.15
    public var bridgeGap: Double = 0.3
    public var minimumRegion: Double = 0.2

    public init() {}

    public func regions(in samples: [Float], sampleRate: Double) -> [TimeRange] {
        let frame = Int(sampleRate * 0.02), hop = Int(sampleRate * 0.01)
        guard samples.count > frame else { return [] }
        let count = (samples.count - frame) / hop + 1
        var levels = [Float](repeating: 0, count: count)
        samples.withUnsafeBufferPointer { buffer in
            for i in 0..<count {
                let slice = UnsafeBufferPointer(rebasing: buffer[(i * hop)..<(i * hop + frame)])
                levels[i] = 10 * log10(vDSP.meanSquare(slice) + 1e-10)
            }
        }
        let sorted = levels.sorted()
        let floor = sorted[Int(Double(count) * 0.1)]
        let peak = sorted[min(count - 1, Int(Double(count) * 0.95))]
        let threshold = floor + max(minimumRiseDecibels, 0.3 * (peak - floor))

        var raw = [TimeRange]()
        var openAt: Int?
        for i in 0..<count {
            if levels[i] > threshold {
                if openAt == nil { openAt = i }
            } else if let start = openAt {
                raw.append(TimeRange(start: Double(start * hop) / sampleRate, end: Double(i * hop + frame) / sampleRate))
                openAt = nil
            }
        }
        if let start = openAt {
            raw.append(TimeRange(start: Double(start * hop) / sampleRate, end: Double(samples.count) / sampleRate))
        }

        let total = Double(samples.count) / sampleRate
        var merged = [TimeRange]()
        for region in raw {
            let padded = TimeRange(start: max(0, region.start - hangover), end: min(total, region.end + hangover))
            if let last = merged.last, padded.start - last.end <= bridgeGap {
                merged[merged.count - 1] = TimeRange(start: last.start, end: max(last.end, padded.end))
            } else {
                merged.append(padded)
            }
        }
        return merged.filter { $0.duration >= minimumRegion }
    }
}

/// Splits activity regions into the analysis windows embeddings are taken over.
public struct AnalysisWindowing: Sendable {
    public var length: Double = 1.5
    public var hop: Double = 0.75
    public var minimum: Double = 0.3

    public init(length: Double = 1.5, hop: Double = 0.75) {
        self.length = length
        self.hop = hop
    }

    /// Windows never cross a region boundary, so one window cannot straddle a
    /// silence between two people. A region shorter than ``length`` becomes a
    /// single shorter window, which is exactly the short-interjection case
    /// where the evidence is weakest.
    public func windows(for regions: [TimeRange]) -> [TimeRange] {
        var result = [TimeRange]()
        for region in regions where region.duration >= minimum {
            if region.duration <= length {
                result.append(region)
                continue
            }
            var start = region.start
            while start + length < region.end {
                result.append(TimeRange(start: start, end: start + length))
                start += hop
            }
            result.append(TimeRange(start: region.end - length, end: region.end))
        }
        return result
    }
}
