//
//  CapturedPCMBufferAdapter.swift
//  ScribeKit
//

import Accelerate
import CoreMedia

/// Adapts Core Media sample buffers into ScribeKit's own audio buffers.
///
/// This is the only place a `CMSampleBuffer` is read. A buffer is owned by the
/// capture system for the duration of its callback, so everything the rest of
/// ScribeKit needs is taken while the callback is on the stack: the frames are
/// copied into an owned array and neither the sample buffer, its block buffer
/// nor its memory is retained beyond the call.
nonisolated enum CapturedPCMBufferAdapter {

    /// Adapts one audio sample buffer.
    ///
    /// Only 32-bit floating-point audio is adapted, which is what
    /// ScreenCaptureKit delivers. Anything else is reported as unreadable
    /// rather than reinterpreted, so a stream in an unexpected format is
    /// visible instead of silently mis-decoded.
    ///
    /// - Parameter sampleBuffer: A buffer delivered by the capture system.
    /// - Returns: The buffer's audio, or `nil` when it carries no readable
    ///   format, no frames, or samples ScribeKit cannot read.
    static func buffer(from sampleBuffer: CMSampleBuffer) -> CapturedPCMBuffer? {
        guard sampleBuffer.isValid,
              let streamDescription = sampleBuffer.formatDescription?.audioStreamBasicDescription
        else { return nil }

        let frameCount = sampleBuffer.numSamples
        guard frameCount > 0 else { return nil }

        let format = CapturedAudioFormat(streamDescription: streamDescription)
        guard format.isFloat, format.bitsPerChannel == 32, format.channelCount > 0 else { return nil }
        guard let copied = copy(from: sampleBuffer, count: frameCount * format.channelCount) else {
            return nil
        }

        let presentationTime = sampleBuffer.presentationTimeStamp
        return CapturedPCMBuffer(
            format: format,
            frameCount: frameCount,
            presentationTime: presentationTime.isNumeric ? presentationTime.seconds : nil,
            peakAmplitude: copied.peak,
            samples: copied.samples
        )
    }

    /// Copies a buffer's samples out of the capture system's memory.
    ///
    /// The copy is the smallest one that makes the audio safe to own past the
    /// callback: one pass over the frames of a single buffer, into an array
    /// sized exactly for them. The loudest magnitude is measured during the
    /// same pass, so nothing is read twice.
    ///
    /// - Parameters:
    ///   - sampleBuffer: The buffer to read.
    ///   - count: The number of samples expected across every channel.
    /// - Returns: The samples and their peak magnitude, or `nil` when the
    ///   buffer did not yield exactly `count` samples.
    private static func copy(
        from sampleBuffer: CMSampleBuffer,
        count: Int
    ) -> (samples: [Float], peak: Float)? {
        var samples = [Float](repeating: 0, count: count)
        var peak: Float = 0

        let copied = samples.withUnsafeMutableBufferPointer { destination -> Int in
            guard let base = destination.baseAddress else { return 0 }
            let filled = try? sampleBuffer.withAudioBufferList { bufferList, _ -> Int in
                var offset = 0
                for buffer in bufferList {
                    guard let data = buffer.mData else { return offset }
                    let available = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    guard available > 0, offset + available <= count else { return offset }
                    let source = data.assumingMemoryBound(to: Float.self)
                    base.advanced(by: offset).update(from: source, count: available)
                    var channelPeak: Float = 0
                    vDSP_maxmgv(source, 1, &channelPeak, vDSP_Length(available))
                    peak = max(peak, channelPeak)
                    offset += available
                }
                return offset
            }
            return filled ?? 0
        }

        guard copied == count else { return nil }
        return (samples, peak)
    }
}

nonisolated extension CapturedAudioFormat {
    /// Reads a format from a Core Audio stream description.
    ///
    /// - Parameter streamDescription: The description attached to a sample
    ///   buffer's format description.
    init(streamDescription: AudioStreamBasicDescription) {
        self.init(
            sampleRate: streamDescription.mSampleRate,
            channelCount: Int(streamDescription.mChannelsPerFrame),
            bitsPerChannel: Int(streamDescription.mBitsPerChannel),
            isFloat: streamDescription.mFormatFlags & kAudioFormatFlagIsFloat != 0,
            isInterleaved: streamDescription.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        )
    }
}
