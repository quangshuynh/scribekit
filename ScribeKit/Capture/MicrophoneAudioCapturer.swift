//
//  MicrophoneAudioCapturer.swift
//  ScribeKit
//

import AVFAudio
import Foundation
import OSLog
import Synchronization

/// Listens to the Mac's current microphone input with `AVAudioEngine`.
///
/// The actor owns the whole framework-facing side of microphone capture: the
/// permission check, the engine, the tap on its input node, and the order of
/// start and stop. `AVFAudio` types stop here — callers pass
/// ``AudioCaptureConfiguration`` and receive ``CapturedPCMBuffer`` values and
/// ``AudioCaptureError`` events, exactly as they do from application capture,
/// so everything downstream is shared.
///
/// Audio never reaches the actor. The engine calls the tap on its own thread
/// and the tap hands each buffer straight to the consumer, so delivery is
/// never coupled to actor scheduling or to the main actor.
///
/// Nothing touches the audio engine until a start. Creating the capturer —
/// which the application does at launch, whatever mode the user is in — asks
/// macOS for nothing, so App Audio meetings never involve the microphone.
///
/// The microphone is listened to, not recorded: buffers go to the meeting's
/// consumers and are released, and a Microphone meeting keeps no audio file.
///
/// A change to the audio configuration while listening — the input device
/// switched, disconnected, or changing format — stops the engine, and is
/// reported as the stream ending by itself. ScribeKit does not restart on
/// another device: following the system to a different microphone mid-meeting
/// would put a second person's speech into a transcript without anyone
/// deciding it should.
actor MicrophoneAudioCapturer: AudioCapturing {

    /// Frames requested per tap callback. The engine treats this as a hint
    /// and may deliver more; the adapter cuts whatever arrives into pieces.
    private static let tapBufferSize: AVAudioFrameCount = 4_800

    /// What the interruption says when the engine stopped because the audio
    /// configuration changed.
    static let configurationChangeDescription =
        "the microphone input changed or was disconnected, so ScribeKit stopped listening rather than "
        + "switch to another microphone"

    nonisolated let interruptions: AsyncStream<AudioCaptureError>

    private let consumer: AudioSampleConsuming
    private let access: any MicrophoneAccessProviding
    private nonisolated let interruptionContinuation: AsyncStream<AudioCaptureError>.Continuation
    private nonisolated let logger = ScribeKitLog.capture

    private var session: Session?

    /// A running engine and what is attached to it.
    private nonisolated struct Session {
        let engine: AVAudioEngine
        let tap: MicrophoneTap
        let configurationObserver: any NSObjectProtocol
    }

    /// Creates a capturer.
    ///
    /// - Parameters:
    ///   - consumer: Receives audio buffers on the engine's tap thread.
    ///   - access: The system's answers about microphone access. The default
    ///     asks macOS; tests substitute their own.
    init(consumer: AudioSampleConsuming, access: any MicrophoneAccessProviding = SystemMicrophoneAccess()) {
        self.consumer = consumer
        self.access = access
        var continuation: AsyncStream<AudioCaptureError>.Continuation!
        interruptions = AsyncStream(bufferingPolicy: .bufferingNewest(4)) { continuation = $0 }
        interruptionContinuation = continuation
    }

    deinit {
        interruptionContinuation.finish()
    }

    /// Asks for microphone access when ScribeKit never has, and confirms the
    /// input the meeting was set up with is still the current one.
    ///
    /// This is the only place ScribeKit shows the microphone permission
    /// prompt during a meeting start, and it runs before the meeting creates
    /// anything on disk.
    func prepare(configuration: AudioCaptureConfiguration) async throws {
        guard configuration.mode == .microphone else { return }
        do {
            try await MicrophoneAccessGate.ensureAccess(access, mayPrompt: true)
            _ = try MicrophoneAccessGate.expectedInput(access, matching: configuration.sourceIDs)
        } catch {
            logger.notice(
                "Microphone start refused: \(DiagnosticCategory(error)?.rawValue ?? "unclassified", privacy: .public)"
            )
            throw error
        }
    }

    func start(configuration: AudioCaptureConfiguration) async throws {
        guard session == nil else { throw AudioCaptureError.alreadyCapturing }
        guard configuration.mode == .microphone, !configuration.sourceIDs.isEmpty else {
            throw AudioCaptureError.noSourcesSelected
        }
        // A start never prompts: a resume happens without the user being
        // asked for anything, and access turned off since the meeting began
        // is a refusal to report, not a question to put to them again.
        try await MicrophoneAccessGate.ensureAccess(access, mayPrompt: false)
        _ = try MicrophoneAccessGate.expectedInput(access, matching: configuration.sourceIDs)
        // Checked again after the suspension above, so two overlapping starts
        // cannot both build an engine.
        guard session == nil else { throw AudioCaptureError.alreadyCapturing }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            logger.error("Microphone refused: the input reported no usable format")
            throw AudioCaptureError.microphoneUnavailable
        }

        let tap = MicrophoneTap(consumer: consumer)
        input.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: format, block: tap.block())
        let observer = Self.observeConfigurationChanges(of: engine, tap: tap) { [weak self] in
            Task { await self?.handleConfigurationChange() }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            tap.invalidate()
            input.removeTap(onBus: 0)
            NotificationCenter.default.removeObserver(observer)
            logger.error("Microphone failed to start")
            throw AudioCaptureError.systemFailure(error.localizedDescription)
        }

        session = Session(engine: engine, tap: tap, configurationObserver: observer)
        logger.info(
            """
            Microphone listening at \(format.sampleRate, format: .fixed(precision: 0), privacy: .public) Hz, \
            \(format.channelCount, privacy: .public) channel(s)
            """
        )
    }

    func stop() async {
        guard let session else { return }
        self.session = nil
        Self.tearDown(session)
        logger.info("Microphone stopped")
    }

    /// Handles the engine stopping because the audio configuration changed.
    ///
    /// The engine has already stopped itself by the time this runs; what is
    /// left is to release it and to say so. A notification that arrives for
    /// an engine this capturer has already let go of changes nothing.
    private func handleConfigurationChange() {
        guard let session else { return }
        self.session = nil
        Self.tearDown(session)
        logger.error("Microphone stream ended: the audio configuration changed")
        interruptionContinuation.yield(.interrupted(Self.configurationChangeDescription))
    }

    /// Stops a session's engine and detaches everything from it.
    ///
    /// - Parameter session: The session to end.
    private nonisolated static func tearDown(_ session: Session) {
        session.tap.invalidate()
        NotificationCenter.default.removeObserver(session.configurationObserver)
        session.engine.inputNode.removeTap(onBus: 0)
        session.engine.stop()
    }

    /// Watches one engine for configuration changes.
    ///
    /// Built outside the actor so the observer's closure carries no actor
    /// isolation: the notification is posted on whatever thread the engine
    /// chooses, and the only thing done there is to stop the tap and hop
    /// back.
    ///
    /// - Parameters:
    ///   - engine: The engine to watch.
    ///   - tap: The tap to stop forwarding the moment the change is seen.
    ///   - onChange: Called once per notification.
    /// - Returns: The observer token, to remove when the session ends.
    private nonisolated static func observeConfigurationChanges(
        of engine: AVAudioEngine,
        tap: MicrophoneTap,
        onChange: @escaping @Sendable () -> Void
    ) -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { _ in
            tap.invalidate()
            onChange()
        }
    }
}

