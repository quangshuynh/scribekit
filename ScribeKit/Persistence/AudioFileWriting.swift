//
//  AudioFileWriting.swift
//  ScribeKit
//

import AVFAudio
import Foundation
import Synchronization

/// One open audio file a meeting's captured frames are appended to.
///
/// Narrow for the same reason ``TranscriptFileAppending`` is: the policy above
/// it — when a file is opened, what a failure means for the meeting, what
/// happens to a partial recording — is then testable against a double that
/// fails on demand, while the production implementation stays the only place
/// that knows what a container or a codec is.
nonisolated protocol AudioFileWriting: Sendable {

    /// Appends one captured buffer to the file.
    ///
    /// Called on the capture system's delivery queue, so implementations write
    /// incrementally and hold nothing: a multi-hour meeting must cost the same
    /// memory as a one-minute one.
    ///
    /// - Parameter buffer: Audio as the capture system delivered it.
    /// - Throws: ``AudioRetentionError`` when the frames cannot be prepared or
    ///   the write fails.
    func write(_ buffer: CapturedPCMBuffer) throws

    /// Finalises and closes the file.
    ///
    /// - Throws: ``AudioRetentionError/Reason/audioFinishFailed`` when the
    ///   file could not be completed. The file is left on disk either way.
    func close() throws
}

/// Creates the audio file a retention mode calls for.
///
/// Separated from the writer so a session can be opened — and refused — in a
/// test without a codec, and so the one place that turns
/// ``AudioRetentionMode`` into container and encoder settings is a single
/// function rather than a decision spread across the pipeline.
nonisolated protocol AudioFileCreating: Sendable {

    /// Creates and opens an audio file.
    ///
    /// - Parameters:
    ///   - url: Where to create the file.
    ///   - mode: What the user chose to keep. ``AudioRetentionMode/none`` is
    ///     not a file and is refused.
    ///   - format: The format the file will hold.
    /// - Returns: The open file.
    /// - Throws: ``AudioRetentionError`` when the format cannot be described or
    ///   the file cannot be created.
    func makeWriter(
        at url: URL,
        mode: AudioRetentionMode,
        format: CapturedAudioFormat
    ) throws -> any AudioFileWriting
}

/// Audio files as `AVFAudio` writes them.
///
/// Two formats, both native and both written incrementally by the same API:
///
/// - ``AudioRetentionMode/raw`` is linear PCM in a CAF container, in exactly
///   the sample rate, channel count and 32-bit float samples capture delivered,
///   so the file is the captured audio rather than a re-encoding of it. CAF is
///   chosen over WAV because a WAV header addresses its data with 32 bits: at
///   the 48 kHz mono float32 ScreenCaptureKit delivers, a meeting passes WAV's
///   four-gigabyte ceiling after about six hours, and ScribeKit is built for
///   long meetings. CAF has no such limit, and — measured, not assumed — a CAF
///   left unclosed by a process that was killed still opens and reports its
///   real duration.
/// - ``AudioRetentionMode/compressed`` is AAC in an MPEG-4 container at
///   ``compressedBitRate``, which is a practical size for a multi-hour meeting
///   of speech. The encoder is `AVAudioFile`'s own, built once when the file is
///   created and reused for every buffer; ScribeKit does not build a converter
///   per buffer and does not accumulate encoded data of its own.
nonisolated struct AVAudioFileCreator: AudioFileCreating {

    /// The bit rate compressed recordings are encoded at.
    ///
    /// 64 kbit/s mono AAC: measured at about 26 MB per hour against roughly
    /// 660 MB per hour for the same audio as raw float PCM. It is fixed rather
    /// than offered as a setting, because a meeting recording has one job and a
    /// bit-rate picker is a choice without a question behind it.
    static let compressedBitRate = 64_000

    /// Creates the system-backed creator.
    init() {}

    func makeWriter(
        at url: URL,
        mode: AudioRetentionMode,
        format: CapturedAudioFormat
    ) throws -> any AudioFileWriting {
        guard let settings = Self.settings(for: mode, format: format) else {
            throw AudioRetentionError(.cannotCreateAudioFile)
        }
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioRetentionError(.unsupportedCapturedFormat)
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw AudioRetentionError(.cannotCreateAudioFile, underlying: error)
        }
        return AVAudioFileWriter(file: file, url: url)
    }

    /// The container and encoder settings a retention mode is written with.
    ///
    /// - Parameters:
    ///   - mode: What the user chose to keep.
    ///   - format: The captured format the file will hold.
    /// - Returns: Settings for `AVAudioFile`, or `nil` when the mode keeps no
    ///   audio and there is therefore no file to describe.
    private static func settings(
        for mode: AudioRetentionMode,
        format: CapturedAudioFormat
    ) -> [String: Any]? {
        switch mode {
        case .none:
            nil
        case .raw:
            [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: true
            ]
        case .compressed:
            [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: compressedBitRate
            ]
        }
    }
}

