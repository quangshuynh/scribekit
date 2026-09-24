//
//  FakeCapturer.swift
//  ScribeKitTests
//

import Foundation
import Synchronization
@testable import ScribeKit

/// A capturer that records calls and can be made to fail or to be interrupted,
/// so capture lifecycle is testable without ScreenCaptureKit, a real meeting or
/// screen recording permission.
///
/// Its start/stop rules mirror the real implementations: an empty selection and
/// a second start are refused rather than quietly accepted. It accepts either
/// capture mode, so the same double stands in for application capture and for
/// the microphone; a test that needs a start to wait — as one does while a
/// permission prompt is on screen — can hold ``prepare(configuration:)``.
nonisolated final class FakeCapturer: AudioCapturing, @unchecked Sendable {
    let interruptions: AsyncStream<AudioCaptureError>
    let consumer: AudioSampleConsuming

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var configurations: [AudioCaptureConfiguration] = []
    private(set) var isCapturing = false

    /// How many times a start was checked ahead of time, and what for.
    private(set) var prepareCount = 0
    private(set) var preparedConfigurations: [AudioCaptureConfiguration] = []

    /// Thrown by the next `start`, when set.
    var startError: AudioCaptureError?

    /// Thrown by every `prepare`, when set.
    var prepareError: AudioCaptureError?

    /// Whether `prepare` waits for ``releasePrepare()`` before answering.
    var holdsPrepare = false

    private let continuation: AsyncStream<AudioCaptureError>.Continuation
    private let heldPrepare = Mutex<CheckedContinuation<Void, Never>?>(nil)

    init(consumer: AudioSampleConsuming) {
        self.consumer = consumer
        var continuation: AsyncStream<AudioCaptureError>.Continuation!
        interruptions = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func prepare(configuration: AudioCaptureConfiguration) async throws {
        prepareCount += 1
        preparedConfigurations.append(configuration)
        if holdsPrepare {
            await withCheckedContinuation { continuation in
                heldPrepare.withLock { $0 = continuation }
            }
        }
        if let prepareError { throw prepareError }
    }

    /// Whether a `prepare` is waiting to be released.
    var isHoldingPrepare: Bool { heldPrepare.withLock { $0 != nil } }

    /// Lets a held `prepare` answer.
    func releasePrepare() {
        let held: CheckedContinuation<Void, Never>? = heldPrepare.withLock { held in
            let continuation = held
            held = nil
            return continuation
        }
        held?.resume()
    }

    func start(configuration: AudioCaptureConfiguration) async throws {
        startCount += 1
        configurations.append(configuration)
        if let startError { throw startError }
        guard !configuration.sourceIDs.isEmpty else { throw AudioCaptureError.noSourcesSelected }
        guard !isCapturing else { throw AudioCaptureError.alreadyCapturing }
        isCapturing = true
    }

    func stop() async {
        stopCount += 1
        isCapturing = false
    }

    /// Reports the capture system ending the stream on its own.
    func interrupt(_ error: AudioCaptureError) {
        isCapturing = false
        continuation.yield(error)
    }

    /// Delivers a synthetic buffer the way the real capture queue would.
    func deliver(_ buffer: CapturedPCMBuffer) {
        consumer.consume(buffer)
    }
}
