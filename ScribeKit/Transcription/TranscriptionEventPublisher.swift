//
//  TranscriptionEventPublisher.swift
//  ScribeKit
//

import Foundation
import Synchronization

/// A count of the events a transcriber has published, and of the events its
/// bounded event buffer could not hold.
///
/// The published count is what a stop waits for: it tells a coordinator how
/// many events it must have observed before it can claim to have seen
/// everything the recogniser produced. The dropped count exists so that
/// overflow is a reported condition rather than a silent one — finalised
/// speech that never reached a consumer must fail a meeting, not vanish from
/// its transcript.
nonisolated struct TranscriptionEventTally: Equatable, Sendable {
    /// Events that were accepted by the event buffer and will be delivered.
    let published: Int

    /// Events the buffer was too full to hold, which no consumer will see.
    let dropped: Int

    /// Creates a tally.
    ///
    /// - Parameters:
    ///   - published: Events accepted by the buffer.
    ///   - dropped: Events the buffer discarded.
    init(published: Int = 0, dropped: Int = 0) {
        self.published = published
        self.dropped = dropped
    }
}

/// Publishes transcription events and counts what happened to them.
///
/// The publisher wraps an `AsyncStream` continuation so that every yield is
/// accounted for in one place. `AsyncStream` reports whether an element was
/// enqueued or discarded by its buffering policy, and that answer is the only
/// evidence anyone gets that a bounded buffer overflowed, so it is recorded
/// rather than ignored.
///
/// It is safe to publish from any thread: the tally is held under a mutex and
/// the continuation is itself thread-safe.
nonisolated final class TranscriptionEventPublisher: Sendable {
    private let continuation: AsyncStream<TranscriptionEvent>.Continuation
    private let tallyState = Mutex(TranscriptionEventTally())

    /// Wraps a stream's continuation.
    ///
    /// - Parameter continuation: The continuation events are yielded to.
    init(continuation: AsyncStream<TranscriptionEvent>.Continuation) {
        self.continuation = continuation
    }

    /// What has been published and what has been dropped so far.
    var tally: TranscriptionEventTally { tallyState.withLock { $0 } }

    /// Publishes one event, recording whether the buffer accepted it.
    ///
    /// - Parameter event: The event to publish.
    func publish(_ event: TranscriptionEvent) {
        let outcome = continuation.yield(event)
        tallyState.withLock { tally in
            switch outcome {
            case .enqueued:
                tally = TranscriptionEventTally(published: tally.published + 1, dropped: tally.dropped)
            case .dropped:
                tally = TranscriptionEventTally(published: tally.published, dropped: tally.dropped + 1)
            case .terminated:
                break
            @unknown default:
                break
            }
        }
    }

    /// Ends the event stream.
    func finish() {
        continuation.finish()
    }
}