/// An audio file backed by an open `AVAudioFile`.
///
/// The file and the one buffer frames are copied through are held under a mutex
/// because neither is `Sendable` and both outlive the call that created them.
/// In practice the capture system's serial delivery queue is the only thread
/// that writes, so the lock is never contended; it is here so the writer is
/// safe to hand across isolation without an unchecked claim.
///
/// One `AVAudioPCMBuffer` is allocated for the first captured buffer and reused
/// for every buffer afterwards, so a meeting's writing allocates a fixed amount
/// however long it runs.
nonisolated final class AVAudioFileWriter: AudioFileWriting {

    private struct Open {
        var file: AVAudioFile?
        var scratch: AVAudioPCMBuffer?
    }

    private let state: Mutex<Open>
    private let url: URL

    /// Wraps a file opened for writing.
    ///
    /// - Parameters:
    ///   - file: A file opened for writing with a float32 processing format.
    ///   - url: Where the file is, so closing can confirm it reads back.
    init(file: AVAudioFile, url: URL) {
        state = Mutex(Open(file: file, scratch: nil))
        self.url = url
    }

    func write(_ buffer: CapturedPCMBuffer) throws {
        try state.withLock { state in
            guard let file = state.file else { throw AudioRetentionError(.noSessionInProgress) }
            let pcm = try Self.prepare(buffer, format: file.processingFormat, scratch: &state.scratch)
            do {
                try file.write(from: pcm)
            } catch {
                throw AudioRetentionError(.audioWriteFailed, underlying: error)
            }
        }
    }

    /// Closes the file and confirms it can be opened again.
    ///
    /// `AVAudioFile` finalises a container when the last reference to it goes
    /// away, and has no closing call that could report a problem. Reading the
    /// finished file's header back is therefore how this writer finds out
    /// whether the file it just wrote is a file at all — cheap, since only the
    /// header is read, and the difference between a recording and a broken one.
    func close() throws {
        let hadFile: Bool = state.withLock { state in
            defer {
                state.file = nil
                state.scratch = nil
            }
            return state.file != nil
        }
        guard hadFile else { return }

        do {
            _ = try AVAudioFile(forReading: url)
        } catch {
            throw AudioRetentionError(.audioFinishFailed, underlying: error)
        }
    }

    /// Copies captured frames into a buffer the file can write.
    ///
    /// The scratch buffer is reused whenever it is large enough, so the steady
    /// state of a meeting allocates nothing per buffer. Interleaved captured
    /// audio is separated into channels here rather than converted or
    /// resampled: this is a copy, not a transformation, and the samples that
    /// reach the file are the samples that arrived.
    ///
    /// - Parameters:
    ///   - buffer: Audio as the capture system delivered it.
    ///   - format: The file's processing format.
    ///   - scratch: The reusable buffer, replaced when a larger one is needed.
    /// - Returns: A buffer holding the captured frames.
    /// - Throws: ``AudioRetentionError/Reason/unsupportedCapturedFormat`` when
    ///   the buffer does not fit the file's format, or
    ///   ``AudioRetentionError/Reason/audioConversionFailed`` when the copy
    ///   buffer cannot be made.
    private static func prepare(
        _ buffer: CapturedPCMBuffer,
        format: AVAudioFormat,
        scratch: inout AVAudioPCMBuffer?
    ) throws -> AVAudioPCMBuffer {
        let channelCount = Int(format.channelCount)
        guard buffer.frameCount > 0,
              buffer.format.channelCount == channelCount,
              buffer.format.sampleRate == format.sampleRate,
              buffer.samples.count == buffer.frameCount * channelCount
        else { throw AudioRetentionError(.unsupportedCapturedFormat) }

        let pcm: AVAudioPCMBuffer
        if let existing = scratch, existing.frameCapacity >= AVAudioFrameCount(buffer.frameCount) {
            pcm = existing
        } else {
            guard let created = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(buffer.frameCount)
            ) else { throw AudioRetentionError(.audioConversionFailed) }
            scratch = created
            pcm = created
        }

        guard let channels = pcm.floatChannelData else {
            throw AudioRetentionError(.audioConversionFailed)
        }
        pcm.frameLength = AVAudioFrameCount(buffer.frameCount)
        buffer.samples.withUnsafeBufferPointer { samples in
            guard let base = samples.baseAddress else { return }
            if buffer.format.isInterleaved, channelCount > 1 {
                for channel in 0..<channelCount {
                    for frame in 0..<buffer.frameCount {
                        channels[channel][frame] = base[frame * channelCount + channel]
                    }
                }
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
