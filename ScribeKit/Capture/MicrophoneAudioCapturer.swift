//
//  MicrophoneAudioCapturer.swift
//  ScribeKit
//

import AudioToolbox
import AVFAudio
import CoreAudio
import Foundation
import OSLog
import Synchronization

/// Listens to one microphone input with `AVAudioEngine`.
///
/// The actor owns the whole framework-facing side of microphone capture: the
/// permission check, the engine, the device its input is bound to, the tap on
/// its input node, and the order of start and stop. `AVFAudio` and Core Audio
/// types stop here — callers pass ``AudioCaptureConfiguration`` and receive
/// ``CapturedPCMBuffer`` values and ``AudioCaptureError`` events, exactly as
/// they do from application capture, so everything downstream is shared.
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
/// **One device per meeting.** The engine's input is bound to the meeting's
/// device through its own audio unit's current-device property — the Mac's
/// default input is never changed to get there — and the binding is read
/// back before anything is listened to. A meeting set up for System Default
/// was resolved to a device before it started, so a default that moves later
/// neither switches the meeting nor ends it.
///
/// **Changes are judged, not assumed.** The audio engine posts one
/// configuration-change notification for a headphone plugged in, a
/// microphone unplugged and a sample rate changed alike, so the notification
/// is only a cue to look. ``MicrophoneRouteMonitor`` reads what Core Audio
/// and the engine report and ``MicrophoneRouteAssessment`` decides: a meeting
/// whose device is still there, still bound, still in its format and still
/// running keeps listening; anything else ends it as an interruption. It never
/// restarts on another device, which would put a second person's speech into a
/// transcript without anyone deciding it should.
actor MicrophoneAudioCapturer: AudioCapturing {

    /// Frames requested per tap callback. The engine treats this as a hint
    /// and may deliver more; the adapter cuts whatever arrives into pieces.
    private static let tapBufferSize: AVAudioFrameCount = 4_800

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
        let monitor: MicrophoneRouteMonitor
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
    /// input the meeting was set up with is connected.
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
        let input = try MicrophoneAccessGate.expectedInput(access, matching: configuration.sourceIDs)
        // Checked again after the suspension above, so two overlapping starts
        // cannot both build an engine.
        guard session == nil else { throw AudioCaptureError.alreadyCapturing }

        let engine = AVAudioEngine()
        let node = engine.inputNode
        let device = try Self.bind(node, to: input)
        let format = node.outputFormat(forBus: 0)

        let tap = MicrophoneTap(consumer: consumer)
        node.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: format, block: tap.block())

        let baseline = MicrophoneRouteBaseline(
            inputID: input.id,
            format: MicrophoneStreamFormat(format),
            defaultInputID: CoreAudioInputDevices.defaultInputDevice().flatMap(CoreAudioInputDevices.uid(of:))
        )
        let monitor = MicrophoneRouteMonitor(engine: engine, device: device, baseline: baseline, tap: tap)

        engine.prepare()
        do {
            try engine.start()
        } catch {
            tap.invalidate()
            node.removeTap(onBus: 0)
            logger.error("Microphone failed to start")
            throw AudioCaptureError.systemFailure(error.localizedDescription)
        }

        session = Session(engine: engine, tap: tap, monitor: monitor)
        monitor.start { [weak self, weak monitor] loss in
            guard let monitor else { return }
            Task { await self?.handleRouteLoss(loss, reportedBy: monitor) }
        }
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

    /// Ends the session because its input is gone or different.
    ///
    /// The tap was already stopped where the loss was seen, so nothing heard
    /// after it reached the meeting. A loss reported for a session this
    /// capturer has already let go of — one that was stopped, or replaced by
    /// a resume — changes nothing.
    ///
    /// - Parameters:
    ///   - loss: What happened to the input.
    ///   - monitor: The monitor that saw it, which names the session.
    private func handleRouteLoss(_ loss: MicrophoneRouteLoss, reportedBy monitor: MicrophoneRouteMonitor) {
        guard let session, session.monitor === monitor else { return }
        self.session = nil
        Self.tearDown(session)
        logger.error("Microphone stream ended: \(loss.rawValue, privacy: .public)")
        interruptionContinuation.yield(.interrupted(loss.interruptionDescription))
    }

    /// Stops a session's engine and detaches everything from it.
    ///
    /// The monitor goes first, so no assessment reads the engine while it is
    /// being stopped.
    ///
    /// - Parameter session: The session to end.
    private nonisolated static func tearDown(_ session: Session) {
        session.monitor.cancel()
        session.tap.invalidate()
        session.engine.inputNode.removeTap(onBus: 0)
        session.engine.stop()
    }

    /// Binds an input node's audio unit to one device, confirms it took, and
    /// matches the unit's output to the device's own format.
    ///
    /// This sets the device of ScribeKit's own audio unit — the property
    /// Technical Note TN2091 documents for choosing the input of a HAL output
    /// unit — and nothing system-wide. It is done before the engine starts.
    ///
    /// Binding alone is not enough. Measured on a Mac whose default input was
    /// a 24 kHz Bluetooth headset, a node bound to the 48 kHz built-in
    /// microphone reported 48 kHz on its device side and still 24 kHz on the
    /// side a tap reads, the format it was created with. The HAL unit does
    /// not convert sample rates on input, so the output side is set to the
    /// device's rate and channel count before anything reads it.
    ///
    /// - Parameters:
    ///   - node: The engine's input node.
    ///   - input: The input the meeting listens to.
    /// - Returns: The bound device.
    /// - Throws: ``AudioCaptureError/microphoneDisconnected`` when the device
    ///   is not present, ``AudioCaptureError/microphoneInputChanged`` when the
    ///   unit reports another device after binding,
    ///   ``AudioCaptureError/microphoneUnavailable`` when the device reports no
    ///   usable format, and ``AudioCaptureError/systemFailure(_:)`` when the
    ///   unit refused.
    private nonisolated static func bind(_ node: AVAudioInputNode, to input: MicrophoneInput) throws -> AudioObjectID {
        guard let device = CoreAudioInputDevices.device(forUID: input.id), CoreAudioInputDevices.isAlive(device) else {
            throw AudioCaptureError.microphoneDisconnected
        }
        guard let unit = node.audioUnit else {
            throw AudioCaptureError.systemFailure("the audio input has no audio unit")
        }
        var selected = device
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selected,
            UInt32(MemoryLayout<AudioObjectID>.size)
        )
        guard status == noErr else {
            throw AudioCaptureError.systemFailure("the microphone could not be selected (\(status))")
        }
        guard MicrophoneRouteMonitor.currentDevice(of: node) == device else {
            throw AudioCaptureError.microphoneInputChanged
        }

        let hardware = node.inputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0,
              let client = AVAudioFormat(standardFormatWithSampleRate: hardware.sampleRate, channels: hardware.channelCount)
        else {
            throw AudioCaptureError.microphoneUnavailable
        }
        var description = client.streamDescription.pointee
        let formatStatus = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &description,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard formatStatus == noErr, MicrophoneStreamFormat(node.outputFormat(forBus: 0)) == MicrophoneStreamFormat(hardware)
        else {
            throw AudioCaptureError.systemFailure("the microphone's format could not be matched (\(formatStatus))")
        }
        return device
    }
}

