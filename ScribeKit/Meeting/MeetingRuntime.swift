//
//  MeetingRuntime.swift
//  ScribeKit
//

import Foundation

/// Owns the live pipeline of the one meeting the application can be running:
/// capture, on-device recognition, durable transcript writing, optional audio
/// retention, and the order between them.
///
/// One of these exists, it is created by the application delegate and it lives
/// as long as the process does. That is the point: a meeting is application
/// state, not presentation state. A window that is hidden, minimised, closed
/// or rebuilt is asking to see a meeting, never deciding whether one exists,
/// so views may request a start or a stop and observe what happens, and a view
/// going away neither stops capture nor starts a second pipeline.
///
/// There is at most one active meeting, enforced here rather than by whichever
/// window happens to be open: ``start(_:)`` refuses while anything is running.
///
/// The model drives an ``AudioCapturing``, a ``SpeechTranscribing``, a
/// ``TranscriptPersisting`` and an ``AudioRetaining`` value and never touches
/// ScreenCaptureKit, the Speech framework, a codec or the filesystem itself, so
/// a whole meeting is testable without capture permission, a speech model, a
/// save folder or a disk.
///
/// Audio does not pass through here. The capturer delivers buffers on its own
/// queue to a fan-out consumer that feeds the activity summary, the transcriber
/// and — when the user asked to keep audio — the retainer that writes them to a
/// file. The main actor sees coalesced summaries and transcription events only;
/// transcript writes happen on the writer's own executor and audio writes on
/// the capture queue.
///
/// The durability invariant this type is responsible for: a finalised span the
/// writer accepted is never discarded, and a stop does not report a finished
/// meeting until every event the recogniser produced has been handled and every
/// durable artifact the meeting enabled — the transcript, and the audio file
/// when there is one — has been flushed and closed.
@MainActor
@Observable
final class MeetingRuntime {

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
    private(set) var captureState: AudioCaptureState = .idle {
        didSet { synchronizeActivity() }
    }

    /// The recognition subsystem's current state.
    private(set) var transcriptionState: TranscriptionState = .idle {
        didSet { synchronizeActivity() }
    }

    /// The durable transcript's current state.
    private(set) var persistenceState: TranscriptPersistenceState = .idle {
        didSet { synchronizeActivity() }
    }

    /// The retained audio file's current state. Stays ``AudioRetentionState/idle``
    /// for the whole of a meeting that keeps no audio.
    private(set) var audioRetentionState: AudioRetentionState = .idle {
        didSet { synchronizeActivity() }
    }

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

    /// The meeting that is running, or the last one that ran.
    ///
    /// Set when a meeting starts and left in place afterwards, so a window
    /// opened after a meeting finished or failed still has something to name.
    /// ``status`` says whether it is live.
    private(set) var meeting: MeetingSnapshot?

    /// How long the current meeting has been running.
    let elapsed: MeetingElapsedClock

    private let capturer: AudioCapturing
    private let transcriber: any SpeechTranscribing
    private let persistence: any TranscriptPersisting
    private let audio: any AudioRetaining
    private let monitor: AudioCaptureActivityMonitor
    private let processActivity: any MeetingActivityAsserting
    private var recoveryAttempts = 0

    /// How much audio this meeting has captured, in media time.
    private let mediaClock: CapturedMediaClock

    /// Reads the wall clock. Tests substitute a controllable one so a pause
    /// can last minutes without anything sleeping.
    private let now: () -> Date

    /// Seconds of captured audio that came before the current recognition run.
    ///
    /// A recogniser restarted by a resume begins its own timeline at zero, so
    /// its offsets are run-local. This is what turns them back into offsets
    /// from the meeting's first captured frame — the one origin the transcript,
    /// the retained recording and review playback all share. It is media time,
    /// so a pause adds nothing to it; wall-clock time is mapped separately.
    private var mediaOffsetBase: Double = 0

