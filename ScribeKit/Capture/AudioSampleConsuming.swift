//
//  AudioSampleConsuming.swift
//  ScribeKit
//

import Foundation

/// Receives audio buffers from a capture implementation.
///
/// Implementations are called on the capture system's own delivery queue, many
/// times a second, and must return quickly: no blocking work, no filesystem
/// access and no synchronous hop to the main actor. Anything the interface
/// needs is coalesced and forwarded separately, so the hot path never waits on
/// a view update.
nonisolated protocol AudioSampleConsuming: Sendable {
    /// Handles one buffer of captured audio.
    ///
    /// - Parameter buffer: The audio that just arrived, owned by the caller's
    ///   value rather than by the capture system.
    func consume(_ buffer: CapturedPCMBuffer)

    /// Records that a buffer arrived but could not be read.
    ///
    /// Capture counts these rather than discarding them silently, so a stream
    /// that is delivering unusable audio is visible instead of looking idle.
    func recordUnreadableSample()
}

nonisolated extension AudioSampleConsuming {
    /// Ignores an unreadable buffer.
    func recordUnreadableSample() {}
}

/// Delivers every captured buffer to several consumers in turn.
///
/// Capture has one output but more than one interested party — the activity
/// summary the interface shows and the transcriber that turns audio into text.
/// Fanning out here keeps the capturer unaware of both, and keeps the order
/// deterministic: consumers see the same buffers in the same sequence.
///
/// Every consumer runs on the delivery queue, so each is bound by the same
/// obligation to return quickly.
nonisolated struct BroadcastingAudioSampleConsumer: AudioSampleConsuming {
    private let consumers: [any AudioSampleConsuming]

    /// Creates a fan-out consumer.
    ///
    /// - Parameter consumers: The consumers to deliver to, in order.
    init(_ consumers: [any AudioSampleConsuming]) {
        self.consumers = consumers
    }

    func consume(_ buffer: CapturedPCMBuffer) {
        for consumer in consumers { consumer.consume(buffer) }
    }

    func recordUnreadableSample() {
        for consumer in consumers { consumer.recordUnreadableSample() }
    }
}
