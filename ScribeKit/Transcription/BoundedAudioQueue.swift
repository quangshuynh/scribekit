//
//  BoundedAudioQueue.swift
//  ScribeKit
//

import Foundation
import Synchronization

/// A fixed-capacity handover between a producer that cannot wait and a
/// consumer that can.
///
/// Capture delivers audio on a real-time queue at a rate the recogniser does
/// not have to match. An unbounded buffer between them would turn a recogniser
/// that is momentarily behind into memory that grows for the rest of the
/// meeting, so the backlog is capped: appending to a full queue evicts the
/// oldest element and hands it back, and the caller is responsible for
/// reporting the loss rather than hiding it.
///
/// Appending never blocks and never allocates beyond the cap. The queue is an
/// `AsyncSequence`, so a single consumer suspends while it is empty and
/// finishes once ``finish()`` has been called and the backlog is drained.
/// Exactly one consumer may iterate a queue.
nonisolated final class BoundedAudioQueue<Element: Sendable>: AsyncSequence, Sendable {

    /// The largest number of elements held before the oldest is evicted.
    let capacity: Int

    private struct State {
        var elements: [Element] = []
        var isFinished = false
        var waiter: CheckedContinuation<Element?, Never>?
    }

    private let state = Mutex(State())

    /// Creates an empty queue.
    ///
    /// - Parameter capacity: The largest backlog to hold. Must be positive.
    init(capacity: Int) {
        precondition(capacity > 0, "A bounded queue needs room for at least one element")
        self.capacity = capacity
    }

    /// The number of elements waiting to be consumed.
    var count: Int { state.withLock { $0.elements.count } }

    /// Whether the producer has finished and the backlog has been drained.
    var isDrained: Bool { state.withLock { $0.isFinished && $0.elements.isEmpty } }

    /// Adds an element, evicting the oldest when the queue is full.
    ///
    /// The newest audio is always kept, so recognition stays as close to live
    /// as the backlog allows; what is lost is the audio the recogniser had
    /// already fallen behind on.
    ///
    /// - Parameter element: The element to add.
    /// - Returns: The element evicted to make room, or `nil` when nothing was
    ///   evicted. Adding to a finished queue evicts the new element itself.
    @discardableResult
    func append(_ element: Element) -> Element? {
        let outcome: (evicted: Element?, waiter: CheckedContinuation<Element?, Never>?) =
            state.withLock { state in
                guard !state.isFinished else { return (element, nil) }
                if let waiter = state.waiter {
                    state.waiter = nil
                    return (nil, waiter)
                }
                var evicted: Element?
                if state.elements.count >= capacity {
                    evicted = state.elements.removeFirst()
                }
                state.elements.append(element)
                return (evicted, nil)
            }
        outcome.waiter?.resume(returning: element)
        return outcome.evicted
    }

    /// Declares that no further elements will be added.
    ///
    /// A consumer waiting on an empty queue is released immediately; one with a
    /// backlog still receives it before the sequence ends.
    func finish() {
        let waiter = state.withLock { state -> CheckedContinuation<Element?, Never>? in
            state.isFinished = true
            defer { state.waiter = nil }
            return state.elements.isEmpty ? state.waiter : nil
        }
        waiter?.resume(returning: nil)
    }

    /// Takes the next element, waiting while the queue is empty.
    ///
    /// - Returns: The next element, or `nil` once the queue has finished and
    ///   its backlog has been consumed.
    private func next() async -> Element? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let immediate = state.withLock { state -> Element?? in
                    if !state.elements.isEmpty { return .some(state.elements.removeFirst()) }
                    if state.isFinished { return .some(nil) }
                    state.waiter = continuation
                    return nil
                }
                if let immediate { continuation.resume(returning: immediate) }
            }
        } onCancel: {
            finish()
        }
    }

    /// The queue's single consumer.
    struct AsyncIterator: AsyncIteratorProtocol {
        fileprivate let queue: BoundedAudioQueue

        /// - Returns: The next element, or `nil` when the queue has finished.
        func next() async -> Element? { await queue.next() }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(queue: self) }
}
