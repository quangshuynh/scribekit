//
//  RetainedAudioRecorder.swift
//  ScribeKit
//

import Foundation
import Synchronization

/// Streams one meeting's captured audio to one file at a time.
///
/// The recorder is the production ``AudioRetaining`` implementation and the
/// serialised owner of an open recording: the file, the format it was opened
/// for, how much has been written, and whether the recording has failed.
///
/// **Backpressure, stated exactly: there is none, because there is no queue.**
/// A captured buffer is written to the file inside ``consume(_:)``, on the
/// capture system's own serial delivery queue, before that call returns. There
/// is no array, no `AsyncStream` and no dispatched task between capture and the
/// file, so the maximum backlog is the one buffer being written, no audio is
/// ever dropped to keep up, and the memory a meeting costs does not grow with
/// its length. Measured on this Mac, writing 20 ms of 48 kHz mono audio costs
/// about 46 µs as lossless PCM and about 200 µs as AAC, against the 20 ms
/// before the next buffer is due — so the queue this design does not have would
/// have had nothing to hold.
///
/// The cost of that choice is that a writer which could not keep up would slow
/// the delivery queue rather than silently discard audio, and that a failed
/// write ends the recording rather than leaving a hole in the middle of it.
/// Both are deliberate: a retained recording that quietly skips the minutes the
/// disk was busy is worse than one that stops and says so.
///
/// Nothing here deletes. A recording that failed part-way through is closed and
/// left exactly where it is.
nonisolated final class RetainedAudioRecorder: AudioRetaining {

    /// One open recording.
    private struct Recording {
        let url: URL
        let format: CapturedAudioFormat
        let writer: any AudioFileWriting
        var isFailed = false
    }

    private struct State {
        var recording: Recording?
        var failure: AudioRetentionError?

        /// Frames accepted by the current or most recent recording, kept
        /// beside the recording so it still answers after a session closes.
        var frameCount = 0

        /// The sample rate those frames were written at, for the same reason.
        var sampleRate: Double = 0
    }

    let failures: AsyncStream<AudioRetentionError>

    private let creator: any AudioFileCreating
    private let state = Mutex(State())
    private let failureContinuation: AsyncStream<AudioRetentionError>.Continuation

    /// Creates a recorder.
    ///
    /// - Parameter creator: How audio files are created. `AVFAudio` by
    ///   default; tests substitute a double that can fail on demand.
    init(creator: any AudioFileCreating = AVAudioFileCreator()) {
        self.creator = creator
        var continuation: AsyncStream<AudioRetentionError>.Continuation!
        // One failure per recording is all there is to report: the recorder
        // stops writing after the first, so a larger buffer would only hold
        // restatements of a condition already being acted on.
        failures = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation = $0 }
        failureContinuation = continuation
    }

    deinit {
        failureContinuation.finish()
    }

    /// How many frames the current or most recent recording accepted.
    ///
    /// A count, not a copy: the frames are in the file, and nothing here holds
    /// audio.
    var retainedFrameCount: Int { state.withLock { $0.frameCount } }

    /// How much audio those frames are, in seconds.
    var retainedDuration: Double {
        state.withLock { state in
            state.sampleRate > 0 ? Double(state.frameCount) / state.sampleRate : 0
        }
    }

    /// Whether a recording is open and accepting audio.
    var isRecording: Bool { state.withLock { $0.recording != nil } }

    func startSession(
        mode: AudioRetentionMode,
        layout: SessionArtifactLayout,
        format: CapturedAudioFormat
    ) throws -> URL? {
        guard state.withLock({ $0.recording == nil }) else {
            throw AudioRetentionError(.sessionAlreadyInProgress)
        }
        guard mode.retainsAudio, let url = layout.audioURL(for: mode) else {
            state.withLock { $0 = State() }
            return nil
        }

        // Created outside the lock: it reaches the filesystem, and the only
        // thing that could contend for the lock is a capture queue that has
        // not been started yet.
        let writer = try creator.makeWriter(at: url, mode: mode, format: format)
        state.withLock { state in
            state = State(
                recording: Recording(url: url, format: format, writer: writer),
                failure: nil,
                frameCount: 0,
                sampleRate: format.sampleRate
            )
        }
        return url
    }

    func consume(_ buffer: CapturedPCMBuffer) {
        let failure: AudioRetentionError? = state.withLock { state in
            guard let recording = state.recording, !recording.isFailed else { return nil }
            guard buffer.format.sampleRate == recording.format.sampleRate,
                  buffer.format.channelCount == recording.format.channelCount
            else {
                return Self.fail(&state, with: AudioRetentionError(.unsupportedCapturedFormat))
            }

            do {
                try recording.writer.write(buffer)
                state.frameCount += buffer.frameCount
                return nil
            } catch {
                return Self.fail(&state, with: error as? AudioRetentionError
                    ?? AudioRetentionError(.audioWriteFailed, underlying: error))
            }
        }
        guard let failure else { return }
        failureContinuation.yield(failure)
    }

    func finishSession() throws {
        let recording: Recording? = state.withLock { state in
            defer { state.recording = nil }
            return state.recording
        }
        guard let recording else { throw AudioRetentionError(.noSessionInProgress) }

        var closeFailure: Error?
        do { try recording.writer.close() } catch { closeFailure = error }

        // A recording that already failed is reported as that failure rather
        // than as whatever closing made of the wreckage: the reason the file is
        // incomplete is the write that did not happen, and that is the reason
        // worth telling the user.
        if let earlier = state.withLock({ $0.failure }) { throw earlier }
        guard let closeFailure else { return }
        throw closeFailure as? AudioRetentionError
            ?? AudioRetentionError(.audioFinishFailed, underlying: closeFailure)
    }

    func cancelSession() {
        let recording: Recording? = state.withLock { state in
            defer { state.recording = nil }
            return state.recording
        }
        try? recording?.writer.close()
    }

    /// Marks the open recording failed and closes its file, leaving the file
    /// on disk.
    ///
    /// - Parameters:
    ///   - state: The recorder's state, with the lock held.
    ///   - error: What went wrong.
    /// - Returns: The failure, for the caller to publish outside the lock.
    private static func fail(_ state: inout State, with error: AudioRetentionError) -> AudioRetentionError {
        state.recording?.isFailed = true
        state.failure = error
        try? state.recording?.writer.close()
        return error
    }
}
