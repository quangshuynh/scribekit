//
//  SpeechAudioConverter.swift
//  ScribeKit
//

// `AVAudioConverter`'s input block is declared `@Sendable` although Core Audio
// calls it synchronously, on the caller's own thread, before `convert` returns.
// The buffer handed to it never escapes that call.
@preconcurrency import AVFAudio
import Foundation

/// Converts captured audio into the format the recogniser accepts.
///
/// ScreenCaptureKit delivers 48 kHz mono 32-bit float, and the on-device
/// recogniser accepts only 16 kHz (or 8 kHz) 16-bit integer, so a conversion
/// is unavoidable rather than chosen. One `AVAudioConverter` is built the first
/// time audio arrives and reused for every buffer afterwards; it is rebuilt
/// only if the capture format itself changes, which it does not during a run.
///
/// The type is not thread-safe. Its owner uses it from one thread at a time —
/// the capture system's serial delivery queue — so no lock is paid per buffer.
nonisolated final class SpeechAudioConverter {

    /// The format the recogniser asked for.
    let outputFormat: AVAudioFormat

    /// How many converters have been built.
    ///
    /// One per capture format, so a healthy run leaves this at one. It exists
    /// to keep "the converter is not rebuilt per buffer" testable.
    private(set) var converterCreationCount = 0

    private var converter: AVAudioConverter?
    private var inputFormat: CapturedAudioFormat?

    /// Creates a converter targeting one recogniser format.
    ///
    /// - Parameter outputFormat: The format the recogniser accepts.
    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    /// Converts one captured buffer.
    ///
    /// - Parameter buffer: Audio as the capture system delivered it.
    /// - Returns: The same audio in the recogniser's format, or `nil` when the
    ///   capture format cannot be described to Core Audio or the conversion
    ///   failed.
    func convert(_ buffer: CapturedPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameCount > 0,
              let source = Self.sourceBuffer(from: buffer),
              let converter = converter(for: buffer.format, sourceFormat: source.format)
        else { return nil }

        let ratio = outputFormat.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameCount) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        var isSupplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if isSupplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            isSupplied = true
            inputStatus.pointee = .haveData
            return source
        }

        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    /// Returns the converter for a capture format, building it if needed.
    ///
    /// - Parameters:
    ///   - format: The captured format, used to decide whether the existing
    ///     converter still applies.
    ///   - sourceFormat: The same format as Core Audio describes it.
    /// - Returns: A converter, or `nil` when Core Audio refused to build one.
    private func converter(
        for format: CapturedAudioFormat,
        sourceFormat: AVAudioFormat
    ) -> AVAudioConverter? {
        if inputFormat == format, let converter { return converter }
        guard let created = AVAudioConverter(from: sourceFormat, to: outputFormat) else { return nil }
        created.sampleRateConverterQuality = AVAudioQuality.medium.rawValue
        converter = created
        inputFormat = format
        converterCreationCount += 1
        return created
    }

    /// Wraps captured samples in a Core Audio buffer.
    ///
    /// The frames are written straight into the buffer's storage, so the
    /// captured array is read once and no intermediate copy is made.
    /// Interleaved audio occupies one channel pointer with the channels
    /// woven together; non-interleaved audio occupies one pointer per channel.
    ///
    /// - Parameter buffer: The captured audio.
    /// - Returns: A Core Audio buffer holding the same frames, or `nil` when
    ///   the captured format cannot be described.
    private static func sourceBuffer(from buffer: CapturedPCMBuffer) -> AVAudioPCMBuffer? {
        let channelCount = buffer.format.channelCount
        guard channelCount > 0, buffer.samples.count == buffer.frameCount * channelCount,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: buffer.format.sampleRate,
                  channels: AVAudioChannelCount(channelCount),
                  interleaved: buffer.format.isInterleaved
              ),
              let pcm = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(buffer.frameCount)
              ),
              let channels = pcm.floatChannelData
        else { return nil }

        pcm.frameLength = AVAudioFrameCount(buffer.frameCount)
        buffer.samples.withUnsafeBufferPointer { samples in
            guard let base = samples.baseAddress else { return }
            if buffer.format.isInterleaved {
                channels[0].update(from: base, count: samples.count)
            } else {
                for channel in 0..<channelCount {
                    channels[channel].update(
                        from: base.advanced(by: channel * buffer.frameCount),
                        count: buffer.frameCount
                    )
                }
            }
        }
        return pcm
    }
}