/// Watches a running Microphone meeting's input and reports when it is lost.
///
/// Three things can say the input may have changed: the engine's
/// configuration-change notification, the bound device's alive property, and
/// Core Audio's device list and default input. Each is only a cue. On any of
/// them the monitor reads the evidence — is the device there, is the unit
/// still bound to it, is the format the tap's, is the engine running — and
/// ``MicrophoneRouteAssessment`` decides. Every cue is handled on one serial
/// queue, and a loss stops the tap before it is reported, so nothing heard
/// from a different microphone can reach the meeting while the actor catches
/// up.
nonisolated final class MicrophoneRouteMonitor: @unchecked Sendable {
    // @unchecked: `AVAudioEngine` is not `Sendable`. The engine is only read
    // here, and only while `state` is locked; teardown takes the same lock
    // before stopping it, so no read overlaps a stop.

    private struct State {
        var isActive = true
        var observer: (any NSObjectProtocol)?
        var listeners: [CoreAudioPropertyListener] = []
    }

    private let engine: AVAudioEngine
    private let device: AudioObjectID
    private let baseline: MicrophoneRouteBaseline
    private let tap: MicrophoneTap
    private let queue = DispatchQueue(label: "com.scribekit.microphone.route")
    private let state = Mutex(State())
    private let logger = ScribeKitLog.capture

    /// Creates a monitor. Nothing is watched until ``start(onLoss:)``.
    ///
    /// - Parameters:
    ///   - engine: The running engine.
    ///   - device: The device its input is bound to.
    ///   - baseline: What the meeting started with.
    ///   - tap: The tap to stop the moment a loss is seen.
    init(engine: AVAudioEngine, device: AudioObjectID, baseline: MicrophoneRouteBaseline, tap: MicrophoneTap) {
        self.engine = engine
        self.device = device
        self.baseline = baseline
        self.tap = tap
    }

    /// Begins watching, and assesses once straight away so a change that
    /// happened while the engine was starting is not missed.
    ///
    /// - Parameter onLoss: Called at most once, on the monitor's queue, when
    ///   the input is lost. The tap has already stopped by then.
    func start(onLoss: @escaping @Sendable (MicrophoneRouteLoss) -> Void) {
        let operations = OperationQueue()
        operations.underlyingQueue = queue
        operations.maxConcurrentOperationCount = 1
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: operations
        ) { [weak self] _ in
            self?.evaluate(onLoss: onLoss)
        }
        let listeners = [
            CoreAudioPropertyListener.listen(to: kAudioDevicePropertyDeviceIsAlive, of: device, on: queue) {
                [weak self] in self?.evaluate(onLoss: onLoss)
            },
            CoreAudioPropertyListener.listen(to: kAudioHardwarePropertyDevices, on: queue) {
                [weak self] in self?.evaluate(onLoss: onLoss)
            },
            CoreAudioPropertyListener.listen(to: kAudioHardwarePropertyDefaultInputDevice, on: queue) {
                [weak self] in self?.evaluate(onLoss: onLoss)
            }
        ].compactMap { $0 }

        let stale = state.withLock { state -> Bool in
            guard state.isActive else { return true }
            state.observer = observer
            state.listeners = listeners
            return false
        }
        if stale {
            NotificationCenter.default.removeObserver(observer)
            for listener in listeners { listener.cancel() }
            return
        }
        queue.async { [weak self] in self?.evaluate(onLoss: onLoss) }
    }

    /// Stops watching. After it returns no assessment is running and none
    /// will start.
    func cancel() {
        let (observer, listeners) = state.withLock { state in
            state.isActive = false
            defer {
                state.observer = nil
                state.listeners = []
            }
            return (state.observer, state.listeners)
        }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        for listener in listeners { listener.cancel() }
    }

    /// Reads the evidence and acts on the assessment.
    ///
    /// - Parameter onLoss: Called when the input is lost.
    private func evaluate(onLoss: @Sendable (MicrophoneRouteLoss) -> Void) {
        let assessment = state.withLock { state -> MicrophoneRouteAssessment? in
            guard state.isActive else { return nil }
            let assessment = MicrophoneRouteAssessment.assess(observe(), against: baseline)
            if case .lost = assessment {
                state.isActive = false
                tap.invalidate()
            }
            return assessment
        }
        switch assessment {
        case let .lost(loss)?:
            onLoss(loss)
        case let .unaffected(change)?:
            logger.notice("Microphone route changed (\(change.rawValue, privacy: .public)); still listening")
        case nil:
            return
        }
    }

    /// What Core Audio and the engine report now.
    ///
    /// The format is the device side's. The side the tap reads was set once,
    /// at the start, and does not follow the device, so a device that changed
    /// its sample rate shows only here.
    private func observe() -> MicrophoneRouteObservation {
        let node = engine.inputNode
        let format = node.inputFormat(forBus: 0)
        return MicrophoneRouteObservation(
            inputIsPresent: CoreAudioInputDevices.isAlive(device)
                && CoreAudioInputDevices.device(forUID: baseline.inputID) == device,
            listeningInputID: Self.currentDevice(of: node).flatMap(CoreAudioInputDevices.uid(of:)),
            format: format.sampleRate > 0 && format.channelCount > 0 ? MicrophoneStreamFormat(format) : nil,
            engineIsRunning: engine.isRunning,
            defaultInputID: CoreAudioInputDevices.defaultInputDevice().flatMap(CoreAudioInputDevices.uid(of:))
        )
    }

    /// The device an input node's audio unit is bound to.
    ///
    /// - Parameter node: The engine's input node.
    /// - Returns: The device, or `nil` when the unit did not say.
    static func currentDevice(of node: AVAudioInputNode) -> AudioObjectID? {
        guard let unit = node.audioUnit else { return nil }
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioUnitGetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, &size
        )
        guard status == noErr, device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return device
    }
}

nonisolated extension MicrophoneStreamFormat {
    /// The shape of an engine format.
    ///
    /// - Parameter format: The format.
    init(_ format: AVAudioFormat) {
        self.init(sampleRate: format.sampleRate, channelCount: Int(format.channelCount))
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
