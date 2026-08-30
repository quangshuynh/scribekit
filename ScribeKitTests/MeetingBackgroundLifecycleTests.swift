//
//  MeetingBackgroundLifecycleTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// What was already true at the moment the transcript's session record was
/// written, captured off the main actor because that is where the writer
/// closes.
private final class ClosingOrder: @unchecked Sendable {
    private let lock = NSLock()
    private var state = (recording: false, capture: false, recogniser: false)

    /// Whether the retained recording had already been closed.
    var recordingClosed: Bool { lock.withLock { state.recording } }

    /// Whether capture had already been stopped.
    var captureStopped: Bool { lock.withLock { state.capture } }

    /// Whether the recogniser had already been stopped.
    var recogniserStopped: Bool { lock.withLock { state.recogniser } }

    /// Records what was true as the session record was written.
    func record(recordingClosed: Bool, captureStopped: Bool, recogniserStopped: Bool) {
        lock.withLock { state = (recordingClosed, captureStopped, recogniserStopped) }
    }
}

/// Something view-scoped that observes the meeting, used to prove that letting
/// go of it changes nothing about the meeting.
@MainActor
private final class PresentationScope {
    let runtime: MeetingRuntime

    init(runtime: MeetingRuntime) {
        self.runtime = runtime
    }
}

@MainActor
@Suite("Background meeting lifecycle")
struct MeetingBackgroundLifecycleTests {

    private let meet = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")
    private let browser = CaptureSource.application(bundleIdentifier: "com.example.Browser", displayName: "Browser")
    private let destination = URL(filePath: "/tmp/scribekit-tests", directoryHint: .isDirectory)

    private let format = CapturedAudioFormat(
        sampleRate: 48_000,
        channelCount: 1,
        bitsPerChannel: 32,
        isFloat: true,
        isInterleaved: false
    )

    /// Everything one runtime is built over, so a test can inspect any of it.
    private struct Meeting {
        let runtime: MeetingRuntime
        let capturer: FakeCapturer
        let transcriber: FakeSpeechTranscriber
        let persistence: FakeTranscriptPersistence
        let audio: FakeAudioRetention
        let activity: FakeMeetingActivity
        let clock: MeetingElapsedClock
    }

    /// Builds an application-scoped runtime over doubles, prepared as the
    /// screen prepares it.
    ///
    /// - Parameter startedAt: The time the clock reads, so elapsed time is
    ///   deterministic.
    /// - Returns: The runtime and everything behind it.
    private func makeMeeting(startedAt: Date = Date(timeIntervalSince1970: 1_000)) async -> Meeting {
        let transcriber = FakeSpeechTranscriber()
        let persistence = FakeTranscriptPersistence()
        let audio = FakeAudioRetention()
        let activity = FakeMeetingActivity()
        let clock = MeetingElapsedClock(now: { startedAt }, interval: nil)
        var capturer: FakeCapturer!
        let runtime = MeetingRuntime(
            monitor: AudioCaptureActivityMonitor(minimumPublishInterval: .zero),
            transcriber: transcriber,
            persistence: persistence,
            audio: audio,
            elapsed: clock,
            processActivity: activity,
            makeCapturer: { consumer in
                capturer = FakeCapturer(consumer: consumer)
                return capturer
            }
        )
        await runtime.prepare()
        return Meeting(
            runtime: runtime,
            capturer: capturer,
            transcriber: transcriber,
            persistence: persistence,
            audio: audio,
            activity: activity,
            clock: clock
        )
    }

    /// A meeting to start.
    private func request(
        _ sources: [CaptureSource],
        title: String = "Weekly Sync",
        retention: AudioRetentionMode = .none
    ) -> MeetingStartRequest {
        MeetingStartRequest(title: title, sources: sources, destination: destination, audioRetention: retention)
    }

    /// A synthetic captured buffer.
    private func buffer(frames: Int = 960) -> CapturedPCMBuffer {
        CapturedPCMBuffer(
            format: format,
            frameCount: frames,
            presentationTime: 12,
            peakAmplitude: 0.25,
            samples: [Float](repeating: 0.25, count: frames)
        )
    }

    /// A finalised span, as a recogniser would report one.
    private func segment(_ text: String, start: Double = 0) -> TranscriptSegment {
        TranscriptSegment(
            text: text,
            startTime: start,
            endTime: start + 1,
            state: .final,
            localeIdentifier: "en-US"
        )
    }

    /// Waits for a main-actor condition a background delivery will satisfy.
    private func wait(for condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// What the menu bar would show right now.
    private func menuBar(_ runtime: MeetingRuntime) -> MeetingMenuBarPresentation {
        MeetingMenuBarPresentation(
            status: runtime.status,
            meeting: runtime.meeting,
            transcript: runtime.persistenceState.layout?.transcriptURL,
            audio: runtime.audioRetentionState.url,
            canStop: runtime.canStop
        )
    }

    // MARK: - Ownership

    @Test("Releasing everything the window held leaves the meeting running")
    func meetingOutlivesItsPresentation() async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([meet]))
        #expect(meeting.runtime.status == .transcribing)

