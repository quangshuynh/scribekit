//
//  Timeline.swift
//  DiarizationCore
//

import Foundation

/// One reference speaker turn: who spoke, from when to when, in seconds from
/// the start of the fixture. Ground truth, written by the corpus renderer from
/// the audio it actually placed.
public struct ReferenceTurn: Codable, Equatable, Sendable {
    public let speaker: String
    public let start: Double
    public let end: Double

    public init(speaker: String, start: Double, end: Double) {
        self.speaker = speaker
        self.start = start
        self.end = end
    }
}

/// One stretch of the diarizer's output.
///
/// `cluster` is an anonymous index within one run. It means "acoustically
/// grouped with the other spans carrying this index in this recording" and
/// nothing else. `isConfident` is false when the evidence for the assignment
/// was below the abstention margin; scoring treats such spans either as
/// attributed (forced) or as unattributed (abstaining), and reports both.
public struct HypothesisSegment: Codable, Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let cluster: Int
    public let isConfident: Bool

    public init(start: Double, end: Double, cluster: Int, isConfident: Bool) {
        self.start = start
        self.end = end
        self.cluster = cluster
        self.isConfident = isConfident
    }
}

/// A half-open time range in seconds.
public struct TimeRange: Codable, Equatable, Sendable {
    public let start: Double
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public var duration: Double { max(0, end - start) }
    public var center: Double { (start + end) / 2 }
}
