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
    /// - Parameter sample: A description of the buffer that just arrived.
    func consume(_ sample: CapturedAudioSample)

    /// Records that a buffer arrived but could not be described.
    ///
    /// Capture counts these rather than discarding them silently, so a stream
    /// that is delivering unusable audio is visible instead of looking idle.
    func recordUnreadableSample()
}

extension AudioSampleConsuming {
    /// Ignores an unreadable buffer.
    func recordUnreadableSample() {}
}
