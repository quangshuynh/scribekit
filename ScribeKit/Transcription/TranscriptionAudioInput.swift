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
    /// - Returns: Seconds of audio dropped that have not been reported yet,
    ///   once they are worth reporting; otherwise `nil`.
    func append(_ buffer: CapturedPCMBuffer) -> Double? {
        state.withLock { state -> Double? in
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
            guard state.unreportedSeconds >= Self.reportingThreshold else { return nil }
            defer { state.unreportedSeconds = 0 }
            return state.unreportedSeconds
        }
    }

    /// Takes any dropped audio that has not been reported yet.
    ///
    /// - Returns: The unreported seconds, or `nil` when there are none.
    func takeUnreportedDrop() -> Double? {
        state.withLock { state in
            guard state.unreportedSeconds > 0 else { return nil }
            defer { state.unreportedSeconds = 0 }
            return state.unreportedSeconds
        }
    }

    /// Stops accepting audio and ends the recogniser's input sequence.
    func close() {
        state.withLock { $0.isOpen = false }
        queue.finish()
    }
}