/// The tap on the microphone's input node.
///
/// Kept deliberately thin, like application capture's stream output: it
/// decides whether a buffer is still wanted, adapts it, and hands it on.
/// Everything else — state, ordering, teardown — belongs to the actor.
nonisolated final class MicrophoneTap: Sendable {
    private let consumer: AudioSampleConsuming
    private let isActive = Mutex(true)

    /// Creates a tap.
    ///
    /// - Parameter consumer: Receives adapted buffers on the engine's thread.
    init(consumer: AudioSampleConsuming) {
        self.consumer = consumer
    }

    /// Stops the tap forwarding anything further.
    ///
    /// A buffer can still be in flight when a stop is requested; after this it
    /// is discarded rather than counted as audio that outlived the meeting.
    func invalidate() {
        isActive.withLock { $0 = false }
    }

    /// The block the engine calls with each buffer.
    ///
    /// Built here, outside any actor, so the engine can call it on its own
    /// thread without the block asserting an isolation it does not have.
    func block() -> AVAudioNodeTapBlock {
        { [self] buffer, time in deliver(buffer, at: time) }
    }

    /// Adapts one buffer and delivers the result.
    ///
    /// - Parameters:
    ///   - buffer: The audio the engine delivered.
    ///   - time: When the engine says it began.
    func deliver(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime?) {
        guard isActive.withLock({ $0 }) else { return }
        guard let pieces = MicrophonePCMBufferAdapter.buffers(from: buffer, at: time) else {
            consumer.recordUnreadableSample()
            return
        }
        for piece in pieces { consumer.consume(piece) }
    }
}
