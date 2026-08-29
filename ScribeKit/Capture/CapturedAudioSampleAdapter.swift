//
//  CapturedAudioSampleAdapter.swift
//  ScribeKit
//

import Accelerate
import CoreMedia

/// Adapts Core Media sample buffers into ScribeKit's own audio description.
///
/// This is the only place a `CMSampleBuffer` is read. A buffer is owned by the
/// capture system for the duration of its callback, so everything the rest of
/// ScribeKit needs is extracted while the callback is on the stack and nothing
/// is retained beyond it: no buffer, no block buffer, and no audio data.
nonisolated enum CapturedAudioSampleAdapter {

    /// Describes one audio sample buffer.
    ///
    /// - Parameter sampleBuffer: A buffer delivered by the capture system.
    /// - Returns: A description of the buffer, or `nil` when it carries no
    ///   readable audio format or no frames.
    static func sample(from sampleBuffer: CMSampleBuffer) -> CapturedAudioSample? {
        guard sampleBuffer.isValid,
              let streamDescription = sampleBuffer.formatDescription?.audioStreamBasicDescription
        else { return nil }

        let frameCount = sampleBuffer.numSamples
        guard frameCount > 0 else { return nil }

        let format = CapturedAudioFormat(streamDescription: streamDescription)
        let presentationTime = sampleBuffer.presentationTimeStamp
        return CapturedAudioSample(
            format: format,
            frameCount: frameCount,
            presentationTime: presentationTime.isNumeric ? presentationTime.seconds : nil,
            peakAmplitude: peakAmplitude(in: sampleBuffer, format: format)
        )
    }

    /// Measures the loudest sample in a buffer without copying it.
    ///
    /// Only floating-point audio is measured, because that is what the capture
    /// system delivers and because a normalised magnitude is meaningful there
    /// without knowing an integer scale. The scan reads the buffer in place
    /// and keeps only the resulting number.
    ///
    /// - Parameters:
    ///   - sampleBuffer: The buffer to measure.
    ///   - format: The format the buffer arrived in.
    /// - Returns: The largest absolute value across all channels, or `nil` when
    ///   the buffer is not floating point or could not be read.
    private static func peakAmplitude(
        in sampleBuffer: CMSampleBuffer,
        format: CapturedAudioFormat
    ) -> Float? {
        guard format.isFloat, format.bitsPerChannel == 32 else { return nil }

        return try? sampleBuffer.withAudioBufferList { bufferList, _ in
            var peak: Float = 0
            for buffer in bufferList {
                guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
                let count = vDSP_Length(Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                var channelPeak: Float = 0
                vDSP_maxmgv(data.assumingMemoryBound(to: Float.self), 1, &channelPeak, count)
                peak = max(peak, channelPeak)
            }
            return peak
        }
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
