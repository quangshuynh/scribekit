//
//  SyntheticSpeechInjector.swift
//  SoakValidation
//

import AVFoundation
import Foundation
import Synchronization
@testable import ScribeKit

/// Replaces the sample values of real captured buffers with synthesised speech.
///
/// This is the harness's one substitution inside the pipeline, and it is
/// deliberately narrow. Buffers arrive from a real `SCStream` through the real
/// ``ScreenCaptureKitAudioCapturer``, on ScreenCaptureKit's own delivery queue,
/// with the frame count, channel layout, sample rate and presentation time the
/// framework produced. Only the numbers inside them are exchanged, for a loop
/// of speech rendered once before capture starts. So the run's **cadence,
/// format and timing are real** and the **sample provenance is synthetic**:
/// nothing here entitles a claim that the captured application said anything.
///
/// It exists because this machine has no application that produces speech on
/// demand, and a recogniser fed silence does no work worth measuring.
/// Substituting at the consumer seam keeps every stage downstream — the media
/// clock, the activity monitor, the recogniser's input queue and the retention
/// writer — the production one, seeing production values in production order.
nonisolated final class SyntheticSpeechInjector: AudioSampleConsuming {

    private let downstream: any AudioSampleConsuming
    private let speech: [Float]
    private let cursor = Mutex(0)

    /// Wraps a downstream consumer.
    ///
    /// - Parameters:
    ///   - downstream: The pipeline the substituted buffers are handed to.
    ///   - speech: Mono samples at the rate captured audio arrives in, looped
    ///     for the length of the run.
    init(downstream: any AudioSampleConsuming, speech: [Float]) {
        self.downstream = downstream
        self.speech = speech
    }

    func consume(_ buffer: CapturedPCMBuffer) {
        guard !speech.isEmpty else { return downstream.consume(buffer) }
        let channels = max(1, buffer.format.channelCount)
        let needed = buffer.frameCount * channels
        var samples = [Float](repeating: 0, count: needed)
        var peak: Float = 0
        let start = cursor.withLock { position -> Int in
            let start = position
            position = (position + buffer.frameCount) % speech.count
            return start
        }
        for frame in 0..<buffer.frameCount {
            let value = speech[(start + frame) % speech.count]
            peak = max(peak, abs(value))
            if buffer.format.isInterleaved {
                for channel in 0..<channels { samples[frame * channels + channel] = value }
            } else {
                for channel in 0..<channels { samples[channel * buffer.frameCount + frame] = value }
            }
        }
        downstream.consume(
            CapturedPCMBuffer(
                format: buffer.format,
                frameCount: buffer.frameCount,
                presentationTime: buffer.presentationTime,
                peakAmplitude: peak,
                samples: samples
            )
        )
    }

    func recordUnreadableSample() {
        downstream.recordUnreadableSample()
    }
}

/// Renders a loop of speech once, before a soak starts.
nonisolated enum SyntheticSpeech {

    /// What the loop says. Deliberately dull, synthetic and non-sensitive: no
    /// real meeting content, no personal data, nothing that would be a problem
    /// to leave in a disposable transcript.
    static let script = """
        This is a synthetic validation passage for a long running capture test. \
        The first section describes the build under measurement and the machine \
        it is running on. The second section reviews the sampling schedule and \
        the artifacts the run is expected to leave behind. The third section \
        restates the pipeline stages in order: capture, recognition, transcript \
        persistence and retained audio. None of this text describes a real \
        meeting, a real person, or a real decision. It exists only so that the \
        speech recogniser has ordinary connected sentences to work on for the \
        whole length of the run, at a steady rate, without repeating a single \
        short phrase often enough to be unrepresentative of continuous speech.
        """

    /// Renders ``script`` and resamples it to mono at a given rate.
    ///
    /// - Parameters:
    ///   - sampleRate: The rate captured audio arrives at, so a substituted
    ///     buffer plays back at the speed its frame count claims.
    ///   - locale: The voice's language.
    /// - Returns: The samples, or an empty array when synthesis produced none.
    static func render(sampleRate: Double, locale: String = "en-US") async -> [Float] {
        let utterance = AVSpeechUtterance(string: script)
        utterance.voice = AVSpeechSynthesisVoice(language: locale)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        let rendered: [AVAudioPCMBuffer] = await withCheckedContinuation { continuation in
            let synthesizer = AVSpeechSynthesizer()
            let collected = Mutex<[AVAudioPCMBuffer]>([])
            let finished = Mutex(false)
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    let done = finished.withLock { state -> Bool in
                        guard !state else { return false }
                        state = true
                        return true
                    }
                    if done {
                        withExtendedLifetime(synthesizer) {}
                        continuation.resume(returning: collected.withLock { $0 })
                    }
                    return
                }
                guard let copy = pcm.copy() as? AVAudioPCMBuffer else { return }
                collected.withLock { $0.append(copy) }
            }
        }

        guard let first = rendered.first else { return [] }
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: first.format, to: target) else { return [] }

        var samples: [Float] = []
        for source in rendered {
            let ratio = sampleRate / source.format.sampleRate
            let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { continue }
            let pending = PendingBuffer(source)
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                guard let next = pending.take() else {
                    status.pointee = .noDataNow
                    return nil
                }
                status.pointee = .haveData
                return next
            }
            guard error == nil, let channel = output.floatChannelData?[0] else { continue }
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        }
        return samples
    }

    /// Hands one rendered buffer to `AVAudioConverter` exactly once.
    ///
    /// The converter's input block is `@Sendable` and `AVAudioPCMBuffer` is
    /// not, but the block runs synchronously inside `convert(to:error:)` on
    /// this thread and the buffer outlives the call, so the box states that
    /// rather than silencing the whole module.
    private final class PendingBuffer: @unchecked Sendable {
        private let value: Mutex<AVAudioPCMBuffer?>

        init(_ buffer: AVAudioPCMBuffer) {
            value = Mutex(buffer)
        }

        func take() -> AVAudioPCMBuffer? {
            value.withLock { buffer in
                defer { buffer = nil }
                return buffer
            }
        }
    }
}
