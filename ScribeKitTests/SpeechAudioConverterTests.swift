//
//  SpeechAudioConverterTests.swift
//  ScribeKitTests
//

import AVFAudio
import Foundation
import Testing
@testable import ScribeKit

@Suite("SpeechAudioConverter")
struct SpeechAudioConverterTests {

    /// The format the on-device recogniser accepts: 16 kHz mono 16-bit
    /// integer. Captured audio arrives at 48 kHz in 32-bit float, so every
    /// buffer is converted.
    private var recogniserFormat: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
    }

    /// A buffer of the shape ScreenCaptureKit delivers: 48 kHz mono float,
    /// non-interleaved, 20 ms long.
    ///
    /// - Parameters:
    ///   - frames: Frames to carry.
    ///   - channels: Channels to carry.
    ///   - amplitude: The tone's amplitude.
    /// - Returns: The captured buffer.
    private func captured(
        frames: Int = 960,
        channels: Int = 1,
        amplitude: Float = 0.5
    ) -> CapturedPCMBuffer {
        var samples: [Float] = []
        for _ in 0..<channels {
            for frame in 0..<frames {
                samples.append(amplitude * sin(2 * .pi * 440 * Float(frame) / 48_000))
            }
        }
        return CapturedPCMBuffer(
            format: CapturedAudioFormat(
                sampleRate: 48_000,
                channelCount: channels,
                bitsPerChannel: 32,
                isFloat: true,
                isInterleaved: false
            ),
            frameCount: frames,
            presentationTime: 0,
            peakAmplitude: amplitude,
            samples: samples
        )
    }

    @Test("48 kHz float capture becomes the 16 kHz integer audio the recogniser accepts")
    func convertsCaptureFormat() throws {
        let converter = SpeechAudioConverter(outputFormat: recogniserFormat)

        let output = try #require(converter.convert(captured()))

        #expect(output.format.sampleRate == 16_000)
        #expect(output.format.channelCount == 1)
        #expect(output.format.commonFormat == .pcmFormatInt16)
        // 960 frames at 48 kHz is 320 at 16 kHz; the first buffer is a little
        // shorter because the resampler primes its filter on it.
        #expect(output.frameLength <= 320)
        #expect(output.frameLength >= 300)
    }

    @Test("Over a run the converted audio lasts as long as the audio that went in")
    func preservesDuration() {
        let converter = SpeechAudioConverter(outputFormat: recogniserFormat)

        var converted = 0
        for _ in 0..<100 {
            converted += Int(converter.convert(captured())?.frameLength ?? 0)
        }

        // 100 buffers of 960 frames at 48 kHz is two seconds; at 16 kHz that is
        // 32 000 frames, less the resampler's priming on the first buffer.
        #expect(converted > 31_900)
        #expect(converted <= 32_000)
    }

    @Test("The converted audio still carries the signal, not silence")
    func preservesSignal() throws {
        let converter = SpeechAudioConverter(outputFormat: recogniserFormat)

        let output = try #require(converter.convert(captured(amplitude: 0.5)))
        let channel = try #require(output.int16ChannelData)
        var peak: Int16 = 0
        for frame in 0..<Int(output.frameLength) {
            peak = max(peak, abs(channel[0][frame]))
        }

        #expect(peak > 1_000)
    }

    @Test("One converter serves a whole run rather than one per buffer")
    func reusesTheConverter() {
        let converter = SpeechAudioConverter(outputFormat: recogniserFormat)

        for _ in 0..<50 { _ = converter.convert(captured()) }

        #expect(converter.converterCreationCount == 1)
    }

    @Test("A change of capture format builds a new converter rather than mis-reading audio")
    func rebuildsOnFormatChange() {
        let converter = SpeechAudioConverter(outputFormat: recogniserFormat)

        _ = converter.convert(captured())
        _ = converter.convert(captured(channels: 2))

        #expect(converter.converterCreationCount == 2)
    }

    @Test("Stereo capture is folded into the mono audio the recogniser accepts")
    func downmixesToMono() throws {
        let converter = SpeechAudioConverter(outputFormat: recogniserFormat)

        let output = try #require(converter.convert(captured(channels: 2)))

        #expect(output.format.channelCount == 1)
        #expect(output.frameLength >= 300)
    }

    @Test("An empty buffer converts to nothing rather than to a zero-length input")
    func rejectsEmptyBuffer() {
        let converter = SpeechAudioConverter(outputFormat: recogniserFormat)

        #expect(converter.convert(captured(frames: 0)) == nil)
    }
}
