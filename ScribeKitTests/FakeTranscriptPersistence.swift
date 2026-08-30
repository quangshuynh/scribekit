//
//  FakeTranscriptPersistence.swift
//  ScribeKitTests
//

import Foundation
import Synchronization
@testable import ScribeKit

/// A transcript writer that records what it was asked to write and can be made
/// to fail, so a whole meeting lifecycle is testable without a disk, a save
/// folder or the sandbox.
///
/// Its lifecycle rules mirror the real store: appending without a session and
/// starting a second session are refused rather than quietly accepted.
nonisolated final class FakeTranscriptPersistence: TranscriptPersisting, @unchecked Sendable {

    /// What the writer was asked to make durable, in order.
    enum Entry: Equatable {
        case started(directory: URL)
        case segment(TranscriptSegment)
        case gap(TranscriptGap)
        case finished(SessionCompletionOutcome)
    }

    private struct State {
        var entries: [Entry] = []
        var isOpen = false
        var startError: TranscriptPersistenceError?
        var appendError: TranscriptPersistenceError?
        var finishError: TranscriptPersistenceError?
        var startDelay: Duration = .zero
        var onFinish: (@Sendable () -> Void)?
    }

    private let state = Mutex(State())

    /// Everything the writer accepted, in the order it accepted it.
    var entries: [Entry] { state.withLock { $0.entries } }

    /// Whether a session is open, so a test can prove one was closed.
    var isOpen: Bool { state.withLock { $0.isOpen } }

    /// The finalised spans that reached durable storage.
    var segments: [TranscriptSegment] {
        entries.compactMap { if case let .segment(segment) = $0 { segment } else { nil } }
    }

    /// The gaps that reached durable storage.
    var gaps: [TranscriptGap] {
        entries.compactMap { if case let .gap(gap) = $0 { gap } else { nil } }
    }

    /// Thrown by the next `startSession`, when set.
    func failStart(with error: TranscriptPersistenceError) {
        state.withLock { $0.startError = error }
    }

    /// Thrown by every append until cleared.
    func failAppends(with error: TranscriptPersistenceError) {
        state.withLock { $0.appendError = error }
    }

    /// Thrown by the next `finishSession`.
    func failFinish(with error: TranscriptPersistenceError) {
        state.withLock { $0.finishError = error }
    }

    /// Makes `finishSession` take time, so a test can observe whether a stop
    /// waits for it.
    func delayFinish(by duration: Duration) {
        state.withLock { $0.startDelay = duration }
    }

    /// Observes the moment the session is closed, so a test can check what the
    /// rest of the meeting looked like just before its record was written.
    ///
    /// - Parameter body: Called before the session is recorded as finished.
    func observeFinish(_ body: @escaping @Sendable () -> Void) {
        state.withLock { $0.onFinish = body }
    }

    func startSession(
        _ session: MeetingSession,
        localeIdentifier: String,
        startedAt: Date
    ) async throws -> SessionArtifactLayout {
        let error: TranscriptPersistenceError? = state.withLock { state in
            defer { state.startError = nil }
            if state.startError == nil, state.isOpen {
                return TranscriptPersistenceError(.sessionAlreadyInProgress)
            }
            return state.startError
        }
        if let error { throw error }

        let name = SessionDirectoryName.make(date: startedAt, title: session.title)
        let layout = SessionArtifactLayout(destination: session.destination, directoryName: name)
        state.withLock { state in
            state.isOpen = true
            state.entries.append(.started(directory: layout.directory))
        }
        return layout
    }

    func appendFinalSegment(_ segment: TranscriptSegment) async throws {
        try append(.segment(segment), isFinalized: segment.state == .final)
    }

    func recordGap(_ gap: TranscriptGap) async throws {
        try append(.gap(gap), isFinalized: true)
    }

    func finishSession(endedAt: Date, outcome: SessionCompletionOutcome) async throws {
        let delay = state.withLock { $0.startDelay }
        if delay > .zero { try? await Task.sleep(for: delay) }
        state.withLock { $0.onFinish }?()

        let error: TranscriptPersistenceError? = state.withLock { state in
            defer { state.finishError = nil }
            guard state.isOpen else { return TranscriptPersistenceError(.noSessionInProgress) }
            state.isOpen = false
            state.entries.append(.finished(outcome))
            return state.finishError
        }
        if let error { throw error }
    }

    /// How each closed session was reported as ending, in order.
    var outcomes: [SessionCompletionOutcome] {
        entries.compactMap { if case let .finished(outcome) = $0 { outcome } else { nil } }
    }

    /// Records one durable entry, applying the same refusals the real store
    /// applies.
    ///
    /// - Parameters:
    ///   - entry: What was written.
    ///   - isFinalized: Whether the material was finalised.
    /// - Throws: The refusal, or whatever the test armed.
    private func append(_ entry: Entry, isFinalized: Bool) throws {
        let error: TranscriptPersistenceError? = state.withLock { state in
            guard state.isOpen else { return TranscriptPersistenceError(.noSessionInProgress) }
            guard isFinalized else { return TranscriptPersistenceError(.segmentNotFinalized) }
            if let armed = state.appendError { return armed }
            state.entries.append(entry)
            return nil
        }
        if let error { throw error }
    }
}
