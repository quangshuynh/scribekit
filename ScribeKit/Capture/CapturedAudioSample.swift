//
//  CapturedAudioSample.swift
//  ScribeKit
//

import Foundation

/// The format of the audio a capture system actually delivered.
///
/// The values are read from the sample buffers themselves rather than from the
/// configuration that was requested, so the interface and the logs describe
/// what arrived instead of what was asked for.
nonisolated struct CapturedAudioFormat: Hashable, Sendable {
    /// Frames per second, per channel.
    let sampleRate: Double

    /// Number of channels in each frame.
    let channelCount: Int

    /// Bit depth of one sample in one channel.
    let bitsPerChannel: Int

    /// Whether samples are floating point rather than integer.
    let isFloat: Bool

    /// Whether the channels of a frame are stored together in one buffer.
    let isInterleaved: Bool

    /// A short description for the interface and for capture logs.
    var summary: String {
        let channels = channelCount == 1 ? "mono" : channelCount == 2 ? "stereo" : "\(channelCount) ch"
        let encoding = isFloat ? "float\(bitsPerChannel)" : "int\(bitsPerChannel)"
        let layout = isInterleaved ? "interleaved" : "non-interleaved"
        return "\(Int(sampleRate.rounded())) Hz, \(channels), \(encoding), \(layout)"
    }
}

/// One buffer of audio received from the capture system, described rather than
/// carried.
///
/// Interval 4 proves that audio arrives; nothing consumes the samples yet.
/// The value therefore holds a bounded description — format, size, timing and
/// a peak level — and never the pulse-code data itself, so capture memory
/// stays constant no matter how long a meeting runs. The type is the boundary
/// a later transcription consumer extends; it is not a substitute for one.
nonisolated struct CapturedAudioSample: Hashable, Sendable {
    /// The format the buffer arrived in.
    let format: CapturedAudioFormat

    /// The number of frames the buffer holds.
    let frameCount: Int

    /// The buffer's presentation timestamp in seconds, when the capture system
    /// supplied a numeric one.
    let presentationTime: Double?

    /// The largest absolute sample value in the buffer, when it could be read.
    ///
    /// Present only for floating-point audio, where it is a normalised
    /// magnitude. It exists so capture can show that real, non-silent audio is
    /// flowing without retaining or replaying any of it.
    let peakAmplitude: Float?

    /// How much time the buffer represents, in seconds.
    var duration: Double {
        format.sampleRate > 0 ? Double(frameCount) / format.sampleRate : 0
    }
}
