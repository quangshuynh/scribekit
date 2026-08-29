//
//  TranscriptionAudioInput.swift
//  ScribeKit
//

import AVFAudio
import CoreMedia
import Foundation
import Speech
import Synchronization

/// The audio side of a recognition run: conversion, session-relative timing and
/// a bounded backlog.
///
/// Captured buffers are converted on the capture system's delivery queue, which
/// is serial and where 20 ms of audio costs microseconds, and then handed to a
/// ``BoundedAudioQueue`` that the recogniser drains at its own pace. Nothing
/// here waits on the recogniser, so a recogniser that falls behind slows
/// nothing down and grows nothing; it loses the audio it was already behind on,
/// and that loss is reported.
///
/// Each converted buffer carries the time of its first frame, counted from the
/// first frame of the run. Recognised spans are therefore timed against the
/// audio, not against when a result happened to arrive, and audio dropped from
/// the backlog leaves a real gap in that timeline rather than sliding
/// everything after it.
nonisolated final class TranscriptionAudioInput: Sendable {

    /// Audio the backlog discarded, and where in the run it fell.
    ///
    /// The position is the start time of the oldest buffer discarded since the
    /// last report, taken from the buffer itself rather than from a clock, so
    /// a gap is placed where the audio was and not where the report arrived.
    /// It is optional because the position is only as good as the timing the
    /// buffer carried.
    struct DroppedAudio: Equatable, Sendable {
        /// How many seconds of audio were discarded.
        let seconds: Double

        /// Seconds from the start of the run to the first discarded audio.
        let startTime: Double?
    }

    /// Dropped audio worth reporting, in seconds.
    ///
    /// Losses are accumulated and reported once they add up, so a recogniser
    /// that is badly behind produces a readable statement rather than one
    /// event per buffer.
    private static let reportingThreshold = 0.5

    /// The backlog the recogniser reads from.
    let queue: BoundedAudioQueue<AnalyzerInput>

    private struct State {
        var converter: SpeechAudioConverter
        var elapsed: CMTime = .zero
        var droppedSeconds: Double = 0
        var unreportedSeconds: Double = 0
        var unreportedStart: Double?
        var isOpen = true
    }

    private let state: Mutex<State>
    private let outputSampleRate: Double

    /// Creates an input for one recognition run.
    ///
    /// - Parameters:
    ///   - outputFormat: The format the recogniser accepts.
    ///   - capacity: How many converted buffers may wait for the recogniser.
    init(outputFormat: AVAudioFormat, capacity: Int) {
        queue = BoundedAudioQueue(capacity: capacity)
        outputSampleRate = outputFormat.sampleRate
        state = Mutex(State(converter: SpeechAudioConverter(outputFormat: outputFormat)))
    }

    /// Total audio lost to a full backlog during this run, in seconds.
    var droppedSeconds: Double { state.withLock { $0.droppedSeconds } }

    /// How many converters the run has built. One, unless the capture format
    /// changed mid-run.
    var converterCreationCount: Int { state.withLock { $0.converter.converterCreationCount } }

    /// Converts a captured buffer and offers it to the recogniser.
    ///
    /// Called on the capture system's delivery queue. It never waits and never
    /// allocates beyond one converted buffer.
    ///
    /// - Parameter buffer: Audio as the capture system delivered it.
    /// - Returns: The unreported drop, once it is worth reporting: how many
    ///   seconds were lost and where the loss began, in seconds from the start
    ///   of the run. `nil` when there is nothing worth reporting.
    func append(_ buffer: CapturedPCMBuffer) -> DroppedAudio? {
        state.withLock { state -> DroppedAudio? in
            guard state.isOpen else { return nil }
            guard let converted = state.converter.convert(buffer) else { return nil }

            let startTime = state.elapsed
            state.elapsed = CMTimeAdd(
                state.elapsed,
                CMTime(
                    value: CMTimeValue(buffer.frameCount),
                    timescale: CMTimeScale(buffer.format.sampleRate.rounded())
                )
            )

            let evicted = queue.append(AnalyzerInput(buffer: converted, bufferStartTime: startTime))
            guard let evicted, outputSampleRate > 0 else { return nil }

            let lost = Double(evicted.buffer.frameLength) / outputSampleRate
            state.droppedSeconds += lost
            state.unreportedSeconds += lost
            if state.unreportedStart == nil, let evictedStart = evicted.bufferStartTime, evictedStart.isNumeric {
                state.unreportedStart = evictedStart.seconds
            }
            guard state.unreportedSeconds >= Self.reportingThreshold else { return nil }
            return Self.takeDrop(from: &state)
        }
    }

    /// Takes any dropped audio that has not been reported yet.
    ///
    /// - Returns: The unreported drop, or `nil` when there is none.
    func takeUnreportedDrop() -> DroppedAudio? {
        state.withLock { state in
            guard state.unreportedSeconds > 0 else { return nil }
            return Self.takeDrop(from: &state)
        }
    }

    /// Empties the unreported drop and returns it.
    ///
    /// - Parameter state: The input's state, with the lock held.
    /// - Returns: The drop that was pending.
    private static func takeDrop(from state: inout State) -> DroppedAudio {
        defer {
            state.unreportedSeconds = 0
            state.unreportedStart = nil
        }
        return DroppedAudio(seconds: state.unreportedSeconds, startTime: state.unreportedStart)
    }

    /// Stops accepting audio and ends the recogniser's input sequence.
    func close() {
        state.withLock { $0.isOpen = false }
        queue.finish()
    }
}