        weak var released: PresentationScope?
        do {
            let scope = PresentationScope(runtime: meeting.runtime)
            released = scope
            #expect(scope.runtime.status == .transcribing)
        }

        #expect(released == nil, "the window's state really did go away")
        #expect(meeting.runtime.status == .transcribing)
        #expect(meeting.capturer.stopCount == 0)
        #expect(meeting.transcriber.stopCount == 0)
        #expect(meeting.persistence.isOpen)
        #expect(meeting.activity.isAsserted)
    }

    @Test("The application object owns a meeting runtime and starts nothing")
    func applicationOwnsTheRuntime() {
        let delegate = ScribeKitAppDelegate()
        #expect(delegate.runtime.status == .idle)
        #expect(delegate.runtime.meeting == nil)
        #expect(!delegate.runtime.isRunning)
        #expect(delegate.runtime === delegate.runtime, "one runtime, not one per read")
    }

    @Test("A second start is refused rather than building a second pipeline")
    func onlyOneActiveMeeting() async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([meet], title: "First"))
        #expect(meeting.runtime.status == .transcribing)

        #expect(!meeting.runtime.canStart(request([browser], title: "Second")))
        await meeting.runtime.start(request([browser], title: "Second", retention: .compressed))

        #expect(meeting.capturer.startCount == 1)
        #expect(meeting.transcriber.startCount == 1)
        #expect(meeting.persistence.entries.filter { if case .started = $0 { true } else { false } }.count == 1)
        #expect(meeting.audio.entries.count == 1, "the refused meeting did not open a second recording")
        #expect(meeting.audio.entries.first == .started(mode: .none, url: nil))
        #expect(meeting.runtime.meeting?.session.title == "First")
    }

    @Test("A window built again observes the meeting that is already running")
    func rebuiltWindowSeesTheRunningMeeting() async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([meet, browser], retention: .compressed))
        meeting.transcriber.emit(.final(segment("hello")))
        #expect(await wait { !meeting.runtime.transcript.finalizedSegments.isEmpty })

        // What reopening the window does: the screen prepares itself again.
        await meeting.runtime.prepare()

        #expect(meeting.runtime.status == .transcribing)
        #expect(meeting.runtime.meeting?.title == "Weekly Sync")
        #expect(meeting.runtime.transcript.finalizedSegments.count == 1)
        #expect(menuBar(meeting.runtime).statusLine == "Transcribing")
        #expect(meeting.capturer.startCount == 1)
        #expect(meeting.transcriber.startCount == 1)
    }

    @Test("Preparing the screen repeatedly duplicates no listener, segment or timer")
    func repeatedPresentationCreation() async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([meet], retention: .compressed))
        meeting.capturer.deliver(buffer())

        for _ in 0..<3 { await meeting.runtime.prepare() }

        meeting.transcriber.emit(.final(segment("only once")))
        #expect(await wait { meeting.persistence.segments.count == 1 })

        #expect(meeting.runtime.transcript.finalizedSegments.count == 1)
        #expect(meeting.persistence.segments.count == 1)
        #expect(meeting.audio.appendCount == 1)
        #expect(meeting.activity.beginCount == 1)
        #expect(!meeting.clock.isTicking, "the test clock never ticks; a real one would have exactly one")
    }

    // MARK: - Stopping from the menu bar

    @Test("Stopping from the menu bar finalises in the same order the window does")
    func menuBarStopFinalisesEverything() async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([meet], retention: .compressed))
        meeting.capturer.deliver(buffer())
        meeting.transcriber.emit(.final(segment("last words")))
        #expect(await wait { meeting.persistence.segments.count == 1 })
        #expect(menuBar(meeting.runtime).canStop)

        let audio = meeting.audio
        let capturer = meeting.capturer
        let transcriber = meeting.transcriber
        let order = ClosingOrder()
        meeting.persistence.observeFinish {
            order.record(
                recordingClosed: !audio.isOpen,
                captureStopped: capturer.stopCount == 1,
                recogniserStopped: transcriber.stopCount == 1
            )
        }

        // Exactly what the menu bar's Stop item invokes.
        await meeting.runtime.stop()

        #expect(order.captureStopped)
        #expect(order.recogniserStopped)
        #expect(order.recordingClosed)
        #expect(meeting.persistence.outcomes == [.completed])
        #expect(!meeting.persistence.isOpen)
        #expect(meeting.audio.entries.last == .finished)
        #expect(meeting.runtime.status == .completed)
        #expect(!menuBar(meeting.runtime).canStop)
        #expect(!meeting.activity.isAsserted)
    }

    @Test("A finished meeting releases the process activity assertion it took")
    func activityIsScopedToTheMeeting() async {
        let meeting = await makeMeeting()
        #expect(!meeting.activity.isAsserted)

        await meeting.runtime.start(request([meet]))
        #expect(meeting.activity.isAsserted)
        #expect(meeting.activity.beginCount == 1)

        await meeting.runtime.stop()
        #expect(!meeting.activity.isAsserted)
        #expect(meeting.activity.endCount == 1)
    }

    @Test("A meeting that fails releases the assertion too")
    func activityIsReleasedOnFailure() async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([meet]))
        #expect(meeting.activity.isAsserted)

        meeting.capturer.interrupt(.interrupted("The stream stopped."))
        #expect(await wait { !meeting.activity.isAsserted })
        #expect(meeting.activity.endCount == 1)
    }

    // MARK: - Failure with no window

    @Test("A failure with no window open is still there when one is opened")
    func failureSurvivesUntilItIsSeen() async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([meet]))

        meeting.capturer.interrupt(.interrupted("The stream stopped."))
        #expect(await wait { !meeting.runtime.isRunning })

        let expected = AudioCaptureError.interrupted("The stream stopped.").errorDescription ?? ""
        #expect(meeting.runtime.status == .failed(message: expected))
        #expect(menuBar(meeting.runtime).failureMessage == expected)

        // Reopening the window prepares the screen again; nothing is cleared.
        await meeting.runtime.prepare()
        #expect(meeting.runtime.status == .failed(message: expected))
        #expect(meeting.runtime.meeting?.title == "Weekly Sync")
    }

    @Test("A retention failure with no window open ends the meeting and is reported")
    func retentionFailureIsReported() async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([meet], retention: .compressed))

        meeting.audio.reportFailure()
        #expect(await wait { !meeting.runtime.isRunning })

        #expect(meeting.runtime.status.failureMessage != nil)
        #expect(meeting.persistence.outcomes == [.failed])
        #expect(menuBar(meeting.runtime).statusLine == "Meeting failed")
        #expect(menuBar(meeting.runtime).audioURL != nil, "the partial recording is still named")
    }

    // MARK: - Retention

    @Test(
        "Application-scoped ownership leaves each retention mode's artifacts alone",
        arguments: [AudioRetentionMode.none, .raw, .compressed]
    )
    func retentionIsUnchanged(mode: AudioRetentionMode) async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([meet], retention: mode))
        meeting.capturer.deliver(buffer())
        await meeting.runtime.stop()

        let expectedURL = meeting.persistence.entries.compactMap { entry -> URL? in
            if case let .started(directory) = entry {
                SessionArtifactLayout(directory: directory).audioURL(for: mode)
            } else {
                nil
            }
        }.first

        #expect(meeting.audio.entries.first == .started(mode: mode, url: expectedURL))
        #expect(meeting.runtime.audioRetentionState.url == expectedURL)
        #expect(meeting.persistence.outcomes == [.completed])
        if mode.retainsAudio {
            #expect(meeting.audio.entries.last == .finished)
        } else {
            #expect(!meeting.audio.entries.contains(.finished))
        }
    }

    // MARK: - Configuration

    @Test("A meeting keeps the settings it started with")
    func configurationIsSnapshotAtStart() async throws {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([meet], title: "Weekly Sync", retention: .compressed))

        let snapshot = try #require(meeting.runtime.meeting)
        #expect(snapshot.title == "Weekly Sync")
        #expect(snapshot.sources == [meet])
        #expect(snapshot.destination == destination)
        #expect(snapshot.audioRetention == .compressed)
        #expect(snapshot.localeIdentifier == meeting.runtime.localeIdentifier)

        // What editing the setup screen mid-meeting amounts to: another
        // request, which the running meeting must not adopt.
        await meeting.runtime.start(
            request([browser], title: "Something Else", retention: .raw)
        )
        await meeting.runtime.selectLocale("fr-FR")

        #expect(meeting.runtime.meeting == snapshot)
        #expect(meeting.runtime.localeIdentifier == snapshot.localeIdentifier)
        #expect(meeting.audio.entries.count == 1)
        #expect(meeting.capturer.configurations.count == 1)
        #expect(meeting.capturer.configurations.first?.sourceIDs == [meet.id])
    }

    // MARK: - Recovery

    @Test("Recovery is unavailable while a meeting is running and available again after it")
    func recoveryIsGatedOnTheRuntime() async {
        let meeting = await makeMeeting()
        #expect(meeting.runtime.allowsRecovery)

        await meeting.runtime.start(request([meet]))
        #expect(!meeting.runtime.allowsRecovery)

        await meeting.runtime.stop()
        #expect(meeting.runtime.allowsRecovery)
        #expect(meeting.runtime.status == .completed)
    }

    @Test("A failed meeting is finished, so recovery may look at the folder again")
    func recoveryReturnsAfterAFailure() async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([meet]))
        meeting.capturer.interrupt(.interrupted("The stream stopped."))

        #expect(await wait { meeting.runtime.allowsRecovery })
    }

    // MARK: - Elapsed time

    @Test("Timing follows the meeting and writes nothing while it runs")
    func elapsedFollowsTheMeeting() async {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let meeting = await makeMeeting(startedAt: startedAt)
        #expect(meeting.clock.startedAt == nil)

        await meeting.runtime.start(request([meet]))
        #expect(meeting.clock.startedAt != nil)

        let entriesWhileTiming = meeting.persistence.entries.count
        for _ in 0..<5 { meeting.clock.refresh() }
        #expect(meeting.persistence.entries.count == entriesWhileTiming, "a tick is not a write")

        await meeting.runtime.stop()
        #expect(!meeting.clock.isTicking)
    }
}
