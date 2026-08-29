//
//  FakeSpeechTranscriber.swift
//  ScribeKitTests
//

import Synchronization
@testable import ScribeKit

/// A transcriber that records calls and emits events on demand, so recognition
/// lifecycle is testable without the Speech framework, a downloaded speech
/// model or real audio.
///
/// Its start rule mirrors the real implementation: a second start while a run
/// is in progress is refused rather than quietly accepted.
nonisolated final class FakeSpeechTranscriber: SpeechTranscribing, @unchecked Sendable {
    let events: AsyncStream<TranscriptionEvent>

    /// The locales ``availableLocales()`` reports.
    var locales: [TranscriptionLocale] = [TranscriptionLocale(id: "en-US", isInstalled: true)]

    /// What ``availability(for:)`` reports.
    var availabilityResult: SpeechRecognitionAvailability = .available(localeIdentifier: "en-US")

    /// Thrown by the next `start`, when set.
    var startError: TranscriptionError?

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var configurations: [TranscriptionConfiguration] = []
    private(set) var isTranscribing = false

    private let continuation: AsyncStream<TranscriptionEvent>.Continuation
    private let received = Mutex<[CapturedPCMBuffer]>([])

    init() {
        var continuation: AsyncStream<TranscriptionEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    /// The buffers delivered through the capture boundary.
    var receivedBuffers: [CapturedPCMBuffer] { received.withLock { $0 } }

    func consume(_ buffer: CapturedPCMBuffer) {
        received.withLock { $0.append(buffer) }
    }

    func availableLocales() async -> [TranscriptionLocale] { locales }

    func availability(for configuration: TranscriptionConfiguration) async -> SpeechRecognitionAvailability {
        availabilityResult
    }

    func start(configuration: TranscriptionConfiguration) async throws {
        startCount += 1
        configurations.append(configuration)
        if let startError {
            self.startError = nil
            throw startError
        }
        guard !isTranscribing else { throw TranscriptionError.alreadyTranscribing }
        isTranscribing = true
    }

    func stop() async {
        stopCount += 1
        isTranscribing = false
    }

    /// Emits an event the way a running recogniser would.
    ///
    /// - Parameter event: The event to publish.
    func emit(_ event: TranscriptionEvent) {
        continuation.yield(event)
    }
}
