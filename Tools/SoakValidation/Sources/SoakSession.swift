//
//  SoakSession.swift
//  SoakValidation
//

import Foundation
@testable import ScribeKit

/// A real-time run of the production pipeline, observed from inside the
/// process at a low, fixed rate.
///
/// The session owns a real ``MeetingRuntime`` built from the real
/// ``ScreenCaptureKitAudioCapturer``, the real ``AppleSpeechTranscriber``, the
/// real ``MarkdownTranscriptStore`` and the real ``RetainedAudioRecorder``. It
/// is started, paused, resumed and stopped through the same calls the
/// application makes, so what is measured is the shipping pipeline rather than
/// a model of it.
///
/// Two substitutions, both at a boundary and both stated in the report:
///
/// 1. **Sample provenance.** ``SyntheticSpeechInjector`` sits between the real
///    stream and the real pipeline. Cadence, format, frame counts and
///    presentation times are the framework's; the sample values are
///    synthesised speech.
/// 2. **Folder access.** The destination is a disposable directory reached
///    through a granting ``SecurityScopedResourceAccessing``, because a
///    security-scoped bookmark can only come from a system panel.
@MainActor
final class SoakSession {

    /// Grants access to a directory that carries no security scope.
    ///
    /// Confined to the harness: it stands in for a bookmark the developer
    /// cannot produce from a test process, and grants nothing the process did
    /// not already have.
    nonisolated struct GrantingAccess: SecurityScopedResourceAccessing {
        func startAccess(to url: URL) -> Bool { true }
        func stopAccess(to url: URL) {}
    }

    /// What went wrong before a run could start.
    enum Failure: Error, CustomStringConvertible {
        case noCapturableApplication
        case recognitionUnavailable(String)
        case startFailed(String)

        var description: String {
            switch self {
            case .noCapturableApplication:
                "no capturable application was discovered; grant Screen Recording and leave an application running"
            case let .recognitionUnavailable(reason):
                "on-device recognition is unavailable: \(reason)"
            case let .startFailed(reason):
                "the meeting did not start: \(reason)"
            }
        }
    }

    /// How the run was configured.
    let configuration: SoakConfiguration

    /// The meeting owner under measurement.
    let runtime: MeetingRuntime

    /// The recogniser the runtime is using, held so its event tally can be
    /// read: the tally is how often the interface is asked to update.
    let transcriber: any SpeechTranscribing

    /// The disposable destination this run writes into.
    let destination: URL

    /// The source the run captured.
    private(set) var source: CaptureSource?

    /// Every observation taken, in order.
    private(set) var observations: [SoakObservation] = []

    private var previous: SoakProcessSample?
    private var previousAt: Date?
    private var startedAt = Date()