    /// The base a recognition run started mid-capture must use, and the
    /// handled-event count at which it may take effect.
    ///
    /// A pause can change ``mediaOffsetBase`` the moment it has drained,
    /// because by then every event the old run published has been handled. A
    /// recogniser that restarted itself cannot: the restart happens inside the
    /// handler for the event that reported the failure, so it cannot wait for
    /// that event — or for the trailing report the old run publishes as it
    /// closes — without waiting for itself. The change is therefore scheduled
    /// at exactly the count a drain would have waited for, and applied by
    /// ``completeHandling()``, so an event still on the old run's timeline is
    /// never rebased onto the new one.
    private var pendingMediaOffsetBase: (base: Double, afterHandledEvents: Int)?

    /// The capture configuration the meeting started with.
    ///
    /// A resume rebuilds the stream from this rather than from the setup
    /// screen, so a meeting keeps the sources it was started with even if the
    /// selection has been edited since.
    private var captureConfiguration: AudioCaptureConfiguration?

    /// When the meeting was paused, while it still is.
    private var pausedAt: Date?

    /// Why the last pause or resume did not happen, when one did not.
    ///
    /// Kept apart from ``captureState`` deliberately: a resume that fails
    /// leaves the meeting paused, and overwriting the paused state with a
    /// failure would lose the fact that the transcript and the recording are
    /// still open and still resumable.
    private(set) var pauseFailureMessage: String?

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

    /// Observes retained-audio failures for as long as the model exists.
    private var retentionFailureTask: Task<Void, Never>?

