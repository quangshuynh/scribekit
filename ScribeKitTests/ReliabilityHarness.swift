//
//  ReliabilityHarness.swift
//  ScribeKitTests
//

import Foundation
import Synchronization
@testable import ScribeKit

/// One meeting driven entirely by doubles, with both of its clocks under the
/// test's control, so a multi-hour run, a fault at any persistence boundary and
/// a hundred lifecycle cycles all cost milliseconds and no disk.
///
/// The harness exists to make long-duration and failure behaviour reproducible
/// rather than observed by hand. It drives the same seams the application does:
/// captured buffers arrive through the capturer's own delivery path, so the
/// media clock, the activity monitor, the recogniser's input and the retainer
/// all see them in order; recognition events are published the way a run
/// publishes them; and every failure is armed on the double that would really
/// have failed.
///
/// Two things it deliberately does not simulate: the audio itself — a delivered
/// buffer carries the frame count that drives the clocks and a token sample,
/// not two hours of synthesised PCM — and real time. Evidence produced here is
/// evidence about ordering, arithmetic and state, never about CPU, memory
/// behaviour under a real recogniser, or anything the operating system decides.
@MainActor
final class ReliabilityHarness {

    /// A wall clock the test moves by hand, so a two-hour meeting and a
    /// six-minute pause cost nothing.
    final class Clock: @unchecked Sendable {
        private let value: Mutex<Date>

        init(start: Date = Date(timeIntervalSinceReferenceDate: 0)) {
            value = Mutex(start)
        }

        var now: Date { value.withLock { $0 } }

        func advance(_ seconds: TimeInterval) {
            value.withLock { $0 += seconds }
        }
    }

    let runtime: MeetingRuntime
    let capturer: FakeCapturer
    let transcriber: FakeSpeechTranscriber
    let persistence: FakeTranscriptPersistence
    let audio: FakeAudioRetention
    let activity: FakeMeetingActivity
    let clock: Clock

    /// The format the synthetic buffers claim to be in.
    let format = CapturedAudioFormat(
        sampleRate: 48_000,
        channelCount: 1,
        bitsPerChannel: 32,
        isFloat: true,
        isInterleaved: false
    )

    /// A source that exists for the whole of a harness meeting.
    nonisolated static let meet = CaptureSource.application(
        bundleIdentifier: "com.example.Meet",
        displayName: "Meet"
    )

    /// Where a harness meeting claims to be written. Nothing reaches a disk.
    nonisolated static let destination = URL(filePath: "/tmp/scribekit-reliability", directoryHint: .isDirectory)

    /// Seconds of audio delivered since the meeting started: what the media
    /// clock should read, computed independently of it.
    private(set) var capturedSeconds: Double = 0

    /// The media time at which the current recognition run began.
    ///
    /// A recognition run counts its own offsets from its own first frame, so
    /// this is what a run-relative offset has to be added to for the meeting's
    /// timeline. The harness tracks it so a test can state what an offset
    /// *should* be rather than reading it back from the code under test.
    private(set) var runOrigin: Double = 0

    /// Builds a meeting over doubles.
    ///
    /// - Parameter availability: What the recogniser reports about itself.
    init(availability: SpeechRecognitionAvailability = .available(localeIdentifier: "en-US")) {
        let clock = Clock()
        let transcriber = FakeSpeechTranscriber()
        transcriber.availabilityResult = availability
        let persistence = FakeTranscriptPersistence()
        let audio = FakeAudioRetention()
        let activity = FakeMeetingActivity()
        var built: FakeCapturer!
        runtime = MeetingRuntime(
            monitor: AudioCaptureActivityMonitor(minimumPublishInterval: .zero),
            transcriber: transcriber,
            persistence: persistence,
            audio: audio,
            elapsed: MeetingElapsedClock(now: { clock.now }, interval: nil),
            processActivity: activity,
            now: { clock.now },
            makeCapturer: { consumer in
                built = FakeCapturer(consumer: consumer)
                return built
            }
        )
        self.clock = clock
        self.transcriber = transcriber
        self.persistence = persistence
        self.audio = audio
        self.activity = activity
        capturer = built
    }

    // MARK: - Lifecycle

    /// Prepares the screen and starts a meeting.
    ///
    /// - Parameters:
    ///   - retention: What the meeting keeps of its audio.
    ///   - title: The meeting's title.
    ///   - sources: What it captures.
    func start(
        retention: AudioRetentionMode = .none,
        title: String = "Reliability",
        sources: [CaptureSource] = [ReliabilityHarness.meet]
    ) async {
        await runtime.prepare()
        await runtime.start(MeetingStartRequest(
            title: title,
            sources: sources,
            destination: Self.destination,
            audioRetention: retention
        ))
        capturedSeconds = 0
        runOrigin = 0
    }

