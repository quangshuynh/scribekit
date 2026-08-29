//
//  CapturedAudioSampleAdapterTests.swift
//  ScribeKitTests
//

import AVFAudio
import CoreMedia
import Testing
@testable import ScribeKit

@Suite("CapturedAudioSampleAdapter")
struct CapturedAudioSampleAdapterTests {

    /// Builds a floating-point audio sample buffer of the kind ScreenCaptureKit
    /// delivers, so the adapter is exercised against real Core Media buffers
    /// rather than a stand-in.
    ///
    /// - Parameters:
    ///   - frames: Frames to allocate.
    ///   - sampleRate: Frames per second to describe.
    ///   - channels: Channels per frame.
    ///   - peak: The largest magnitude to write into the buffer.
    ///   - presentationTime: The timestamp to attach.
    /// - Returns: A ready sample buffer, or `nil` when Core Media refused.
    private func makeSampleBuffer(
        frames: Int,
        sampleRate: Double = 48_000,
        channels: AVAudioChannelCount = 1,
        peak: Float = 0.5,
        presentationTime: CMTime = CMTime(value: 480, timescale: 48_000)
    ) -> CMSampleBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels),
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
        else { return nil }

        pcmBuffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<Int(channels) {
            guard let samples = pcmBuffer.floatChannelData?[channel] else { return nil }
            for frame in 0..<frames {
                samples[frame] = frame == frames / 2 ? -peak : peak / 4
            }
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format.formatDescription,
            sampleCount: CMItemCount(frames),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else { return nil }

        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: pcmBuffer.audioBufferList
        ) == noErr else { return nil }

        CMSampleBufferSetDataReady(sampleBuffer)
        return sampleBuffer
    }

    @Test("A float audio buffer is described by its own format, not by a guess")
    func describesFloatBuffer() throws {
        let buffer = try #require(makeSampleBuffer(frames: 1_024))

        let sample = try #require(CapturedAudioSampleAdapter.sample(from: buffer))

        #expect(sample.frameCount == 1_024)
        #expect(sample.format.sampleRate == 48_000)
        #expect(sample.format.channelCount == 1)
        #expect(sample.format.bitsPerChannel == 32)
        #expect(sample.format.isFloat)
        #expect(!sample.format.isInterleaved)
        #expect(sample.presentationTime == 0.01)
        #expect(sample.duration == 1_024 / 48_000.0)
    }

    @Test("The peak is the largest magnitude in the buffer, whatever its sign")
    func measuresPeakMagnitude() throws {
        let buffer = try #require(makeSampleBuffer(frames: 512, peak: 0.8))

        let sample = try #require(CapturedAudioSampleAdapter.sample(from: buffer))

        #expect(sample.peakAmplitude == 0.8)
    }

    @Test("Silence is reported as silence rather than as an unreadable buffer")
    func measuresSilence() throws {
        let buffer = try #require(makeSampleBuffer(frames: 256, peak: 0))

        let sample = try #require(CapturedAudioSampleAdapter.sample(from: buffer))

        #expect(sample.peakAmplitude == 0)
        #expect(sample.frameCount == 256)
    }

    @Test("Multi-channel buffers report every channel")
    func describesStereoBuffer() throws {
        let buffer = try #require(makeSampleBuffer(frames: 480, channels: 2, peak: 0.6))

        let sample = try #require(CapturedAudioSampleAdapter.sample(from: buffer))

        #expect(sample.format.channelCount == 2)
        #expect(sample.peakAmplitude == 0.6)
    }

    @Test("A format summary names the rate, channels and encoding that arrived")
    func summarisesFormat() {
        let format = CapturedAudioFormat(
            sampleRate: 48_000,
            channelCount: 1,
            bitsPerChannel: 32,
            isFloat: true,
            isInterleaved: false
        )

        #expect(format.summary == "48000 Hz, mono, float32, non-interleaved")
    }

    @Test("A buffer carrying no frames is not described as captured audio")
    func rejectsEmptyBuffer() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format.formatDescription,
            sampleCount: 0,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        #expect(status == noErr)

        #expect(CapturedAudioSampleAdapter.sample(from: try #require(sampleBuffer)) == nil)
    }
}
