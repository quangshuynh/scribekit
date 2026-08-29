//
//  ScreenCaptureKitAudioCapturer.swift
//  ScribeKit
//

import CoreMedia
import Foundation
import OSLog
import ScreenCaptureKit
import Synchronization

/// Subsystem used for capture logging, matching the application's identifier so
/// capture events are filterable in Console alongside the rest of the app.
private nonisolated let captureSubsystem = Bundle.main.bundleIdentifier ?? "ScribeKit"

/// Captures audio from selected applications with ScreenCaptureKit.
///
/// The actor owns the whole framework-facing side of capture: resolving the
/// selection against the applications running now, building the filter and
/// configuration, the `SCStream` itself, and the order of start and stop.
/// ScreenCaptureKit types stop here — callers pass ``AudioCaptureConfiguration``
/// and receive ``CapturedPCMBuffer`` values and ``AudioCaptureError`` events.
///
/// Audio buffers never reach the actor. They are delivered on a dedicated
/// queue straight to the consumer, so the delivery rate is never coupled to
/// actor scheduling or to the main actor.
actor ScreenCaptureKitAudioCapturer: AudioCapturing {

    /// Frames per second requested for video.
    ///
    /// ScreenCaptureKit has no audio-only stream: a filter and a frame size are
    /// always part of a valid configuration. ScribeKit never adds a screen
    /// output, so no frame is ever delivered, decoded, rendered or stored; this
    /// interval simply asks for the least video work the API will accept.
    private static let videoFramesPerSecond: Int32 = 1

    /// Smallest frame size ScreenCaptureKit accepts without complaint, used for
    /// the same reason as ``videoFramesPerSecond``.
    private static let videoFrameDimension = 2

    /// Frames the capture system may hold before dropping them.
    ///
    /// The documented range tops out at eight; the minimum keeps capture memory
    /// small, and the frames in question are the ones ScribeKit never reads.
    private static let queueDepth = 3

    nonisolated let interruptions: AsyncStream<AudioCaptureError>

    private let consumer: AudioSampleConsuming
    private let excludedBundleIdentifiers: Set<String>
    private nonisolated let interruptionContinuation: AsyncStream<AudioCaptureError>.Continuation
    private nonisolated let logger = Logger(subsystem: captureSubsystem, category: "AudioCapture")

    /// The queue ScreenCaptureKit delivers audio on.
    ///
    /// Serial, so buffers stay in order, and `userInitiated` because dropped
    /// meeting audio cannot be recovered later.
    private nonisolated let sampleQueue = DispatchQueue(
        label: "\(captureSubsystem).audio-capture",
        qos: .userInitiated,
        autoreleaseFrequency: .workItem
    )

    private var session: Session?

    /// A running stream and the output attached to it.
    private struct Session {
        let stream: SCStream
        let output: StreamOutput
    }

    /// Creates a capturer.
    ///
    /// - Parameters:
    ///   - consumer: Receives audio buffers on the delivery queue.
    ///   - excludedBundleIdentifiers: Applications never captured, whatever the
    ///     selection says. Defaults to ScribeKit's own bundle identifier, which
    ///     together with `excludesCurrentProcessAudio` keeps ScribeKit out of
    ///     its own capture.
    init(consumer: AudioSampleConsuming, excludedBundleIdentifiers: Set<String>? = nil) {
        self.consumer = consumer
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
            ?? Set([Bundle.main.bundleIdentifier].compactMap { $0 })
        var continuation: AsyncStream<AudioCaptureError>.Continuation!
        interruptions = AsyncStream(bufferingPolicy: .bufferingNewest(4)) { continuation = $0 }
        interruptionContinuation = continuation
    }

    deinit {
        interruptionContinuation.finish()
    }

    func start(configuration: AudioCaptureConfiguration) async throws {
        guard session == nil else { throw AudioCaptureError.alreadyCapturing }
        guard !configuration.sourceIDs.isEmpty else { throw AudioCaptureError.noSourcesSelected }

        logger.info("Capture requested for \(configuration.sourceIDs.count, privacy: .public) application(s)")

        let content = try await shareableContent()
        let applications = try resolveApplications(configuration.sourceIDs, in: content)
        guard let display = content.displays.first else {
            logger.error("Capture refused: the system reported no display")
            throw AudioCaptureError.noCaptureDisplay
        }

        let filter = SCContentFilter(display: display, including: applications, exceptingWindows: [])
        let output = StreamOutput(consumer: consumer) { [weak self] error in
            Task { await self?.handleStreamStop(error) }
        }
        let stream = SCStream(
            filter: filter,
            configuration: Self.streamConfiguration(for: configuration),
            delegate: output
        )

        do {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()
        } catch {
            output.invalidate()
            let captureError = Self.captureError(from: error)
            logger.error("Capture failed to start: \(String(describing: captureError), privacy: .public)")
            throw captureError
        }

        session = Session(stream: stream, output: output)
        logger.info("Capture started for \(applications.count, privacy: .public) process(es)")
    }

    func stop() async {
        guard let session else { return }
        self.session = nil
        session.output.invalidate()
        do {
            try await session.stream.stopCapture()
            logger.info("Capture stopped")
        } catch {
            // The stream may already have stopped on its own; teardown is done
            // either way, and the reason was reported as an interruption.
            logger.info("Capture stop reported: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Handles the capture system stopping a running stream by itself.
    ///
    /// - Parameter error: The reason the stream ended.
    private func handleStreamStop(_ error: AudioCaptureError) {
        guard let session else { return }
        self.session = nil
        session.output.invalidate()
        logger.error("Capture interrupted: \(String(describing: error), privacy: .public)")
        interruptionContinuation.yield(error)
    }

    /// Asks the system what can be captured right now.
    ///
    /// Windows are irrelevant to audio, so the query is not restricted to
    /// on-screen ones: an application that is running with every window
    /// minimised is still producing audio and is still a valid source.
    ///
    /// - Returns: The current shareable content.
    /// - Throws: ``AudioCaptureError`` describing why the system refused.
    private func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: false
            )
        } catch {
            throw Self.captureError(from: error)
        }
    }

    /// Resolves selected bundle identifiers to the processes running now.
    ///
    /// A bundle identifier may map to several processes; all of them are
    /// included, because a single application can produce audio from more than
    /// one process.
    ///
    /// - Parameters:
    ///   - requested: The selected bundle identifiers.
    ///   - content: The system's current shareable content.
    /// - Returns: The running applications to capture.
    /// - Throws: ``AudioCaptureError/sourcesUnavailable(_:)`` when any selected
    ///   application is not running.
    private func resolveApplications(
        _ requested: Set<CaptureSource.ID>,
        in content: SCShareableContent
    ) throws -> [SCRunningApplication] {
        let candidates = content.applications.filter {
            !excludedBundleIdentifiers.contains($0.bundleIdentifier)
        }
        let outcome = CaptureSourceReconciliation.reconcile(
            requested: requested,
            available: Set(candidates.map(\.bundleIdentifier))
        )
        guard outcome.isComplete else {
            logger.error("Selected source unavailable: \(outcome.missing.count, privacy: .public) application(s)")
            throw AudioCaptureError.sourcesUnavailable(outcome.missing)
        }
        return candidates.filter { requested.contains($0.bundleIdentifier) }
    }

    /// Builds the stream configuration for a capture request.
    ///
    /// Audio is enabled and ScribeKit's own output excluded; the video side is
    /// reduced to the smallest valid frame at the lowest rate, since no screen
    /// output is ever added. The microphone is explicitly left off: ScribeKit
    /// captures the applications the user selected and nothing else.
    ///
    /// - Parameter configuration: The requested capture settings.
    /// - Returns: A configuration ready for `SCStream`.
    private static func streamConfiguration(
        for configuration: AudioCaptureConfiguration
    ) -> SCStreamConfiguration {
        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.capturesAudio = true
        streamConfiguration.sampleRate = configuration.sampleRate
        streamConfiguration.channelCount = configuration.channelCount
        streamConfiguration.excludesCurrentProcessAudio = true
        streamConfiguration.captureMicrophone = false
        streamConfiguration.width = videoFrameDimension
        streamConfiguration.height = videoFrameDimension
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: videoFramesPerSecond)
        streamConfiguration.queueDepth = queueDepth
        streamConfiguration.showsCursor = false
        return streamConfiguration
    }

    /// Classifies an error raised while starting or querying capture.
    ///
    /// - Parameter error: The error the framework reported.
    /// - Returns: The matching capture error, keeping the system's own
    ///   description for anything ScribeKit cannot name.
    private static func captureError(from error: Error) -> AudioCaptureError {
        let error = error as NSError
        guard error.domain == SCStreamErrorDomain else {
            return .systemFailure(error.localizedDescription)
        }
        switch error.code {
        case SCStreamError.Code.userDeclined.rawValue,
             SCStreamError.Code.missingEntitlements.rawValue:
            return .permissionDenied
        case SCStreamError.Code.attemptToStartStreamState.rawValue:
            return .alreadyCapturing
        default:
            return .systemFailure(error.localizedDescription)
        }
    }

    /// Classifies an error reported for a stream that was already running.
    ///
    /// - Parameter error: The error the delegate received.
    /// - Returns: The matching interruption.
    fileprivate static func interruption(from error: Error) -> AudioCaptureError {
        let captureError = captureError(from: error)
        if case let .systemFailure(description) = captureError {
            return .interrupted(description)
        }
        return captureError
    }
}

