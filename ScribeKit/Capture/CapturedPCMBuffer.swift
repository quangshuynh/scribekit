//
//  CapturedPCMBuffer.swift
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

/// One buffer of audio received from the capture system, carried as ScribeKit's
/// own owned pulse-code data.
///
/// The capture system owns its `CMSampleBuffer` only for the duration of the
/// callback that delivers it, so a transcriber that consumes audio on another
/// thread cannot read that memory. The value therefore holds the smallest copy
/// that makes safe asynchronous ownership possible: the frames of one buffer,
/// as floating-point samples, in the layout they arrived in.
///
/// One buffer is 20 ms of audio in practice — a few kilobytes. Buffers are
/// consumed and released as they arrive; nothing in ScribeKit accumulates them,
/// so audio memory stays flat however long a meeting runs.
nonisolated struct CapturedPCMBuffer: Equatable, Sendable {
    /// The format the buffer arrived in.
    let format: CapturedAudioFormat

    /// The number of frames the buffer holds.
    let frameCount: Int

    /// The buffer's presentation timestamp in seconds, when the capture system
    /// supplied a numeric one.
    ///
    /// This is the capture system's own clock, which does not start at zero for
    /// a meeting. Session-relative time is derived by the transcription
    /// pipeline from the frames it has received, not from this value.
    let presentationTime: Double?

    /// The largest absolute sample value in the buffer.
    ///
    /// A normalised magnitude, so the interface can show that real, non-silent
    /// audio is flowing without replaying any of it.
    let peakAmplitude: Float

    /// The frames themselves, `frameCount * format.channelCount` values.
    ///
    /// Non-interleaved audio is stored channel by channel; interleaved audio
    /// frame by frame, matching ``CapturedAudioFormat/isInterleaved``.
    let samples: [Float]

    /// How much time the buffer represents, in seconds.
    var duration: Double {
        format.sampleRate > 0 ? Double(frameCount) / format.sampleRate : 0
    }
}
