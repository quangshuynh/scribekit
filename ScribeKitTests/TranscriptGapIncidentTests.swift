//
//  TranscriptGapIncidentTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@Suite("Transcription gap incidents")
struct TranscriptGapIncidentTests {

    /// One observation of the shape a saturated backlog reports.
    ///
    /// - Parameters:
    ///   - seconds: How much audio was discarded.
    ///   - start: Where the first discarded audio fell.
    ///   - end: Where the last discarded audio ended.
    ///   - closes: Whether the backlog has caught up.
    /// - Returns: The observation.
    private func drop(
        _ seconds: Double,
        from start: Double,
        to end: Double,
        closes: Bool = false
    ) -> DroppedAudio {
        DroppedAudio(seconds: seconds, startTime: start, endTime: end, closesIncident: closes)
    }

    // MARK: - One incident

    @Test("A single short loss is one incident that states a position, not a range")
    func isolatedGapIsAPosition() {
        var incident = TranscriptGapIncident(drop(0.5, from: 120, to: 120.5, closes: true))

        #expect(incident.isClosed)
        #expect(incident.observationCount == 1)
        #expect(incident.lostSeconds == 0.5)
        let gap = incident.gap
        #expect(gap.startTime == 120)
        #expect(gap.endTime == 120.5)
        #expect(gap.duration == 0.5)
        #expect(gap.reason == .audioDropped)
        #expect(!gap.spansRange)
        // A closing report that carries no audio adds none.
        incident.extend(with: DroppedAudio(seconds: 0, closesIncident: true))
        #expect(incident.lostSeconds == 0.5)
        #expect(incident.gap.duration == 0.5)
    }

    @Test("Hundreds of adjacent half-second losses collapse into one incident")
    func adjacentObservationsCollapse() {
        // The pattern a real meeting produced: a report every half second of
        // captured audio, for a little over three and a half minutes.
        var incident = TranscriptGapIncident(drop(0.5, from: 600, to: 600.5))
        for step in 1..<430 {
            let start = 600 + Double(step) * 0.5
            #expect(incident.accepts(drop(0.5, from: start, to: start + 0.5)))
            incident.extend(with: drop(0.5, from: start, to: start + 0.5))
        }

        #expect(incident.observationCount == 430)
        #expect(!incident.isClosed)
        let gap = incident.gap
        #expect(gap.startTime == 600)
        #expect(gap.endTime == 815)
        #expect(abs(gap.duration - 215) < 0.000_001)
        #expect(gap.spansRange)
    }

    @Test("The range affected and the audio lost stay separate quantities")
    func rangeIsNotTheLoss() {
        // Recognition kept transcribing between the losses: three seconds of
        // audio went missing out of a two-minute stretch of trouble.
        var incident = TranscriptGapIncident(drop(1, from: 30, to: 31))
        incident.extend(with: drop(1, from: 90, to: 91))
        incident.extend(with: drop(1, from: 149, to: 150))

        let gap = incident.gap
        #expect(gap.duration == 3)
        #expect(gap.affectedSpan == 120)
        #expect(gap.spansRange)
        // Nothing derives one from the other in either direction.
        #expect(gap.duration != gap.affectedSpan)
    }

    @Test("An observation widens the incident and never narrows it")
    func extendOnlyWidens() {
        var incident = TranscriptGapIncident(drop(0.5, from: 50, to: 50.5))
        incident.extend(with: drop(0.5, from: 40, to: 40.5))
        incident.extend(with: drop(0.5, from: 60, to: 60.5))

        #expect(incident.startTime == 40)
        #expect(incident.endTime == 60.5)
        #expect(abs(incident.lostSeconds - 1.5) < 0.000_001)
    }

    // MARK: - Separate incidents

    @Test("An incident the pipeline closed takes nothing further")
    func closedIncidentAcceptsNothing() {
        var incident = TranscriptGapIncident(drop(0.5, from: 10, to: 10.5))
        #expect(incident.accepts(drop(0.5, from: 11, to: 11.5)))

        incident.extend(with: drop(0.5, from: 11, to: 11.5, closes: true))

        #expect(incident.isClosed)
        // Even audio that fell immediately afterwards belongs to a new
        // incident: the backlog demonstrably caught up in between, which is
        // the whole of the evidence the rule rests on.
        #expect(!incident.accepts(drop(0.5, from: 12, to: 12.5)))
    }

    @Test("A report that only says recognition caught up carries no loss of its own")
    func closingReportWithoutLossIsEmpty() {
        let incident = TranscriptGapIncident(DroppedAudio(seconds: 0, closesIncident: true))

        #expect(incident.isEmpty)
        #expect(incident.isClosed)
    }

    @Test("An observation with no usable position leaves the range it found")
    func positionlessObservationKeepsTheRange() {
        var incident = TranscriptGapIncident(drop(0.5, from: 10, to: 10.5))
        incident.extend(with: DroppedAudio(seconds: 0.5))

        #expect(incident.startTime == 10)
        #expect(incident.endTime == 10.5)
        #expect(abs(incident.lostSeconds - 1) < 0.000_001)
    }

    // MARK: - Rendering decisions

    @Test("A gap narrower than a written second names a moment rather than a range")
    func narrowGapIsNotARange() {
        let gap = TranscriptGap(startTime: 42, endTime: 42.8, duration: 0.8, reason: .audioDropped)
        #expect(!gap.spansRange)
        #expect(abs((gap.affectedSpan ?? 0) - 0.8) < 0.000_001)
    }

    @Test("A gap with no position claims neither a range nor a span")
    func positionlessGapClaimsNothing() {
        let gap = TranscriptGap(duration: 2.35, reason: .recognizerRestarted)
        #expect(!gap.spansRange)
        #expect(gap.affectedSpan == nil)
        #expect(gap.startTime == nil)
        #expect(gap.endTime == nil)
    }
}