/// The stream's output and delegate.
///
/// Kept deliberately thin: it decides whether a buffer is still wanted, adapts
/// it, and hands it on. Everything else — state, ordering, teardown — belongs
/// to the actor.
private nonisolated final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    private let consumer: AudioSampleConsuming
    private let onStop: @Sendable (AudioCaptureError) -> Void
    private let isActive = Mutex(true)

    /// Creates an output.
    ///
    /// - Parameters:
    ///   - consumer: Receives adapted audio buffers on the delivery queue.
    ///   - onStop: Called once if the capture system stops the stream itself.
    init(consumer: AudioSampleConsuming, onStop: @escaping @Sendable (AudioCaptureError) -> Void) {
        self.consumer = consumer
        self.onStop = onStop
    }

    /// Stops the output from forwarding anything further.
    ///
    /// Buffers can still be in flight on the delivery queue when a stop is
    /// requested; after this they are discarded rather than counted as capture
    /// that outlived the session.
    func invalidate() {
        isActive.withLock { $0 = false }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, isActive.withLock({ $0 }) else { return }
        guard let buffer = CapturedPCMBufferAdapter.buffer(from: sampleBuffer) else {
            consumer.recordUnreadableSample()
            return
        }
        consumer.consume(buffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard isActive.withLock({ $0 }) else { return }
        invalidate()
        onStop(ScreenCaptureKitAudioCapturer.interruption(from: error))
    }
}
