//
//  MicrophonePCMBufferAdapter.swift
//  ScribeKit
//

import Accelerate
import AVFAudio

/// Adapts the microphone's audio buffers into ScribeKit's own.
///
/// This is the only place an `AVAudioPCMBuffer` from the microphone is read.
/// The audio engine owns its buffer for the duration of the tap callback, so
/// the frames are copied into owned arrays while the callback is on the stack
/// and nothing of the engine's buffer is kept.
///
/// Two things happen on the way, and neither changes what was said:
///
/// - **Channels are mixed to one.** An input device may have several channels,
///   and speech is monaural. Every channel is averaged rather than the first
///   one taken, because which channel of an interface carries the microphone
///   is the device's business, not ScribeKit's.
/// - **Buffers are cut into pieces of at most 20 ms.** The engine delivers a
///   tenth of a second or more at a time, and application capture delivers
///   20 ms. Cutting microphone audio to the same size means the recogniser's
///   bounded backlog holds the same length of audio whichever source filled
///   it, so its capacity, what it costs and when a transcription-gap incident
///   is judged to have ended mean the same thing for both.
///
/// The sample rate is left alone: the recogniser's converter resamples from
/// whatever arrives, and every consumer reads each buffer's own rate.
nonisolated enum MicrophonePCMBufferAdapter {

    /// The longest stretch of audio one adapted buffer holds, in seconds.
    static let maximumBufferDuration = 0.02

    /// Adapts one buffer from the microphone.
    ///
    /// Only 32-bit floating-point audio is adapted, which is what the audio
    /// engine's input node produces. Anything else is reported as unreadable
    /// rather than reinterpreted.
    ///
    /// - Parameters:
    ///   - pcm: The buffer the audio engine delivered.
    ///   - time: When the engine says the buffer began, if it said.
    /// - Returns: The same audio as mono buffers of at most
    ///   ``maximumBufferDuration`` each, in order, or `nil` when the buffer
    ///   holds no frames or samples ScribeKit cannot read.
    static func buffers(from pcm: AVAudioPCMBuffer, at time: AVAudioTime?) -> [CapturedPCMBuffer]? {
        let format = pcm.format
        let frameCount = Int(pcm.frameLength)
        let channelCount = Int(format.channelCount)
        guard frameCount > 0, channelCount > 0, format.sampleRate > 0,
              format.commonFormat == .pcmFormatFloat32,
              let channels = pcm.floatChannelData
        else { return nil }

        let mono = monoSamples(
            channels,
            channelCount: channelCount,
            frameCount: frameCount,
            isInterleaved: format.isInterleaved
        )
        let startTime: Double? = time.flatMap { time in
            time.isSampleTimeValid && time.sampleRate > 0 ? Double(time.sampleTime) / time.sampleRate : nil
        }
        return pieces(of: mono, sampleRate: format.sampleRate, startTime: startTime)
    }

    /// Mixes a buffer's channels down to one.
    ///
    /// - Parameters:
    ///   - channels: The buffer's channel pointers: one per channel when
    ///     non-interleaved, one holding every channel when interleaved.
    ///   - channelCount: How many channels there are.
    ///   - frameCount: How many frames there are.
    ///   - isInterleaved: Whether the channels share one pointer.
    /// - Returns: One sample per frame, the mean of that frame's channels.
    static func monoSamples(
        _ channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameCount: Int,
        isInterleaved: Bool
    ) -> [Float] {
        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channels[0], count: frameCount))
        }
        var mono = [Float](repeating: 0, count: frameCount)
        if isInterleaved {
            let samples = channels[0]
            for frame in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channelCount { sum += samples[frame * channelCount + channel] }
                mono[frame] = sum
            }
        } else {
            for channel in 0..<channelCount {
                let samples = channels[channel]
                for frame in 0..<frameCount { mono[frame] += samples[frame] }
            }
        }
        let scale = 1 / Float(channelCount)
        for frame in 0..<frameCount { mono[frame] *= scale }
        return mono
    }

    /// Cuts mono audio into consecutive buffers of at most
    /// ``maximumBufferDuration``.
    ///
    /// - Parameters:
    ///   - samples: Mono samples, in order.
    ///   - sampleRate: Their rate in frames per second.
    ///   - startTime: The engine's time for the first sample, if known. Each
    ///     piece's presentation time is offset from it by the frames before
    ///     it, so nothing is invented when it is absent.
    /// - Returns: Buffers whose frames, concatenated, are exactly `samples`.
    static func pieces(of samples: [Float], sampleRate: Double, startTime: Double?) -> [CapturedPCMBuffer] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }
        let format = CapturedAudioFormat(
            sampleRate: sampleRate,
            channelCount: 1,
            bitsPerChannel: 32,
            isFloat: true,
            isInterleaved: false
        )
        let piece = max(1, Int((sampleRate * maximumBufferDuration).rounded()))
        var buffers: [CapturedPCMBuffer] = []
        buffers.reserveCapacity((samples.count + piece - 1) / piece)
        var offset = 0
        while offset < samples.count {
            let end = min(offset + piece, samples.count)
            let frames = Array(samples[offset..<end])
            buffers.append(CapturedPCMBuffer(
                format: format,
                frameCount: frames.count,
                presentationTime: startTime.map { $0 + Double(offset) / sampleRate },
                peakAmplitude: vDSP.maximumMagnitude(frames),
                samples: frames
            ))
            offset = end
        }
        return buffers
    }
}
