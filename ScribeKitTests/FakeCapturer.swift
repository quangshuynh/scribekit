//
//  FakeCapturer.swift
//  ScribeKitTests
//

import Foundation
@testable import ScribeKit

/// A capturer that records calls and can be made to fail or to be interrupted,
/// so capture lifecycle is testable without ScreenCaptureKit, a real meeting or
/// screen recording permission.
///
/// Its start/stop rules mirror the real implementation: an empty selection and
/// a second start are refused rather than quietly accepted.
nonisolated final class FakeCapturer: AudioCapturing, @unchecked Sendable {
    let interruptions: AsyncStream<AudioCaptureError>
    let consumer: AudioSampleConsuming

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var configurations: [AudioCaptureConfiguration] = []
    private(set) var isCapturing = false

    /// Thrown by the next `start`, when set.
    var startError: AudioCaptureError?

    private let continuation: AsyncStream<AudioCaptureError>.Continuation

    init(consumer: AudioSampleConsuming) {
        self.consumer = consumer
        var continuation: AsyncStream<AudioCaptureError>.Continuation!
        interruptions = AsyncStream { continuation = $0 }
        self.continuation = continuation
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
