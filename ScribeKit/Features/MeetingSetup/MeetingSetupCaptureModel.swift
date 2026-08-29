//
//  MeetingSetupCaptureModel.swift
//  ScribeKit
//

import Foundation

/// Owns the live pipeline behind the meeting setup screen: capture, on-device
/// recognition, durable transcript writing, and the order between them.
///
/// The model drives an ``AudioCapturing``, a ``SpeechTranscribing`` and a
/// ``TranscriptPersisting`` value and never touches ScreenCaptureKit, the
/// Speech framework or the filesystem itself, so a whole meeting is testable
/// without capture permission, a speech model, a save folder or a disk.
///
/// Audio does not pass through here. The capturer delivers buffers on its own
/// queue to a fan-out consumer that feeds the activity summary and the
/// transcriber; the main actor sees coalesced summaries and transcription
/// events only, and file writes happen on the writer's own executor.
///
/// The durability invariant this type is responsible for: a finalised span the
/// writer accepted is never discarded, and a stop does not report a finished
/// meeting until every event the recogniser produced has been handled and the
/// transcript has been flushed and closed.
@MainActor
@Observable
final class MeetingSetupCaptureModel {

    /// How many times a recogniser that stops by itself is restarted before
    /// the run is reported as failed.
    ///
    /// Bounded deliberately: a recogniser that fails repeatedly is a condition
    /// to report, not one to paper over with retries.
    static let maximumRecoveryAttempts = 2

    /// What the interface says when recognition outran the event buffer.
    ///
    /// Overflow means finalised speech that no consumer saw, so it cannot be
    /// written and must not be passed over. The meeting is stopped and the
    /// transcript is described as incomplete.
    static let droppedEventsMessage = """
        Recognition produced results faster than they could be saved, so some finalised speech was lost. \
        The transcript is incomplete and the meeting was stopped.
        """

    /// The capture subsystem's current state.
    private(set) var captureState: AudioCaptureState = .idle

    /// The recognition subsystem's current state.
    private(set) var transcriptionState: TranscriptionState = .idle

    /// The durable transcript's current state.
    private(set) var persistenceState: TranscriptPersistenceState = .idle

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
    private let persistence: any TranscriptPersisting
    private let monitor: AudioCaptureActivityMonitor
    private var recoveryAttempts = 0

    /// How many transcription events have been handled, counted over the
    /// transcriber's whole life so it can be compared with its tally.
    private var handledEventCount = 0

    /// The dropped-event count when the current run started, so only this
    /// run's overflow is reported.
    private var droppedEventBaseline = 0

    /// The handled-event count a stop is waiting to reach, and everyone
    /// waiting for it. There can be more than one waiter: a user stopping a
    /// meeting the capture system has just interrupted asks twice.
    private var drainTarget: Int?
    private var drainContinuations: [CheckedContinuation<Void, Never>] = []

    /// Observes the capturer's interruptions for as long as the model exists.
    private var interruptionTask: Task<Void, Never>?

    /// Observes transcription events for as long as the model exists.
    private var eventTask: Task<Void, Never>?

