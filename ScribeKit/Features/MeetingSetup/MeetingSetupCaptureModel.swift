//
//  MeetingSetupCaptureModel.swift
//  ScribeKit
//

import Foundation

/// Owns the live pipeline behind the meeting setup screen: capture, on-device
/// recognition, and the relationship between them.
///
/// The model drives an ``AudioCapturing`` and a ``SpeechTranscribing`` value
/// and never touches ScreenCaptureKit or the Speech framework, so the screen's
/// behaviour is testable without capture permission, a speech model or a real
/// meeting.
///
/// Audio does not pass through here. The capturer delivers buffers on its own
/// queue to a fan-out consumer that feeds the activity summary and the
/// transcriber; the main actor sees coalesced summaries and transcription
/// events only.
@MainActor
@Observable
final class MeetingSetupCaptureModel {

    /// How many times a recogniser that stops by itself is restarted before
    /// the run is reported as failed.
    ///
    /// Bounded deliberately: a recogniser that fails repeatedly is a condition
    /// to report, not one to paper over with retries.
    static let maximumRecoveryAttempts = 2

    /// The capture subsystem's current state.
    private(set) var captureState: AudioCaptureState = .idle

    /// The recognition subsystem's current state.
    private(set) var transcriptionState: TranscriptionState = .idle

    /// Whether on-device recognition can run in the selected locale.
    private(set) var availability: SpeechRecognitionAvailability = .unknown

    /// What capture has delivered since it last started.
    private(set) var activity: AudioCaptureActivity = .none

    /// The locales the recogniser offers, installed ones first in the list's
    /// own order.
    private(set) var availableLocales: [TranscriptionLocale] = []

    /// The BCP-47 locale recognition uses.
    private(set) var localeIdentifier = TranscriptionConfiguration.systemLocaleIdentifier()

    /// The transcript produced by the current run.
    let transcript: LiveTranscriptModel

    private let capturer: AudioCapturing
    private let transcriber: any SpeechTranscribing
    private let monitor: AudioCaptureActivityMonitor
    private var recoveryAttempts = 0

    /// Observes the capturer's interruptions for as long as the model exists.
    private var interruptionTask: Task<Void, Never>?

    /// Observes transcription events for as long as the model exists.
    private var eventTask: Task<Void, Never>?

