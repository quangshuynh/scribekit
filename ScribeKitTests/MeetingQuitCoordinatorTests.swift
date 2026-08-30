//
//  MeetingQuitCoordinatorTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@MainActor
@Suite("MeetingQuitCoordinator")
struct MeetingQuitCoordinatorTests {

    private let meet = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")
    private let destination = URL(filePath: "/tmp/scribekit-tests", directoryHint: .isDirectory)

    /// A runtime over doubles, prepared as the screen prepares it.
    ///
    /// - Returns: The runtime, its capturer and its transcript writer.
    private func makeRuntime() async -> (MeetingRuntime, FakeCapturer, FakeTranscriptPersistence) {
        let persistence = FakeTranscriptPersistence()
        var capturer: FakeCapturer!
        let runtime = MeetingRuntime(
            monitor: AudioCaptureActivityMonitor(minimumPublishInterval: .zero),
            transcriber: FakeSpeechTranscriber(),
            persistence: persistence,
            audio: FakeAudioRetention(),
            elapsed: MeetingElapsedClock(interval: nil),
            processActivity: FakeMeetingActivity(),
            makeCapturer: { consumer in
                capturer = FakeCapturer(consumer: consumer)
                return capturer
            }
        )
        await runtime.prepare()
        return (runtime, capturer, persistence)
    }

    private func request() -> MeetingStartRequest {
        MeetingStartRequest(title: "Weekly Sync", sources: [meet], destination: destination)
    }

    /// Records what the coordinator asked and reported.
    private final class Answers {
        var confirmCount = 0
        var finishes: [Bool] = []
    }

    @Test("Quitting with no meeting running terminates without asking")
    func quitsWhenIdle() async {
        let (runtime, capturer, _) = await makeRuntime()
        let answers = Answers()
        let coordinator = MeetingQuitCoordinator(
            runtime: runtime,
            confirmStop: { answers.confirmCount += 1; return true },
            finish: { answers.finishes.append($0) }
        )

        #expect(coordinator.applicationShouldTerminate() == .terminateNow)
        #expect(answers.confirmCount == 0)
        #expect(answers.finishes.isEmpty)
        #expect(capturer.stopCount == 0)
    }

    @Test("A finished meeting does not make quitting ask again")
    func quitsAfterAMeeting() async {
        let (runtime, _, _) = await makeRuntime()
        await runtime.start(request())
        await runtime.stop()

        let answers = Answers()
        let coordinator = MeetingQuitCoordinator(
            runtime: runtime,
            confirmStop: { answers.confirmCount += 1; return true },
            finish: { answers.finishes.append($0) }
        )

        #expect(coordinator.applicationShouldTerminate() == .terminateNow)
        #expect(answers.confirmCount == 0)
    }

    @Test("Cancelling the question leaves the meeting exactly as it was")
    func cancellingKeepsTheMeeting() async {
        let (runtime, capturer, persistence) = await makeRuntime()
        await runtime.start(request())

        let answers = Answers()
        let coordinator = MeetingQuitCoordinator(
            runtime: runtime,
            confirmStop: { answers.confirmCount += 1; return false },
            finish: { answers.finishes.append($0) }
        )

        #expect(coordinator.applicationShouldTerminate() == .cancel)
        #expect(answers.confirmCount == 1)
        #expect(answers.finishes.isEmpty)
        #expect(coordinator.stopTask == nil)
        #expect(runtime.status == .transcribing)
        #expect(capturer.stopCount == 0)
        #expect(persistence.isOpen)
    }

    @Test("Choosing to quit stops the meeting properly before termination continues")
    func stoppingFinishesTheMeetingFirst() async {
        let (runtime, capturer, persistence) = await makeRuntime()
        await runtime.start(request())

        let answers = Answers()
        let coordinator = MeetingQuitCoordinator(
            runtime: runtime,
            confirmStop: { answers.confirmCount += 1; return true },
            finish: { answers.finishes.append($0) }
        )

        #expect(coordinator.applicationShouldTerminate() == .terminateLater)
        #expect(answers.confirmCount == 1)
        #expect(answers.finishes.isEmpty, "termination waits for the stop, it does not race it")

        await coordinator.stopTask?.value

        #expect(answers.finishes == [true])
        #expect(capturer.stopCount == 1)
        #expect(!persistence.isOpen)
        #expect(persistence.outcomes == [.completed])
        #expect(runtime.status == .completed)
    }
}