    /// Creates a model with its own capture, recognition and writing stack.
    ///
    /// - Parameters:
    ///   - monitor: Accumulates delivered audio. Defaults to a fresh monitor,
    ///     which the model connects to its own published activity.
    ///   - transcriber: Turns captured audio into transcription events. The
    ///     default is the on-device Apple recogniser; tests substitute a fake.
    ///   - persistence: Writes the durable Markdown transcript. The default
    ///     writes real files; tests substitute a double.
    ///   - transcript: The transcript the run fills in. A fresh one by
    ///     default.
    ///   - makeCapturer: Builds the capturer around the audio consumers. The
    ///     default builds the ScreenCaptureKit implementation; tests
    ///     substitute a fake.
    init(
        monitor: AudioCaptureActivityMonitor = AudioCaptureActivityMonitor(),
        transcriber: any SpeechTranscribing = AppleSpeechTranscriber(),
        persistence: any TranscriptPersisting = MarkdownTranscriptStore(),
        transcript: LiveTranscriptModel? = nil,
        makeCapturer: (AudioSampleConsuming) -> AudioCapturing = {
            ScreenCaptureKitAudioCapturer(consumer: $0)
        }
    ) {
        self.monitor = monitor
        self.transcriber = transcriber
        self.persistence = persistence
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

    /// Whether a meeting is running or in the middle of starting or stopping.
    var isRunning: Bool {
        captureState.isActive || transcriptionState.isActive || persistenceState.isActive
    }

    /// Whether the interface should offer to start a meeting.
    ///
    /// - Parameter request: What the screen would start, or `nil` when the
    ///   settings do not describe a startable meeting yet.
    /// - Returns: `true` when a start would be meaningful.
    func canStart(_ request: MeetingStartRequest?) -> Bool {
        guard let request else { return false }
        return captureState.canStart && transcriptionState.canStart && !persistenceState.isActive
            && !request.sources.isEmpty && availability.canTranscribe
    }

    /// Whether the interface should offer to stop.
    var canStop: Bool { captureState.canStop || transcriptionState.canStop }

    /// Starts a meeting: the transcript file, then recognition, then capture.
    ///
    /// The order is the order of dependency. The transcript is created first,
    /// because a meeting that cannot be saved should not capture anything at
    /// all; recognition next, because capturing audio nothing will transcribe
    /// holds system resources for no result; capture last. Every step undoes
    /// the ones before it when it fails, so a failed start never leaves a file
    /// open, a folder leased or half a pipeline running.
    ///
    /// - Parameter request: The meeting to start.
    func start(_ request: MeetingStartRequest) async {
        guard captureState.canStart, transcriptionState.canStart, !persistenceState.isActive else { return }
        guard !request.sources.isEmpty else {
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

        let startedAt = Date()
        persistenceState = .preparing
        transcriptionState = .preparing
        captureState = .preparing
        recoveryAttempts = 0
        droppedEventBaseline = transcriber.eventTally.dropped
        monitor.reset()
        activity = .none
        transcript.begin(at: startedAt)

        do {
            let layout = try await persistence.startSession(
                request.makeSession(createdAt: startedAt),
                localeIdentifier: localeIdentifier,
                startedAt: startedAt
            )
            persistenceState = .saving(layout)
        } catch {
            persistenceState = .failed(message: message(for: error, sources: []), layout: nil)
            transcriptionState = .idle
            captureState = .idle
            return
        }

        do {
            try await transcriber.start(configuration: configuration)
            transcriptionState = .transcribing
        } catch {
            transcriptionState = .failed(message: message(for: error, sources: request.sources))
            captureState = .idle
            await closeSession()
            await refreshAvailability()
            return
        }

        do {
            try await capturer.start(configuration: AudioCaptureConfiguration(sources: request.sources))
            captureState = .capturing
        } catch {
            await transcriber.stop()
            transcriptionState = .idle
            captureState = .failed(message: message(for: error, sources: request.sources))
            await closeSession()
        }
    }

    /// Stops the meeting, in the order that loses nothing.
    ///
    /// Capture stops first so no audio arrives after the recogniser has closed
    /// its input; the recogniser then finalises what it has already accepted,
    /// so the last sentence of a meeting is not lost; every event it produced
    /// is handled and written before the transcript is flushed and closed.
    /// Only then is the folder lease released and the meeting reported as
    /// over.
    func stop() async {
        guard canStop else { return }
        captureState = .stopping
        transcriptionState = .stopping
        await capturer.stop()
        captureState = .idle
        await transcriber.stop()
        transcriptionState = .idle
        await drainPendingEvents()
        await closeSession()
    }

    /// Waits until every event the recogniser published has been handled.
    ///
    /// A finalised span reaches this model through an asynchronous stream, so
    /// a stop that closed the transcript as soon as the recogniser returned
    /// could close it on a sentence still in flight. The recogniser's tally
    /// says how many events exist; the handler says how many have been dealt
    /// with; this waits for the second to catch up with the first, without
    /// polling.
    private func drainPendingEvents() async {
        let published = transcriber.eventTally.published
        guard handledEventCount < published else { return }
        await withCheckedContinuation { continuation in
            drainTarget = max(drainTarget ?? published, published)
            drainContinuations.append(continuation)
        }
    }

    /// Finishes the durable transcript and releases the folder.
    ///
    /// A session that has already failed is left alone: its resources were
    /// released when it failed, and overwriting the failure with a success
    /// would be the one thing this model must never do.
    private func closeSession() async {
        guard persistenceState.isActive else { return }
        let layout = persistenceState.layout
        do {
            try await persistence.finishSession(endedAt: Date())
            persistenceState = layout.map { .saved($0) } ?? .idle
        } catch {
            persistenceState = .failed(message: message(for: error, sources: []), layout: layout)
        }
    }

    // MARK: - Events

    /// Applies a transcription event to the transcript, writes what is durable
    /// about it, and recovers from a recogniser that stopped by itself.
    ///
    /// - Parameter event: What the transcriber reported.
    private func handle(_ event: TranscriptionEvent) async {
        defer { completeHandling() }
        transcript.apply(event)

        guard transcriber.eventTally.dropped <= droppedEventBaseline else {
            await failPersistence(message: Self.droppedEventsMessage)
            return
        }

        switch event {
        case .partial:
            // A hypothesis is replaced by the next one and by the finalised
            // span that covers it. Writing it would record the same sentence
            // once per word.
            break
        case let .final(segment):
            await persist(segment)
        case let .interrupted(interruption):
            if let gap = interruption.gap { await persist(gap) }
            if case .recognitionFailed = interruption { await recoverRecognition() }
        }
    }

    /// Records that an event has been fully handled and releases a stop that
    /// was waiting for it.
    private func completeHandling() {
        handledEventCount += 1
        guard let target = drainTarget, handledEventCount >= target else { return }
        let waiting = drainContinuations
        drainTarget = nil
        drainContinuations = []
        for continuation in waiting { continuation.resume() }
    }

    /// Writes one finalised span to the transcript.
    ///
    /// - Parameter segment: The span the recogniser finalised.
    private func persist(_ segment: TranscriptSegment) async {
        guard case .saving = persistenceState, !segment.displayText.isEmpty else { return }
        do {
            try await persistence.appendFinalSegment(segment)
        } catch {
            await failPersistence(error)
        }
    }

    /// Writes one gap marker to the transcript.
    ///
    /// - Parameter gap: The untranscribed stretch.
    private func persist(_ gap: TranscriptGap) async {
        guard case .saving = persistenceState else { return }
        do {
            try await persistence.recordGap(gap)
        } catch {
            await failPersistence(error)
        }
    }

    /// Reports that the transcript is no longer being saved, and ends the
    /// meeting rather than continuing to transcribe into nothing.
    ///
    /// - Parameter error: What the writer reported.
    private func failPersistence(_ error: Error) async {
        await failPersistence(message: message(for: error, sources: []))
    }

    /// Reports that the transcript is no longer being saved.
    ///
    /// The writer is closed so the file and the folder lease are released, and
    /// capture and recognition are stopped separately, because continuing to
    /// recognise speech that nothing is writing down would be exactly the
    /// false impression this state exists to prevent.
    ///
    /// - Parameter message: What to tell the user.
    private func failPersistence(message: String) async {
        guard persistenceState.isActive else { return }
        persistenceState = .failed(message: message, layout: persistenceState.layout)
        try? await persistence.finishSession(endedAt: Date())
        stopSubsystemsAfterPersistenceFailure()
    }

    /// Stops capture and recognition after the transcript stopped being saved.
    ///
    /// Deliberately not ``stop()``: this runs while an event is being handled,
    /// and a stop that waited for that event to finish would wait for itself.
    /// The subsystems return to idle without a failure of their own, because
    /// nothing failed in them; ``persistenceState`` carries the reason.
    private func stopSubsystemsAfterPersistenceFailure() {
        guard canStop else { return }
        captureState = .stopping
        transcriptionState = .stopping
        Task { @MainActor [weak self] in
            guard let self else { return }
            await capturer.stop()
            captureState = .idle
            await transcriber.stop()
            transcriptionState = .idle
        }
    }

    /// Restarts a recogniser that stopped by itself, while capture continues.
    ///
    /// Audio that arrives while the recogniser is being rebuilt is not
    /// transcribed. The loss is measured by the clock, because no audio clock
    /// is running while the recogniser is down, so it is recorded as a gap
    /// whose length is known and whose position in the run is not.
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
        let lost = Date().timeIntervalSince(startedRecovery)
        transcript.apply(.interrupted(.audioDropped(seconds: lost)))
        await persist(TranscriptGap(duration: lost, reason: .recognizerRestarted))
    }

    /// Records the capture system ending a stream by itself, stops recognition
    /// and closes the transcript, which now has nothing more to receive.
    ///
    /// - Parameter error: The reason capture ended.
    private func handleCaptureInterruption(_ error: AudioCaptureError) {
        guard captureState.isActive else { return }
        captureState = .failed(message: message(for: error, sources: []))
        guard transcriptionState.isActive || persistenceState.isActive else { return }
        transcriptionState = .stopping
        Task { @MainActor [weak self] in
            guard let self else { return }
            await transcriber.stop()
            transcriptionState = .idle
            await drainPendingEvents()
            await closeSession()
        }
    }

    /// Converts a capture, transcription or persistence error into a message
    /// for the screen.
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
