//
//  AppleSpeechTranscriber.swift
//  ScribeKit
//

import AVFAudio
import CoreMedia
import Foundation
import OSLog
import Speech
import Synchronization

/// Subsystem used for transcription logging, matching the application's
/// identifier so recognition events are filterable in Console alongside the
/// rest of the app.
private nonisolated let transcriptionSubsystem = Bundle.main.bundleIdentifier ?? "ScribeKit"

/// Transcribes captured audio with Apple's on-device speech recogniser.
///
/// The actor owns the whole framework-facing side of recognition: availability,
/// the `SpeechAnalyzer` and its `SpeechTranscriber` module, the format the
/// recogniser accepts, and the order of start and stop. Speech framework types
/// stop here — callers pass ``TranscriptionConfiguration`` and receive
/// ``TranscriptionEvent`` values.
///
/// Recognition is local. `SpeechTranscriber` runs against a speech model
/// installed on this Mac; ScribeKit refuses to start unless the model for the
/// chosen locale is present, and it never uses `SFSpeechRecognizer`, the older
/// API that can fall back to Apple's servers. There is no configuration of this
/// type that sends meeting audio anywhere.
///
/// Audio does not pass through the actor. ``consume(_:)`` is called on the
/// capture system's delivery queue, converts the buffer there and hands it to a
/// bounded queue the recogniser drains, so the delivery rate is never coupled
/// to actor scheduling or to the main actor.
actor AppleSpeechTranscriber: SpeechTranscribing {

    /// Converted buffers the recogniser may fall behind by.
    ///
    /// One buffer is 20 ms of captured audio, so this is roughly three seconds
    /// of backlog and a few tens of kilobytes. Beyond it the oldest audio is
    /// dropped and the loss is reported: the alternative, an unbounded queue,
    /// turns a recogniser that stalls once into memory that grows for the rest
    /// of the meeting.
    static let defaultBacklogCapacity = 150

    /// How long a stop waits for the recogniser's results to end by themselves.
    ///
    /// Finalising delivers every remaining result and then ends the sequence,
    /// which takes milliseconds. A run that accepted no audio at all never ends
    /// its sequence, so the wait is bounded and the task is cancelled rather
    /// than left to hold a stop open.
    private static let resultsDrainTimeout = Duration.seconds(2)

    nonisolated let events: AsyncStream<TranscriptionEvent>

    private nonisolated let eventContinuation: AsyncStream<TranscriptionEvent>.Continuation
    private nonisolated let logger = Logger(subsystem: transcriptionSubsystem, category: "Transcription")
    private nonisolated let backlogCapacity: Int

    /// The input the delivery queue writes to, present only while a run is in
    /// progress. Held outside the actor because audio must not wait for it.
    private nonisolated let input = Mutex<TranscriptionAudioInput?>(nil)

    private var run: Run?

    /// One recognition run.
    private struct Run {
        let analyzer: SpeechAnalyzer
        let module: SpeechTranscriber
        let input: TranscriptionAudioInput
        let results: Task<Void, Never>
        let localeIdentifier: String
    }

    /// Creates a transcriber.
    ///
    /// - Parameter backlogCapacity: How many converted buffers the recogniser
    ///   may fall behind by before the oldest audio is dropped.
    init(backlogCapacity: Int = defaultBacklogCapacity) {
        self.backlogCapacity = backlogCapacity
        var continuation: AsyncStream<TranscriptionEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation = $0 }
        eventContinuation = continuation
    }

    deinit {
        eventContinuation.finish()
    }

    // MARK: - Audio

    nonisolated func consume(_ buffer: CapturedPCMBuffer) {
        guard let input = input.withLock({ $0 }) else { return }
        if let dropped = input.append(buffer) {
            eventContinuation.yield(.interrupted(.audioDropped(seconds: dropped)))
        }
    }

    // MARK: - Availability

    func availableLocales() async -> [TranscriptionLocale] {
        guard SpeechTranscriber.isAvailable else { return [] }
        let installed = Set(await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
        return await SpeechTranscriber.supportedLocales
            .map { locale in
                let identifier = locale.identifier(.bcp47)
                return TranscriptionLocale(id: identifier, isInstalled: installed.contains(identifier))
            }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    func availability(for configuration: TranscriptionConfiguration) async -> SpeechRecognitionAvailability {
        guard SpeechTranscriber.isAvailable else { return .unsupportedSystem }
        let requested = Locale(identifier: configuration.localeIdentifier)
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            return .unsupportedLocale(localeIdentifier: configuration.localeIdentifier)
        }
        let identifier = supported.identifier(.bcp47)
        let installed = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
        guard installed.contains(identifier) else {
            return .modelNotInstalled(localeIdentifier: identifier)
        }
        return .available(localeIdentifier: identifier)
    }

    // MARK: - Lifecycle

    func start(configuration: TranscriptionConfiguration) async throws {
        guard run == nil else { throw TranscriptionError.alreadyTranscribing }

        let availability = await availability(for: configuration)
        guard case let .available(localeIdentifier) = availability else {
            logger.error("Recognition refused: \(String(describing: availability), privacy: .public)")
            throw TranscriptionError.unavailable(availability)
        }

        let module = SpeechTranscriber(
            locale: Locale(identifier: localeIdentifier),
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw TranscriptionError.incompatibleAudioFormat
        }

        let analyzer = SpeechAnalyzer(
            modules: [module],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse)
        )
        if !configuration.contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = configuration.contextualStrings
            do {
                try await analyzer.setContext(context)
            } catch {
                throw TranscriptionError.systemFailure(error.localizedDescription)
            }
        }

        let audioInput = TranscriptionAudioInput(outputFormat: format, capacity: backlogCapacity)
        let results = resultsTask(for: module, localeIdentifier: localeIdentifier)
        do {
            try await analyzer.start(inputSequence: audioInput.queue)
        } catch {
            results.cancel()
            audioInput.close()
            logger.error("Recognition failed to start: \(error.localizedDescription, privacy: .public)")
            throw TranscriptionError.systemFailure(error.localizedDescription)
        }

        input.withLock { $0 = audioInput }
        run = Run(
            analyzer: analyzer,
            module: module,
            input: audioInput,
            results: results,
            localeIdentifier: localeIdentifier
        )
        logger.info("""
            Recognition started, locale \(localeIdentifier, privacy: .public), \
            input \(Int(format.sampleRate), privacy: .public) Hz
            """)
    }

    func stop() async {
        guard let run else { return }
        self.run = nil
        input.withLock { $0 = nil }

        if let dropped = run.input.takeUnreportedDrop() {
            eventContinuation.yield(.interrupted(.audioDropped(seconds: dropped)))
        }
        run.input.close()

        do {
            try await run.analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            logger.info("Recognition finish reported: \(error.localizedDescription, privacy: .public)")
            await run.analyzer.cancelAndFinishNow()
        }
        await drain(run.results)
        logger.info("""
            Recognition stopped, dropped \(run.input.droppedSeconds, format: .fixed(precision: 2), privacy: .public) s, \
            converters \(run.input.converterCreationCount, privacy: .public)
            """)
    }

    /// Waits for a results task to end, cancelling it if it takes too long.
    ///
    /// - Parameter results: The task watching a run's results.
    private func drain(_ results: Task<Void, Never>) async {
        let watchdog = Task { [logger] in
            try? await Task.sleep(for: Self.resultsDrainTimeout)
            logger.info("Recognition results did not end on their own; cancelling")
            results.cancel()
        }
        await results.value
        watchdog.cancel()
    }

    /// Watches one run's results and turns them into ScribeKit events.
    ///
    /// The recogniser reports a volatile hypothesis for the span being spoken
    /// and, when it settles, a finalised span covering it. Both are forwarded
    /// with the distinction intact; nothing is merged, deduplicated or edited
    /// here.
    ///
    /// - Parameters:
    ///   - module: The recogniser whose results to watch.
    ///   - localeIdentifier: The locale recognition is running in.
    /// - Returns: The task, which ends when the results sequence does.
    private nonisolated func resultsTask(
        for module: SpeechTranscriber,
        localeIdentifier: String
    ) -> Task<Void, Never> {
        let continuation = eventContinuation
        let logger = logger
        return Task.detached(priority: .userInitiated) {
            do {
                for try await result in module.results {
                    let segment = TranscriptSegment(
                        text: String(result.text.characters),
                        startTime: Self.seconds(result.range.start),
                        endTime: Self.seconds(result.range.end),
                        state: result.isFinal ? .final : .partial,
                        localeIdentifier: localeIdentifier
                    )
                    continuation.yield(result.isFinal ? .final(segment) : .partial(segment))
                }
            } catch {
                // A cancelled task is a stop that has already been decided, not
                // a recogniser that failed, so it is not reported as one.
                guard !Task.isCancelled else { return }
                logger.error("Recognition interrupted: \(error.localizedDescription, privacy: .public)")
                continuation.yield(.interrupted(.recognitionFailed(message: error.localizedDescription)))
            }
        }
    }

    /// Reads a recogniser timestamp as seconds from the start of the run.
    ///
    /// - Parameter time: A time from a recognition result.
    /// - Returns: The time in seconds, or zero when it is not numeric.
    private static func seconds(_ time: CMTime) -> Double {
        time.isNumeric ? time.seconds : 0
    }
}