    /// Suspends capture and advances the wall clock the way a real pause does.
    ///
    /// - Parameter seconds: How long the meeting stays paused on the wall
    ///   clock. Media time does not move: nothing is delivered while paused.
    func pause(for seconds: TimeInterval = 60) async {
        await runtime.pause()
        clock.advance(seconds)
    }

    /// Starts capture again, and records where the new recognition run begins
    /// on the meeting's own timeline.
    func resume() async {
        await runtime.resume()
        if runtime.captureState == .capturing { runOrigin = capturedSeconds }
    }

    /// Stops the meeting.
    func stop() async {
        await runtime.stop()
    }

    // MARK: - Audio

    /// Delivers audio the way the capture queue would.
    ///
    /// The wall clock advances with it, because captured seconds are also
    /// seconds that passed.
    ///
    /// - Parameters:
    ///   - seconds: How much audio each buffer carries.
    ///   - count: How many buffers to deliver.
    func deliver(seconds: Double = 1, count: Int = 1) {
        for _ in 0..<count {
            capturer.deliver(buffer(seconds: seconds))
            capturedSeconds += seconds
            clock.advance(seconds)
        }
    }

    /// A synthetic buffer of the shape ScreenCaptureKit delivers.
    ///
    /// The frames are counted, not synthesised: the clocks, the retainer and
    /// the activity summary read the count, and a two-hour run of real samples
    /// would cost gigabytes to prove arithmetic that does not look at them.
    ///
    /// - Parameter seconds: How much audio the buffer represents.
    /// - Returns: The buffer.
    func buffer(seconds: Double) -> CapturedPCMBuffer {
        CapturedPCMBuffer(
            format: format,
            frameCount: Int(seconds * format.sampleRate),
            presentationTime: capturedSeconds,
            peakAmplitude: 0.25,
            samples: [0.25]
        )
    }

    // MARK: - Recognition

    /// Publishes a finalised span timed at the meeting's current media
    /// position, in the run-relative form a recogniser reports.
    ///
    /// - Parameter text: What the recogniser heard.
    /// - Returns: The offset the span should be written at, on the meeting's
    ///   own timeline.
    @discardableResult
    func emitFinal(_ text: String) -> Double {
        let absolute = capturedSeconds
        transcriber.emit(.final(TranscriptSegment(
            text: text,
            startTime: absolute - runOrigin,
            endTime: absolute - runOrigin + 1,
            state: .final,
            localeIdentifier: "en-US"
        )))
        return absolute
    }

    /// Reports the recogniser stopping by itself and waits for whatever the
    /// runtime decides to do about it.
    ///
    /// - Returns: `true` when the recogniser was restarted, `false` when the
    ///   runtime gave up on it.
    @discardableResult
    func failRecognition(message: String = "resources") async -> Bool {
        let startsBefore = transcriber.startCount
        transcriber.emit(.interrupted(.recognitionFailed(message: message)))
        let restarted = await wait { self.transcriber.startCount > startsBefore }
        if restarted { runOrigin = capturedSeconds }
        _ = await wait { self.runtime.transcriptionState != .recovering }
        return restarted
    }

    // MARK: - Observation

    /// The offsets of every finalised span the writer accepted, in order.
    var writtenOffsets: [Double] {
        persistence.entries.compactMap {
            if case let .segment(segment) = $0 { segment.startTime } else { nil }
        }
    }

    /// The captured durations the pause and resume markers state, in order.
    var markerDurations: [Double] {
        persistence.entries.compactMap { entry in
            switch entry {
            case let .paused(captured): captured
            case let .resumed(captured): captured
            default: nil
            }
        }
    }

    /// Waits for a main-actor condition a background handler will satisfy.
    ///
    /// - Parameter condition: What to wait for.
    /// - Returns: Whether it became true before the attempts ran out.
    @discardableResult
    func wait(for condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return condition()
    }

    /// Waits until the writer has accepted a given number of finalised spans.
    ///
    /// - Parameter count: How many spans should have reached the writer.
    /// - Returns: Whether they did.
    @discardableResult
    func waitForSegments(_ count: Int) async -> Bool {
        await wait { self.persistence.segments.count >= count }
    }
}
