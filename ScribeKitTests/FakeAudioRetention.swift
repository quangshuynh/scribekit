//
//  FakeAudioRetention.swift
//  ScribeKitTests
//

import Foundation
import Synchronization
@testable import ScribeKit

/// An audio file that records what it was asked to write and can be made to
/// fail, so retention policy is testable without a codec or a disk.
///
/// It counts writes rather than keeping the frames, for the same reason the
/// production writer does not keep them: a double that accumulated a meeting's
/// audio would be measuring something ScribeKit never does.
nonisolated final class FakeAudioFile: AudioFileWriting, @unchecked Sendable {

    private struct State {
        var writeCount = 0
        var frameCount = 0
        var closeCount = 0
        var isOpen = true
        var writeError: AudioRetentionError?
        var closeError: AudioRetentionError?
        var failAfterWrites: Int?
    }

    private let state = Mutex(State())

    /// How many buffers reached the file.
    var writeCount: Int { state.withLock { $0.writeCount } }

    /// How many frames reached the file.
    var frameCount: Int { state.withLock { $0.frameCount } }

    /// How many times the file was closed. Closing twice is allowed and does
    /// nothing the second time, as it does in the real writer.
    var closeCount: Int { state.withLock { $0.closeCount } }

    /// Whether the file is still open.
    var isOpen: Bool { state.withLock { $0.isOpen } }

    /// Makes writing fail once this many buffers have been accepted.
    ///
    /// - Parameters:
    ///   - writes: How many buffers to accept first.
    ///   - error: What the failing write throws.
    func failWrites(after writes: Int, with error: AudioRetentionError = AudioRetentionError(.audioWriteFailed)) {
        state.withLock { state in
            state.failAfterWrites = writes
            state.writeError = error
        }
    }

    /// Makes closing the file fail.
    ///
    /// - Parameter error: What closing throws.
    func failClose(with error: AudioRetentionError = AudioRetentionError(.audioFinishFailed)) {
        state.withLock { $0.closeError = error }
    }

    func write(_ buffer: CapturedPCMBuffer) throws {
        try state.withLock { state in
            guard state.isOpen else { throw AudioRetentionError(.noSessionInProgress) }
            if let limit = state.failAfterWrites, state.writeCount >= limit, let error = state.writeError {
                throw error
            }
            state.writeCount += 1
            state.frameCount += buffer.frameCount
        }
    }

    func close() throws {
        let error: AudioRetentionError? = state.withLock { state in
            guard state.isOpen else { return nil }
            state.isOpen = false
            state.closeCount += 1
            return state.closeError
        }
        if let error { throw error }
    }
}

/// A file creator that hands out ``FakeAudioFile`` values and can refuse.
nonisolated final class FakeAudioFileCreator: AudioFileCreating, @unchecked Sendable {

    /// One request to create a file.
    struct Request: Equatable {
        let url: URL
        let mode: AudioRetentionMode
        let format: CapturedAudioFormat
    }

    private struct State {
        var requests: [Request] = []
        var files: [FakeAudioFile] = []
        var error: AudioRetentionError?
    }

    private let state = Mutex(State())

    /// Creates a creator that always succeeds.
    init() {}

    /// Every file that was asked for, in order.
    var requests: [Request] { state.withLock { $0.requests } }

    /// Every file that was created, in order.
    var files: [FakeAudioFile] { state.withLock { $0.files } }

    /// The file created most recently, if any.
    var lastFile: FakeAudioFile? { files.last }

    /// Makes every creation fail, as a folder that cannot be written to would.
    ///
    /// - Parameter error: What creation throws.
    func failCreation(with error: AudioRetentionError = AudioRetentionError(.cannotCreateAudioFile)) {
        state.withLock { $0.error = error }
    }

    func makeWriter(
        at url: URL,
        mode: AudioRetentionMode,
        format: CapturedAudioFormat
    ) throws -> any AudioFileWriting {
        let file = FakeAudioFile()
        let error: AudioRetentionError? = state.withLock { state in
            state.requests.append(Request(url: url, mode: mode, format: format))
            guard state.error == nil else { return state.error }
            state.files.append(file)
            return nil
        }
        if let error { throw error }
        return file
    }
}