    /// Creates a model with its own capture and recognition stack.
    ///
    /// - Parameters:
    ///   - monitor: Accumulates delivered audio. Defaults to a fresh monitor,
    ///     which the model connects to its own published activity.
    ///   - transcriber: Turns captured audio into transcription events. The
    ///     default is the on-device Apple recogniser; tests substitute a fake.
    ///   - transcript: The transcript the run fills in. A fresh one by
    ///     default.
    ///   - makeCapturer: Builds the capturer around the audio consumers. The
    ///     default builds the ScreenCaptureKit implementation; tests
    ///     substitute a fake.
    init(
        monitor: AudioCaptureActivityMonitor = AudioCaptureActivityMonitor(),
        transcriber: any SpeechTranscribing = AppleSpeechTranscriber(),
        transcript: LiveTranscriptModel? = nil,
        makeCapturer: (AudioSampleConsuming) -> AudioCapturing = {
            ScreenCaptureKitAudioCapturer(consumer: $0)
        }
    ) {
        self.monitor = monitor
        self.transcriber = transcriber
        self.transcript = transcript ?? LiveTranscriptModel()
        self.capturer = makeCapturer(BroadcastingAudioSampleConsumer([monitor, transcriber]))
        monitor.onUpdate = { [weak self] activity in
            Task { @MainActor [weak self] in self?.activity = activity }
        }
        let interruptions = capturer.interruptions
        interruptionTask = Task { [weak self] in
            for await error in interruptions {
                self?.handleCaptureInterruption(error)
            }
        }
        let events = transcriber.events
        eventTask = Task { [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }
    }

    // MARK: - Configuration

    /// The configuration the next run would use.
    var configuration: TranscriptionConfiguration {
        TranscriptionConfiguration(localeIdentifier: localeIdentifier)
    }

    /// Loads the recogniser's locales and checks whether it can run.
    ///
    /// Called when the screen appears. The locale defaults to the system's own
    /// when the recogniser supports it, and otherwise to the first installed
    /// locale, so a usable default is offered without ever changing the
    /// language of a run that is already configured.
    func prepare() async {
        availableLocales = await transcriber.availableLocales()
        if !availableLocales.contains(where: { $0.id == localeIdentifier }),
           let fallback = availableLocales.first(where: \.isInstalled) {
            localeIdentifier = fallback.id
        }
        await refreshAvailability()
    }

    /// Selects the locale recognition runs in.
    ///
    /// The selection is explicit and takes effect on the next run. ScribeKit
    /// never changes the recognition language on its own.
    ///
    /// - Parameter identifier: A BCP-47 identifier from ``availableLocales``.
    func selectLocale(_ identifier: String) async {
        guard identifier != localeIdentifier, !isRunning else { return }
        localeIdentifier = identifier
        await refreshAvailability()
    }

    /// Rechecks whether recognition can run in the selected locale.
    func refreshAvailability() async {
        availability = await transcriber.availability(for: configuration)
    }

    // MARK: - Lifecycle

    /// Whether the pipeline is running or in the middle of starting or
    /// stopping.
    var isRunning: Bool { captureState.isActive || transcriptionState.isActive }

    /// Whether the interface should offer to start.
    ///
    /// - Parameter sources: The applications currently selected.
    /// - Returns: `true` when a start would be meaningful.
    func canStart(sources: [CaptureSource]) -> Bool {
        captureState.canStart && transcriptionState.canStart
            && !sources.isEmpty && availability.canTranscribe
    }

    /// Whether the interface should offer to stop.
    var canStop: Bool { captureState.canStop || transcriptionState.canStop }

    /// Starts recognition and then capture.
    ///
    /// Recognition is started first: capturing audio nothing will transcribe
    /// would hold system resources for no result. If capture then fails, the
    /// recogniser is stopped again, so a failed start never leaves half a
    /// pipeline running. An empty selection and unavailable recognition are
    /// reported as failures rather than passed over in silence.
    ///
    /// - Parameter sources: The applications the user selected.
    func start(sources: [CaptureSource]) async {
        guard captureState.canStart, transcriptionState.canStart else { return }
        guard !sources.isEmpty else {
            captureState = .failed(
                message: AudioCaptureError.noSourcesSelected.errorDescription ?? ""
            )
            return
        }
        guard availability.canTranscribe else {
            transcriptionState = .failed(
                message: TranscriptionError.unavailable(availability).errorDescription ?? ""
            )
            return
        }

        transcriptionState = .preparing
        captureState = .preparing
        recoveryAttempts = 0
        monitor.reset()
        activity = .none
        transcript.begin()

        do {
            try await transcriber.start(configuration: configuration)
            transcriptionState = .transcribing
        } catch {
            transcriptionState = .failed(message: message(for: error, sources: sources))
            captureState = .idle
            await refreshAvailability()
            return
        }

        do {
            try await capturer.start(configuration: AudioCaptureConfiguration(sources: sources))
            captureState = .capturing
        } catch {
            await transcriber.stop()
            transcriptionState = .idle
            captureState = .failed(message: message(for: error, sources: sources))
        }
    }

    /// Stops capture and then recognition.
    ///
    /// Capture is stopped first so no audio arrives after the recogniser has
    /// closed its input; the recogniser then finalises whatever it has already
    /// accepted, so the last sentence of a meeting is not lost.
    func stop() async {
        guard canStop else { return }
        captureState = .stopping
        transcriptionState = .stopping
        await capturer.stop()
        captureState = .idle
        await transcriber.stop()
        transcriptionState = .idle
    }

    // MARK: - Events

    /// Applies a transcription event to the transcript, and recovers from a
    /// recogniser that stopped by itself.
    ///
    /// - Parameter event: What the transcriber reported.
    private func handle(_ event: TranscriptionEvent) async {
        transcript.apply(event)
        guard case .interrupted(.recognitionFailed) = event else { return }
        await recoverRecognition()
    }

    /// Restarts a recogniser that stopped by itself, while capture continues.
    ///
    /// Audio that arrives while the recogniser is being rebuilt is not
    /// transcribed, so the gap is measured and recorded as untranscribed time
    /// rather than passed over.
    private func recoverRecognition() async {
        guard captureState == .capturing, transcriptionState == .transcribing else { return }
        guard recoveryAttempts < Self.maximumRecoveryAttempts else {
            transcriptionState = .failed(
                message: "Speech recognition stopped repeatedly and was not restarted again."
            )
            return
        }

        recoveryAttempts += 1
        transcriptionState = .recovering
        let startedRecovery = Date()
        await transcriber.stop()
        do {
            try await transcriber.start(configuration: configuration)
            transcriptionState = .transcribing
        } catch {
            transcriptionState = .failed(message: message(for: error, sources: []))
        }
        transcript.apply(.interrupted(.audioDropped(seconds: Date().timeIntervalSince(startedRecovery))))
    }

    /// Records the capture system ending a stream by itself, and stops
    /// recognition, which now has nothing to transcribe.
    ///
    /// - Parameter error: The reason capture ended.
    private func handleCaptureInterruption(_ error: AudioCaptureError) {
        guard captureState.isActive else { return }
        captureState = .failed(message: message(for: error, sources: []))
        guard transcriptionState.isActive else { return }
        transcriptionState = .stopping
        Task { [weak self, transcriber] in
            await transcriber.stop()
            self?.transcriptionState = .idle
        }
    }

    /// Converts a capture or transcription error into a message for the
    /// screen.
    ///
    /// Unavailable sources are named rather than listed by bundle identifier
    /// when the selection they came from is known.
    ///
    /// - Parameters:
    ///   - error: The error the subsystem reported.
    ///   - sources: The selection the start was made from, used to name
    ///     applications.
    /// - Returns: A user-facing description.
    private func message(for error: Error, sources: [CaptureSource]) -> String {
        if case let AudioCaptureError.sourcesUnavailable(identifiers) = error, !sources.isEmpty {
            let names = identifiers.map { identifier in
                sources.first { $0.id == identifier }?.displayName ?? identifier
            }
            return "No longer running, so capture did not start: " + names.formatted(.list(type: .and))
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
