//
//  TranscriptionAudioInputTests.swift
//  ScribeKitTests
//

import AVFAudio
import CoreMedia
import Foundation
import Speech
import Testing
@testable import ScribeKit

@Suite("TranscriptionAudioInput")
struct TranscriptionAudioInputTests {

    private var recogniserFormat: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
    }

    /// A 20 ms buffer of the shape ScreenCaptureKit delivers.
    private func captured(frames: Int = 960) -> CapturedPCMBuffer {
        CapturedPCMBuffer(
            format: CapturedAudioFormat(
                sampleRate: 48_000,
                channelCount: 1,
                bitsPerChannel: 32,
                isFloat: true,
                isInterleaved: false
            ),
            frameCount: frames,
            presentationTime: 0,
            peakAmplitude: 0.5,
            samples: [Float](repeating: 0.5, count: frames)
        )
    }

    @Test("Buffers are timed from the first frame of the run, not from the capture clock")
    func timesBuffersFromTheStartOfTheRun() async {
        let input = TranscriptionAudioInput(outputFormat: recogniserFormat, capacity: 8)

        for _ in 0..<3 { _ = input.append(captured()) }
        input.close()

        var starts: [Double] = []
        for await element in input.queue {
            starts.append(element.bufferStartTime?.seconds ?? -1)
        }
        #expect(starts == [0, 0.02, 0.04])
    }

    @Test("The backlog stays bounded however far the recogniser falls behind")
    func staysBounded() {
        let input = TranscriptionAudioInput(outputFormat: recogniserFormat, capacity: 10)

        for _ in 0..<1_000 { _ = input.append(captured()) }

        #expect(input.queue.count == 10)
        #expect(input.droppedSeconds > 19)
        #expect(input.droppedSeconds < 20)
    }

    @Test("Dropped audio is reported once it adds up, not once per buffer")
    func reportsDroppedAudioInAggregate() {
        let input = TranscriptionAudioInput(outputFormat: recogniserFormat, capacity: 2)

        var reports: [TranscriptionAudioInput.DroppedAudio] = []
        for _ in 0..<100 {
            if let dropped = input.append(captured()) { reports.append(dropped) }
        }

        #expect(!reports.isEmpty)
        #expect(reports.count < 50)
        #expect(reports.allSatisfy { $0.seconds >= 0.5 })
    }

    @Test("A reported drop says where in the run the audio was lost")
    func reportsWhereAudioWasLost() {
        let input = TranscriptionAudioInput(outputFormat: recogniserFormat, capacity: 1)

        var first: TranscriptionAudioInput.DroppedAudio?
        for _ in 0..<100 where first == nil {
            first = input.append(captured())
        }

        // The first buffer evicted is the one that started the run, and the
        // position comes from the buffer rather than from a clock.
        #expect(first?.startTime == 0)
        #expect((first?.seconds ?? 0) >= 0.5)
    }

    @Test("A drop taken at stop is reported once and then forgotten")
    func unreportedDropIsTakenOnce() {
        let input = TranscriptionAudioInput(outputFormat: recogniserFormat, capacity: 1)
        for _ in 0..<3 { _ = input.append(captured()) }

        let taken = input.takeUnreportedDrop()

        #expect(taken?.seconds ?? 0 > 0)
        #expect(input.takeUnreportedDrop() == nil)
    }

    @Test("Dropping audio leaves a real gap rather than sliding the timeline")
    func droppedAudioLeavesAGap() async {
        let input = TranscriptionAudioInput(outputFormat: recogniserFormat, capacity: 1)

        for _ in 0..<3 { _ = input.append(captured()) }
        input.close()

        var starts: [Double] = []
        for await element in input.queue {
            starts.append(element.bufferStartTime?.seconds ?? -1)
        }
        #expect(starts == [0.04])
    }

    @Test("One converter serves the whole run")
    func reusesOneConverter() {
        let input = TranscriptionAudioInput(outputFormat: recogniserFormat, capacity: 64)

        for _ in 0..<40 { _ = input.append(captured()) }

        #expect(input.converterCreationCount == 1)
    }

    @Test("A closed input accepts no further audio and ends the recogniser's sequence")
    func closedInputStopsAcceptingAudio() async {
        let input = TranscriptionAudioInput(outputFormat: recogniserFormat, capacity: 8)
        _ = input.append(captured())
        input.close()

        _ = input.append(captured())

        var count = 0
        for await _ in input.queue { count += 1 }
        #expect(count == 1)
    }

    @Test("Unreported drops are handed over when the run ends")
    func flushesUnreportedDrops() {
        let input = TranscriptionAudioInput(outputFormat: recogniserFormat, capacity: 1)

        for _ in 0..<5 { _ = input.append(captured()) }

        let remaining = input.takeUnreportedDrop()
        #expect(remaining != nil)
        #expect(input.takeUnreportedDrop() == nil)
    }
}