/// A retainer that records its lifecycle and can be made to fail at any point,
/// so a whole meeting is testable without an audio file.
nonisolated final class FakeAudioRetention: AudioRetaining, @unchecked Sendable {

    /// What the retainer was asked to do, in order.
    enum Entry: Equatable {
        case started(mode: AudioRetentionMode, url: URL?)
        case appended(frames: Int)
        case finished
        case cancelled
    }

    private struct State {
        var entries: [Entry] = []
        var isOpen = false
        var startError: AudioRetentionError?
        var finishError: AudioRetentionError?
    }

    let failures: AsyncStream<AudioRetentionError>

    private let state = Mutex(State())
    private let continuation: AsyncStream<AudioRetentionError>.Continuation

    /// Creates a retainer that accepts everything.
    init() {
        var continuation: AsyncStream<AudioRetentionError>.Continuation!
        failures = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation = $0 }
        self.continuation = continuation
    }

    /// Everything the retainer was asked to do, in order.
    var entries: [Entry] { state.withLock { $0.entries } }

    /// Whether a recording is open, so a test can prove one was closed.
    var isOpen: Bool { state.withLock { $0.isOpen } }

    /// How many buffers reached the retainer.
    var appendCount: Int {
        entries.reduce(into: 0) { count, entry in
            if case .appended = entry { count += 1 }
        }
    }

    /// How many frames of audio reached the retainer, over the whole session.
    var appendedFrames: Int {
        entries.reduce(into: 0) { total, entry in
            if case let .appended(frames) = entry { total += frames }
        }
    }

    /// How many times the recording was finalised.
    var finishCount: Int {
        entries.reduce(into: 0) { count, entry in
            if case .finished = entry { count += 1 }
        }
    }

    /// Thrown by the next `startSession`.
    func failStart(with error: AudioRetentionError = AudioRetentionError(.cannotCreateAudioFile)) {
        state.withLock { $0.startError = error }
    }

    /// Thrown by the next `finishSession`.
    func failFinish(with error: AudioRetentionError = AudioRetentionError(.audioFinishFailed)) {
        state.withLock { $0.finishError = error }
    }

    /// Reports a write failing mid-meeting, as the capture queue would.
    ///
    /// - Parameter error: What went wrong.
    func reportFailure(_ error: AudioRetentionError = AudioRetentionError(.audioWriteFailed)) {
        continuation.yield(error)
    }

    func startSession(
        mode: AudioRetentionMode,
        layout: SessionArtifactLayout,
        format: CapturedAudioFormat
    ) throws -> URL? {
        let error: AudioRetentionError? = state.withLock { state in
            defer { state.startError = nil }
            if state.startError == nil, state.isOpen {
                return AudioRetentionError(.sessionAlreadyInProgress)
            }
            return state.startError
        }
        if let error {
            state.withLock { $0.entries.append(.started(mode: mode, url: nil)) }
            throw error
        }

        let url = layout.audioURL(for: mode)
        state.withLock { state in
            state.isOpen = url != nil
            state.entries.append(.started(mode: mode, url: url))
        }
        return url
    }

    func consume(_ buffer: CapturedPCMBuffer) {
        state.withLock { state in
            guard state.isOpen else { return }
            state.entries.append(.appended(frames: buffer.frameCount))
        }
    }

    func finishSession() throws {
        let error: AudioRetentionError? = state.withLock { state in
            defer { state.finishError = nil }
            guard state.isOpen else { return AudioRetentionError(.noSessionInProgress) }
            state.isOpen = false
            state.entries.append(.finished)
            return state.finishError
        }
        if let error { throw error }
    }

    func cancelSession() {
        state.withLock { state in
            guard state.isOpen else { return }
            state.isOpen = false
            state.entries.append(.cancelled)
        }
    }
}
