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
///
/// Losses are published as observations of a continuing condition rather than
/// as separate gaps. A recogniser that is behind keeps losing audio until it is
/// not, so what the input reports is how much it has lost so far and —
/// separately, and from the backlog's own behaviour rather than from a clock —
/// the moment the backlog has caught up and the run of losses is over. Turning
/// a run of observations back into the single incident they describe is
/// ``TranscriptGapIncident``'s job, not this one's.
nonisolated final class TranscriptionAudioInput: Sendable {

    /// How much unreported loss is worth publishing on its own.
    ///
    /// Losses are accumulated and reported once they add up, so a recogniser
    /// that is badly behind produces a readable statement rather than one
    /// event per buffer. It is a reporting rate, not an incident boundary:
    /// what separates one gap incident from the next is
    /// ``DroppedAudio/closesIncident``.
    private static let reportingThreshold = 0.5

    /// The backlog the recogniser reads from.
    let queue: BoundedAudioQueue<AnalyzerInput>

    private struct State {
        var converter: SpeechAudioConverter
        var elapsed: CMTime = .zero
        var droppedSeconds: Double = 0
        var unreportedSeconds: Double = 0
        var unreportedStart: Double?
        var unreportedEnd: Double?
        var isOpen = true

        /// Whether audio has been evicted since the last time the backlog was
        /// seen to have caught up. While this is true the losses being
        /// accumulated all belong to one incident.
        var isBehind = false

        /// Buffers accepted since the last eviction. The backlog catching up
        /// is measured in these rather than in seconds, because the queue's
        /// capacity is what a full recovery has to be measured against.
        var acceptedSinceEviction = 0
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
    /// - Returns: An observation worth publishing: unreported loss once it has
    ///   added up, or the news that the backlog has caught up and the run of
    ///   losses is therefore over. `nil` when there is nothing to report.
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
            guard let evicted else {
                return Self.noteAccepted(in: &state, capacity: queue.capacity)
            }
            guard outputSampleRate > 0 else { return nil }

            state.isBehind = true
            state.acceptedSinceEviction = 0
            let lost = Double(evicted.buffer.frameLength) / outputSampleRate
            state.droppedSeconds += lost
            state.unreportedSeconds += lost
            if let evictedStart = evicted.bufferStartTime, evictedStart.isNumeric {
                if state.unreportedStart == nil { state.unreportedStart = evictedStart.seconds }
                state.unreportedEnd = evictedStart.seconds + lost
            }
            guard state.unreportedSeconds >= Self.reportingThreshold else { return nil }
            return Self.takeDrop(from: &state, closesIncident: false)
        }
    }

    /// Records a buffer the backlog had room for, and reports the backlog
    /// catching up when it finally has.
    ///
    /// The evidence is the queue's own capacity. Appending to a full queue
    /// always evicts, so a run of appends that evicted nothing is a run during
    /// which the queue was never full; once that run is as long as the whole
    /// backlog, the recogniser has absorbed everything it had fallen behind on
    /// and the incident is over. Nothing here consults a clock: a wall-clock
    /// delay would be a guess about the recogniser, and this is a measurement
    /// of it.
    ///
    /// - Parameters:
    ///   - state: The input's state, with the lock held.
    ///   - capacity: The backlog's capacity.
    /// - Returns: The closing observation, or `nil` when the run of losses is
    ///   not over or there was none.
    private static func noteAccepted(in state: inout State, capacity: Int) -> DroppedAudio? {
        guard state.isBehind else { return nil }
        state.acceptedSinceEviction += 1
        guard state.acceptedSinceEviction >= capacity else { return nil }
        return takeDrop(from: &state, closesIncident: true)
    }

    /// Takes any dropped audio that has not been reported yet.
    ///
    /// Called as a run ends, so whatever comes back closes its incident: no
    /// further audio can reach a recogniser that is being shut down.
    ///
    /// - Returns: The unreported drop, or `nil` when there is none.
    func takeUnreportedDrop() -> DroppedAudio? {
        state.withLock { state in
            guard state.unreportedSeconds > 0 else { return nil }
            return Self.takeDrop(from: &state, closesIncident: true)
        }
    }

    /// Empties the unreported drop and returns it.
    ///
    /// - Parameters:
    ///   - state: The input's state, with the lock held.
    ///   - closesIncident: Whether the backlog has caught up, or the run is
    ///     ending, so nothing further can be lost to this incident.
    /// - Returns: The observation that was pending.
    private static func takeDrop(from state: inout State, closesIncident: Bool) -> DroppedAudio {
        defer {
            state.unreportedSeconds = 0
            state.unreportedStart = nil
            state.unreportedEnd = nil
            if closesIncident {
                state.isBehind = false
                state.acceptedSinceEviction = 0
            }
        }
        return DroppedAudio(
            seconds: state.unreportedSeconds,
            startTime: state.unreportedStart,
            endTime: state.unreportedEnd,
            closesIncident: closesIncident
        )
    }

    /// Stops accepting audio and ends the recogniser's input sequence.
    func close() {
        state.withLock { $0.isOpen = false }
        queue.finish()
    }
}