    /// Creates a model with its own capture, recognition and writing stack.
    ///
    /// - Parameters:
    ///   - monitor: Accumulates delivered audio. Defaults to a fresh monitor,
    ///     which the model connects to its own published activity.
    ///   - transcriber: Turns captured audio into transcription events. The
    ///     default is the on-device Apple recogniser; tests substitute a fake.
    ///   - persistence: Writes the durable Markdown transcript. The default
    ///     writes real files; tests substitute a double.
    ///   - audio: Writes the retained audio file, when the meeting keeps one.
    ///     The default writes real files; tests substitute a double.
    ///   - transcript: The transcript the run fills in. A fresh one by
    ///     default.
    ///   - elapsed: Times the running meeting. A fresh one-second clock by
    ///     default; tests substitute one they advance themselves.
    ///   - processActivity: Keeps the process out of App Nap while a meeting
    ///     runs. The default asserts against the real process; tests
    ///     substitute a double so the assertion's lifetime is testable.
    ///   - now: Reads the wall clock. Tests substitute a controllable one.
    ///   - makeCapturer: Builds the capturer around the audio consumers. The
    ///     default builds the ScreenCaptureKit implementation; tests
    ///     substitute a fake.
    init(
        monitor: AudioCaptureActivityMonitor = AudioCaptureActivityMonitor(),
        transcriber: any SpeechTranscribing = AppleSpeechTranscriber(),
        persistence: any TranscriptPersisting = MarkdownTranscriptStore(),
        audio: any AudioRetaining = RetainedAudioRecorder(),
        transcript: LiveTranscriptModel? = nil,
        elapsed: MeetingElapsedClock? = nil,
        processActivity: (any MeetingActivityAsserting)? = nil,
        now: @escaping () -> Date = { Date() },
        makeCapturer: (AudioSampleConsuming) -> AudioCapturing = {
            ScreenCaptureKitAudioCapturer(consumer: $0)
        }
    ) {
        self.monitor = monitor
        self.transcriber = transcriber
        self.persistence = persistence
        self.audio = audio
        self.transcript = transcript ?? LiveTranscriptModel()
        self.elapsed = elapsed ?? MeetingElapsedClock()
        self.processActivity = processActivity ?? ProcessMeetingActivity()
        self.now = now
        let mediaClock = CapturedMediaClock()
        self.mediaClock = mediaClock
        self.capturer = makeCapturer(
            BroadcastingAudioSampleConsumer([mediaClock, monitor, transcriber, audio])
        )
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
        let retentionFailures = audio.failures
        retentionFailureTask = Task { [weak self] in
            for await failure in retentionFailures {
                self?.handleRetentionFailure(failure)
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
            || audioRetentionState.isActive
    }

    /// What the meeting as a whole is doing.
    ///
    /// Derived from the four subsystem states rather than tracked beside them,
    /// so the menu bar and the main window read one answer and cannot drift
    /// apart. Views that need a subsystem's detail still read that subsystem.
    var status: MeetingRuntimeStatus {
        MeetingRuntimeStatus(
            capture: captureState,
            transcription: transcriptionState,
            persistence: persistenceState,
            audio: audioRetentionState
        )
    }

    /// Whether unfinished-session recovery may run and be acted on.
    ///
    /// A running meeting is legitimately recorded as in progress, so scanning
    /// for interrupted sessions while one runs would offer the meeting being
    /// written right now as a meeting to recover, and acting on it would write
    /// an interruption note into a transcript that is still open.
    var allowsRecovery: Bool { !isRunning }

    /// Starts or ends the process activity assertion and the elapsed clock as
    /// the meeting starts and stops holding resources.
    ///
    /// Driven from every subsystem state change rather than from the start and
    /// stop methods, because a meeting also ends through capture interruption,
    /// a retention failure and a persistence failure. Anything keyed to the
    /// happy path would leak the assertion down the other three.
    private func synchronizeActivity() {
        if isRunning {
            processActivity.begin()
        } else {
            processActivity.end()
            elapsed.stop()
        }
    }

    /// Whether the interface should offer to start a meeting.
    ///
    /// - Parameter request: What the screen would start, or `nil` when the
    ///   settings do not describe a startable meeting yet.
    /// - Returns: `true` when a start would be meaningful.
    func canStart(_ request: MeetingStartRequest?) -> Bool {
        guard let request else { return false }
        return captureState.canStart && transcriptionState.canStart && !persistenceState.isActive
            && !audioRetentionState.isActive && !request.sources.isEmpty && availability.canTranscribe
    }

    /// Whether the interface should offer to stop.
    var canStop: Bool { captureState.canStop || transcriptionState.canStop }

    /// Whether the interface should offer to pause.
    var canPause: Bool { captureState == .capturing && transcriptionState == .transcribing }

    /// Whether the interface should offer to resume.
    var canResume: Bool { captureState.canResume }

    /// Seconds of audio this meeting has captured.
    ///
    /// Media time: it does not advance while the meeting is paused, which is
    /// what keeps it equal to the length of the retained recording and to the
    /// end of the transcript's own offsets. The user-facing elapsed time in
    /// ``elapsed`` is deliberately the other one — wall-clock meeting length,
    /// which does keep running while paused.
    var capturedDuration: Double { mediaClock.seconds }

    /// Starts a meeting: the transcript file, then the audio file, then
    /// recognition, then capture.
    ///
    /// The order is the order of dependency. The transcript is created first,
    /// because a meeting that cannot be saved should not capture anything at
    /// all; the retained audio file next, because it is the other durable
    /// artifact the user asked for and a meeting that cannot keep the audio it
    /// was told to keep should not run either; recognition next, because
    /// capturing audio nothing will transcribe holds system resources for no
    /// result; capture last, so no buffer is delivered before everything that
    /// wants one is ready. Every step undoes the ones before it when it fails,
    /// so a failed start never leaves a file open, a folder leased or half a
    /// pipeline running — and never records a session as completed.
    ///
    /// The settings are copied into ``meeting`` before anything is created,
    /// and everything after that reads the copy. A meeting therefore keeps the
    /// title, sources, destination, retention mode and locale it was started
    /// with, whatever the setup screen is edited to afterwards.
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

        let startedAt = now()
        let session = request.makeSession(createdAt: startedAt)
        meeting = MeetingSnapshot(session: session, localeIdentifier: localeIdentifier)
        persistenceState = .preparing
        transcriptionState = .preparing
        captureState = .preparing
        audioRetentionState = request.audioRetention.retainsAudio ? .preparing : .idle
        recoveryAttempts = 0
        droppedEventBaseline = transcriber.eventTally.dropped
        mediaClock.reset()
        mediaOffsetBase = 0
        pendingMediaOffsetBase = nil
        pausedAt = nil
        pauseFailureMessage = nil
        monitor.reset()
        activity = .none
        transcript.begin(at: startedAt)
        elapsed.start(at: startedAt)

        let layout: SessionArtifactLayout
        do {
            layout = try await persistence.startSession(
                session,
                localeIdentifier: localeIdentifier,
                startedAt: startedAt
            )
            persistenceState = .saving(layout)
        } catch {
            persistenceState = .failed(message: message(for: error, sources: []), layout: nil)
            transcriptionState = .idle
            captureState = .idle
            audioRetentionState = .idle
            return
        }

        let captureConfiguration = AudioCaptureConfiguration(sources: request.sources)
        self.captureConfiguration = captureConfiguration
        do {
            let url = try audio.startSession(
                mode: request.audioRetention,
                layout: layout,
                format: captureConfiguration.requestedFormat
            )
            audioRetentionState = url.map { .retaining($0) } ?? .idle
        } catch {
            audioRetentionState = .failed(message: message(for: error, sources: []), url: nil)
            transcriptionState = .idle
            captureState = .idle
            // The transcript is closed without claiming a completion: nothing
            // was captured, so the meeting did not finish, it never began.
            await closeSession(outcome: .failed)
            return
        }

        do {
            try await transcriber.start(configuration: configuration)
            transcriptionState = .transcribing
        } catch {
            transcriptionState = .failed(message: message(for: error, sources: request.sources))
            captureState = .idle
            // Nothing was captured, so the meeting did not finish: it never
            // began. Recording it as completed would list an empty transcript
            // in History under the status a meeting that ran and closed gets.
            await closeSession(outcome: .failed)
            await refreshAvailability()
            return
        }

        do {
            try await capturer.start(configuration: captureConfiguration)
            captureState = .capturing
        } catch {
            await transcriber.stop()
            transcriptionState = .idle
            captureState = .failed(message: message(for: error, sources: request.sources))
            await closeSession(outcome: .failed)
        }
    }

    /// Suspends capture without ending the meeting.
    ///
    /// The order is the front of a stop and no more: capture stops so no
    /// further audio arrives, the recogniser finalises what it has already
    /// accepted, and every event it produced is handled and written. The
    /// transcript file, the retained recording, the session record and the
    /// folder lease all stay open, and the meeting is left in
    /// ``AudioCaptureState/paused`` rather than reported as finished.
    ///
    /// The media-time base for the next recognition run is taken only after
    /// the drain, so the last spans finalised out of pre-pause audio are still
    /// timed against the run they came from.
    ///
    /// The meeting is only described as paused once it has actually reached
    /// that boundary. A pause whose marker could not be written fails the
    /// transcript the way any other failed write does, and the meeting ends
    /// rather than sitting in a state the file does not record.
    func pause() async {
        guard canPause else { return }
        pauseFailureMessage = nil
        captureState = .stopping
        transcriptionState = .stopping
        await capturer.stop()
        await transcriber.stop()
        transcriptionState = .idle
        await drainPendingEvents()

        // Taken after the drain, so pre-pause spans keep the base they were
        // recognised under, and read from the media clock rather than the wall
        // clock, so a pause adds nothing to the transcript's own timeline.
        let captured = mediaClock.seconds
        mediaOffsetBase = captured
        pendingMediaOffsetBase = nil

        let date = now()
        guard persistenceState.isActive else {
            captureState = .paused
            pausedAt = date
            return
        }
        do {
            try await persistence.recordPause(at: date, capturedDuration: captured)
            pausedAt = date
            captureState = .paused
        } catch {
            captureState = .idle
            await failPersistence(error)
        }
    }

    /// Starts capture again for the meeting that is paused.
    ///
    /// The same session, the same transcript, the same recording and the same
    /// sources: the capture configuration is the one snapshotted at the start,
    /// so a setup screen edited in the meantime configures the next meeting and
    /// cannot reach this one.
    ///
    /// A resume that fails leaves the meeting paused with its artifacts
    /// untouched and says why, so the user can retry it when the source comes
    /// back rather than losing the meeting to a missing application.
    func resume() async {
        guard canResume, let captureConfiguration else { return }
        pauseFailureMessage = nil

        do {
            try await transcriber.start(configuration: configuration)
        } catch {
            pauseFailureMessage = message(for: error, sources: meeting?.sources ?? [])
            return
        }

        do {
            try await capturer.start(configuration: captureConfiguration)
        } catch {
            // Recognition is put back the way it was: the meeting is still
            // paused, and a recogniser left running with no audio would be a
            // second thing to go wrong on the next attempt.
            await transcriber.stop()
            await drainPendingEvents()
            pauseFailureMessage = message(for: error, sources: meeting?.sources ?? [])
            return
        }

        let date = now()
        if persistenceState.isActive {
            do {
                try await persistence.recordResume(at: date, capturedDuration: mediaOffsetBase)
            } catch {
                await capturer.stop()
                await transcriber.stop()
                captureState = .idle
                await failPersistence(error)
                return
            }
        }
        pausedAt = nil
        transcriptionState = .transcribing
        captureState = .capturing
    }

    /// Stops the meeting, in the order that loses nothing.
    ///
    /// Capture stops first so no audio arrives after the recogniser has closed
    /// its input and after the audio file stops accepting frames; the
    /// recogniser then finalises what it has already accepted, so the last
    /// sentence of a meeting is not lost; every event it produced is handled
    /// and written; then the retained audio file is closed, and last the
    /// transcript is flushed, closed and recorded. Only then is the folder
    /// lease released and the meeting reported as over.
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

    /// Closes the meeting's durable artifacts and releases the folder.
    ///
    /// The audio file is closed first and the transcript second, because the
    /// transcript's own writer records the session as finished and owns the
    /// folder lease the audio file was written under: nothing may claim a
    /// meeting completed while one of its artifacts is still open. A retained
    /// recording that could not be finalised therefore turns a completion into
    /// a failure, and the transcript is still flushed and closed either way.
    ///
    /// A session that has already failed is left alone: its resources were
    /// released when it failed, and overwriting the failure with a success
    /// would be the one thing this model must never do.
    ///
    /// - Parameter outcome: How the meeting is being closed, when the caller
    ///   already knows it did not finish normally.
    private func closeSession(outcome: SessionCompletionOutcome = .completed) async {
        let audioFailure = finishRetainedAudio()
        guard persistenceState.isActive else { return }
        let layout = persistenceState.layout
        do {
            try await persistence.finishSession(
                endedAt: now(),
                outcome: audioFailure == nil ? outcome : .failed,
                capturedDuration: mediaClock.seconds
            )
            persistenceState = layout.map { .saved($0) } ?? .idle
        } catch {
            persistenceState = .failed(message: message(for: error, sources: []), layout: layout)
        }
    }

    /// Closes the retained audio file, when the meeting is keeping one.
    ///
    /// - Returns: What to tell the user when the recording could not be
    ///   finalised, or when it had already failed earlier in the meeting;
    ///   `nil` when there is nothing wrong to say. A non-`nil` answer is what
    ///   stops the session being recorded as completed.
    private func finishRetainedAudio() -> String? {
        if let existing = audioRetentionState.failureMessage { return existing }
        guard case let .retaining(url) = audioRetentionState else { return nil }
        do {
            try audio.finishSession()
            audioRetentionState = .retained(url)
            return nil
        } catch {
            let text = message(for: error, sources: [])
            audioRetentionState = .failed(message: text, url: url)
            return text
        }
    }

    /// Records that the audio file stopped being written, and ends the meeting
    /// rather than carrying on with a recording that has a hole in it.
    ///
    /// The file is closed and left on disk with everything that reached it:
    /// audio from a meeting cannot be captured again, so a partial recording is
    /// the user's. The transcript is unaffected and is flushed and closed
    /// normally, but the session is not recorded as completed, because one of
    /// the artifacts the meeting promised did not finish.
    ///
    /// A meeting that is already stopping is left to finish its own teardown,
    /// which picks the failure up from ``audioRetentionState``.
    ///
    /// - Parameter error: What the retainer reported.
    private func handleRetentionFailure(_ error: AudioRetentionError) {
        guard case let .retaining(url) = audioRetentionState else { return }
        audioRetentionState = .failed(message: message(for: error, sources: []), url: url)
        audio.cancelSession()
        guard canStop else { return }

        captureState = .stopping
        transcriptionState = .stopping
        Task { @MainActor [weak self] in
            guard let self else { return }
            await capturer.stop()
            captureState = .idle
            await transcriber.stop()
            transcriptionState = .idle
            await drainPendingEvents()
            await closeSession()
        }
    }

    // MARK: - Events

    /// Applies a transcription event to the transcript, writes what is durable
    /// about it, and recovers from a recogniser that stopped by itself.
    ///
    /// - Parameter event: What the transcriber reported.
    private func handle(_ event: TranscriptionEvent) async {
        defer { completeHandling() }
        let event = rebased(event)
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

    /// Moves an event from the recognition run's own timeline onto the
    /// meeting's.
    ///
    /// A run that started at a resume counts from its own first frame, so
    /// everything it reports is short by the audio captured before the pause.
    /// Adding ``mediaOffsetBase`` puts it back on the one timeline the
    /// transcript, the retained recording and review playback share, so a
    /// resumed span's offset still names the same second of the audio file.
    /// A meeting that was never paused has a base of zero and is unaffected.
    ///
    /// - Parameter event: The event as the recogniser reported it.
    /// - Returns: The same event with session-global offsets.
    private func rebased(_ event: TranscriptionEvent) -> TranscriptionEvent {
        guard mediaOffsetBase > 0 else { return event }
        switch event {
        case let .partial(segment):
            return .partial(rebased(segment))
        case let .final(segment):
            return .final(rebased(segment))
        case let .interrupted(.audioDropped(seconds, startTime)):
            return .interrupted(.audioDropped(
                seconds: seconds,
                startTime: startTime.map { $0 + mediaOffsetBase }
            ))
        case .interrupted:
            return event
        }
    }

    /// The same span with its offsets measured from the meeting's first
    /// captured frame rather than the recognition run's.
    ///
    /// The text, the identity, the locale and the recogniser's confidence are
    /// untouched: this is arithmetic on the timeline and nothing else.
    ///
    /// - Parameter segment: The span as the recogniser reported it.
    /// - Returns: The span with session-global offsets.
    private func rebased(_ segment: TranscriptSegment) -> TranscriptSegment {
        TranscriptSegment(
            id: segment.id,
            text: segment.text,
            startTime: segment.startTime + mediaOffsetBase,
            endTime: segment.endTime + mediaOffsetBase,
            state: segment.state,
            localeIdentifier: segment.localeIdentifier,
            confidence: segment.confidence
        )
    }

    /// Records that an event has been fully handled and releases a stop that
    /// was waiting for it.
    private func completeHandling() {
        handledEventCount += 1
        if let pending = pendingMediaOffsetBase, handledEventCount >= pending.afterHandledEvents {
            mediaOffsetBase = pending.base
            pendingMediaOffsetBase = nil
        }
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
    /// The session is closed as ``SessionCompletionOutcome/failed``, so its
    /// record says the meeting ended because saving stopped working rather
    /// than leaving it looking like a meeting that vanished. ScribeKit was
    /// running and told the user at the time; the next launch should not
    /// present it as a mystery.
    ///
    /// - Parameter message: What to tell the user.
    private func failPersistence(message: String) async {
        guard persistenceState.isActive else { return }
        persistenceState = .failed(message: message, layout: persistenceState.layout)
        try? await persistence.finishSession(
            endedAt: now(),
            outcome: .failed,
            capturedDuration: mediaClock.seconds
        )
        stopSubsystemsAfterPersistenceFailure()
    }

    /// Stops capture and recognition after the transcript stopped being saved.
    ///
    /// Deliberately not ``stop()``: this runs while an event is being handled,
    /// and a stop that waited for that event to finish would wait for itself.
    /// The subsystems return to idle without a failure of their own, because
    /// nothing failed in them; ``persistenceState`` carries the reason.
    private func stopSubsystemsAfterPersistenceFailure() {
        guard canStop else {
            // A pause reached its drained boundary and then could not write
            // its marker: capture and recognition have already stopped, and
            // the recording is the only thing still open. Closing it here is
            // what keeps the meeting from staying "running" for the rest of
            // the process's life with a writer nothing will ever finish.
            _ = finishRetainedAudio()
            return
        }
        captureState = .stopping
        transcriptionState = .stopping
        Task { @MainActor [weak self] in
            guard let self else { return }
            await capturer.stop()
            captureState = .idle
            await transcriber.stop()
            transcriptionState = .idle
            // The recording is closed after capture, so nothing is still
            // arriving for it, and it is closed rather than discarded: the
            // transcript failing is no reason to throw away the audio.
            _ = finishRetainedAudio()
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
            endMeetingAfterRecognitionFailure()
            return
        }

        recoveryAttempts += 1
        transcriptionState = .recovering
        let startedRecovery = Date()
        await transcriber.stop()
        var restartFailed = false
        do {
            try await transcriber.start(configuration: configuration)
            transcriptionState = .transcribing
            // The new run counts from its own first frame again, so its
            // offsets are short by everything captured before it started.
            pendingMediaOffsetBase = (mediaClock.seconds, transcriber.eventTally.published)
        } catch {
            restartFailed = true
            transcriptionState = .failed(message: message(for: error, sources: []))
        }
        let lost = Date().timeIntervalSince(startedRecovery)
        transcript.apply(.interrupted(.audioDropped(seconds: lost)))
        await persist(TranscriptGap(duration: lost, reason: .recognizerRestarted))
        if restartFailed { endMeetingAfterRecognitionFailure() }
    }

    /// Ends a meeting whose recogniser cannot be brought back.
    ///
    /// Capture is stopped, the recogniser's run is closed, the events already
    /// published are handled, and the artifacts are closed and recorded as a
    /// failure. Leaving capture running would hold the capture stream, the
    /// retained recording and the process activity assertion for a meeting
    /// nothing is transcribing, and would close the transcript over an
    /// arbitrarily long stretch that no marker in it accounts for.
    ///
    /// ``transcriptionState`` is left as it is: it carries why the meeting
    /// ended, and nothing else records that.
    private func endMeetingAfterRecognitionFailure() {
        guard captureState.isActive || persistenceState.isActive || audioRetentionState.isActive else {
            return
        }
        captureState = .stopping
        Task { @MainActor [weak self] in
            guard let self else { return }
            await capturer.stop()
            captureState = .idle
            await transcriber.stop()
            await drainPendingEvents()
            await closeSession(outcome: .failed)
        }
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
