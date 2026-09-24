//
//  CaptureModeRouter.swift
//  ScribeKit
//

import Foundation

/// The one capturer a meeting runtime talks to, dispatching each start to the
/// capturer for the configuration's ``CaptureMode``.
///
/// This is the whole of the capture-source abstraction, and it is
/// deliberately this small. Both capturers already speak ``AudioCapturing``
/// and deliver to the same fan-out consumer, so recognition, the transcript,
/// gap incidents, pause and resume, the session record and every failure path
/// run unchanged whichever source fed them; the only thing that differs
/// between an App Audio meeting and a Microphone one is which of these two
/// receives ``start(configuration:)``.
///
/// It holds no meeting state. Which mode is running is the runtime's to know
/// — it took the snapshot — so a stop is passed to both capturers, each of
/// which treats a stop with nothing running as the no-op the protocol says it
/// is. Holding an "active" capturer here would be a second copy of that fact,
/// and one that a stream ending by itself would leave stale.
nonisolated final class CaptureModeRouter: AudioCapturing {

    let interruptions: AsyncStream<AudioCaptureError>

    private let applications: any AudioCapturing
    private let microphone: any AudioCapturing
    private let continuation: AsyncStream<AudioCaptureError>.Continuation
    private let forwarding: [Task<Void, Never>]

    /// Creates a router over one capturer per mode.
    ///
    /// - Parameters:
    ///   - applications: Captures application audio.
    ///   - microphone: Listens to the microphone.
    init(applications: any AudioCapturing, microphone: any AudioCapturing) {
        self.applications = applications
        self.microphone = microphone
        var continuation: AsyncStream<AudioCaptureError>.Continuation!
        interruptions = AsyncStream(bufferingPolicy: .bufferingNewest(4)) { continuation = $0 }
        self.continuation = continuation
        // Each capturer's interruptions are forwarded as they arrive. Only the
        // capturer that was started can end a stream by itself, so the merged
        // sequence says exactly what the one running capturer said.
        let merged = continuation!
        forwarding = [applications.interruptions, microphone.interruptions].map { stream in
            Task {
                for await error in stream { merged.yield(error) }
            }
        }
    }

    deinit {
        for task in forwarding { task.cancel() }
        continuation.finish()
    }

    func prepare(configuration: AudioCaptureConfiguration) async throws {
        try await capturer(for: configuration).prepare(configuration: configuration)
    }

    func start(configuration: AudioCaptureConfiguration) async throws {
        try await capturer(for: configuration).start(configuration: configuration)
    }

    func stop() async {
        await applications.stop()
        await microphone.stop()
    }

    /// The capturer a configuration belongs to.
    ///
    /// - Parameter configuration: What would be captured.
    /// - Returns: The capturer for its mode.
    private func capturer(for configuration: AudioCaptureConfiguration) -> any AudioCapturing {
        switch configuration.mode {
        case .applications: applications
        case .microphone: microphone
        }
    }
}