    /// Builds a session and the pipeline under it.
    ///
    /// - Parameter configuration: What the run should do.
    /// - Throws: ``Failure`` when nothing can be captured or recognised.
    static func make(configuration: SoakConfiguration) async throws -> SoakSession {
        let destination = configuration.output.appending(
            path: "session-\(Int(Date().timeIntervalSince1970))",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let sources = try await ScreenCaptureKitSourceProvider().availableSources()
        let chosen: CaptureSource?
        if let wanted = configuration.sourceBundleIdentifier {
            chosen = sources.first { $0.id == wanted }
        } else {
            chosen = sources.first
        }
        guard let chosen else { throw Failure.noCapturableApplication }

        let speech = await SyntheticSpeech.render(sampleRate: 48_000)
        let transcriber = AppleSpeechTranscriber()
        let runtime = MeetingRuntime(
            transcriber: transcriber,
            persistence: MarkdownTranscriptStore(access: GrantingAccess()),
            makeCapturer: { downstream in
                ScreenCaptureKitAudioCapturer(
                    consumer: SyntheticSpeechInjector(downstream: downstream, speech: speech)
                )
            }
        )
        await runtime.prepare()
        guard runtime.availability.canTranscribe else {
            throw Failure.recognitionUnavailable(String(describing: runtime.availability))
        }

        return SoakSession(
            configuration: configuration,
            runtime: runtime,
            transcriber: transcriber,
            destination: destination,
            source: chosen
        )
    }

    private init(
        configuration: SoakConfiguration,
        runtime: MeetingRuntime,
        transcriber: any SpeechTranscribing,
        destination: URL,
        source: CaptureSource
    ) {
        self.configuration = configuration
        self.runtime = runtime
        self.transcriber = transcriber
        self.destination = destination
        self.source = source
    }

    /// Starts the meeting and takes the first observation.
    ///
    /// - Parameter title: The meeting's title.
    /// - Throws: ``Failure/startFailed(_:)`` when the pipeline refused.
    func start(title: String) async throws {
        guard let source else { throw Failure.noCapturableApplication }
        startedAt = Date()
        await runtime.start(
            MeetingStartRequest(
                title: title,
                sources: [source],
                destination: destination,
                audioRetention: configuration.retention
            )
        )
        guard runtime.isRunning else {
            throw Failure.startFailed(String(describing: runtime.status))
        }
        observe(label: "start")
    }

    /// Takes one observation and appends it.
    ///
    /// - Parameter label: What the run was doing.
    /// - Returns: The observation.
    @discardableResult
    func observe(label: String) -> SoakObservation {
        let now = Date()
        let sample = SoakProcessSampler.sample()
        let window = previousAt.map { now.timeIntervalSince($0) } ?? 0
        let layout = runtime.persistenceState.layout
        let observation = SoakObservation(
            label: label,
            elapsedSeconds: now.timeIntervalSince(startedAt),
            capturedSeconds: runtime.capturedDuration,
            footprintBytes: sample.footprintBytes,
            cpuSeconds: sample.cpuSeconds,
            windowCPUFraction: sample.cpuFraction(since: previous, over: window),
            threadCount: sample.threadCount,
            thermalState: sample.thermalState,
            transcriptBytes: layout.flatMap { Self.size(of: $0.transcriptURL) },
            recordingBytes: layout.flatMap { $0.audioURL(for: configuration.retention) }
                .flatMap(Self.size(of:)),
            status: String(describing: runtime.status),
            bufferCount: runtime.activity.sampleCount,
            unreadableBufferCount: runtime.activity.unreadableSampleCount,
            recognitionEventCount: transcriber.eventTally.published
        )
        previous = sample
        previousAt = now
        observations.append(observation)
        print(observation.line)
        return observation
    }

    /// The longest the run waits between checking that the meeting is still
    /// alive, so a pipeline that stopped is noticed in seconds rather than at
    /// the next observation.
    private static let livenessInterval: TimeInterval = 15

    /// Why the run stopped early, when it did.
    private(set) var endedEarly: String?

    /// Runs for a while, observing on a schedule.
    ///
    /// Returns early when the meeting is no longer running. A soak that has
    /// lost its capture stream is measuring an idle process, and an hour of
    /// that is an hour of nothing: the reason is recorded in ``endedEarly``
    /// and the caller decides what to say about it.
    ///
    /// - Parameters:
    ///   - schedule: When to observe, relative to the call.
    ///   - label: What to call the observations.
    func observe(on schedule: SoakSampleSchedule, label: String) async {
        var reached: TimeInterval = 0
        while let wait = schedule.secondsAfter(reached) {
            var waited: TimeInterval = 0
            while waited < wait {
                let slice = min(Self.livenessInterval, wait - waited)
                try? await Task.sleep(for: .seconds(slice))
                waited += slice
                guard runtime.isRunning else {
                    endedEarly = String(describing: runtime.status)
                    observe(label: "ended early")
                    return
                }
            }
            reached += wait
            observe(label: "\(label) \(Int(reached / 60))m")
        }
    }

    /// Stops the meeting the way the Stop button does, and observes the result.
    func stop() async {
        await runtime.stop()
        try? await Task.sleep(for: .seconds(5))
        observe(label: "stopped")
    }

    /// Reads the session directory the run produced and judges it.
    ///
    /// - Returns: The report, or `nil` when no session directory was recorded.
    func verify(capturedSeconds: Double) -> SoakArtifactReport? {
        guard let directory = sessionDirectory else { return nil }
        return SoakArtifactReport.inspect(
            directory: directory,
            retention: configuration.retention,
            capturedSeconds: capturedSeconds
        )
    }

    /// The one session directory the run should have created.
    var sessionDirectory: URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents.first(where: \.hasDirectoryPath)
    }

    /// Writes the observations beside the session directory, never into it.
    ///
    /// Measurements are not meeting artifacts, so they go in the disposable
    /// output folder's own file rather than anywhere `transcript.md`,
    /// `session.json`, `review.json` or `derived.json` live.
    ///
    /// - Parameter name: The report's file name.
    /// - Returns: Where it was written.
    @discardableResult
    func writeReport(named name: String) throws -> URL {
        let url = configuration.output.appending(path: name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(observations).write(to: url, options: .atomic)
        return url
    }

    private static func size(of url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size])
            .flatMap { $0 as? Int }
    }
}
