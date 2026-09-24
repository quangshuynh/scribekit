//
//  MicrophoneMeetingTests.swift
//  ScribeKitTests
//

import AppKit
import Foundation
import Testing
@testable import ScribeKit

/// In-memory setup preferences, so building the setup screen reads nothing
/// from the user's own preference store.
private nonisolated final class MemoryPreferences: MeetingSetupPreferencesStoring, @unchecked Sendable {
    var audioRetention: AudioRetentionMode = .none
    var rememberedSourceIDs: [String] = []
    var captureMode: CaptureMode = .microphone
}

/// A save location that remembers nothing.
private nonisolated final class NoSaveLocation: SaveLocationPersisting, @unchecked Sendable {
    func save(_ url: URL) throws {}
    func restore() throws -> URL? { nil }
    func clear() throws {}
}

/// An application list that is never asked for.
private nonisolated struct UnusedSourceProvider: CaptureSourceProviding {
    func availableSources() async throws -> [CaptureSource] { [] }
}

/// A Microphone meeting, driven through the same runtime, recogniser boundary,
/// writer and session record an App Audio meeting uses.
///
/// Microphone hardware is replaced at the capture boundary: a fake capturer
/// delivers buffers the way the audio engine's tap would, and permission is
/// stated rather than asked for. What is under test is everything the
/// microphone's audio passes through after that — which is the point, because
/// that is the part the two capture modes share.
@MainActor
@Suite("Microphone meetings")
struct MicrophoneMeetingTests {

    private let input = MicrophoneInput(id: "AppleUSBAudioEngine:Studio:1", name: "Studio Mic")
    private var microphone: CaptureSource { .microphone(input) }
    private let destination = URL(filePath: "/tmp/scribekit-tests", directoryHint: .isDirectory)

    private struct Meeting {
        let runtime: MeetingRuntime
        let capturer: FakeCapturer
        let transcriber: FakeSpeechTranscriber
        let persistence: FakeTranscriptPersistence
        let activity: FakeMeetingActivity
    }

    /// A runtime over doubles, prepared as the screen prepares it.
    private func makeMeeting() async -> Meeting {
        let transcriber = FakeSpeechTranscriber()
        let persistence = FakeTranscriptPersistence()
        let activity = FakeMeetingActivity()
        var capturer: FakeCapturer!
        let runtime = MeetingRuntime(
            monitor: AudioCaptureActivityMonitor(minimumPublishInterval: .zero),
            transcriber: transcriber,
            persistence: persistence,
            audio: FakeAudioRetention(),
            elapsed: MeetingElapsedClock(now: { Date(timeIntervalSince1970: 1_000) }, interval: nil),
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
            activity: activity
        )
    }

    private func request(
        _ sources: [CaptureSource],
        title: String = "Thinking Aloud",
        retention: AudioRetentionMode = .none,
        destination: URL? = nil
    ) -> MeetingStartRequest {
        MeetingStartRequest(
            title: title,
            sources: sources,
            destination: destination ?? self.destination,
            audioRetention: retention
        )
    }

    /// A buffer of the shape the microphone adapter delivers.
    private func buffer(frames: Int = 960, sampleRate: Double = 48_000) -> CapturedPCMBuffer {
        CapturedPCMBuffer(
            format: CapturedAudioFormat(
                sampleRate: sampleRate,
                channelCount: 1,
                bitsPerChannel: 32,
                isFloat: true,
                isInterleaved: false
            ),
            frameCount: frames,
            presentationTime: nil,
            peakAmplitude: 0.2,
            samples: [Float](repeating: 0.2, count: frames)
        )
    }

    private func segment(
        _ text: String,
        start: Double,
        state: TranscriptSegment.RecognitionState = .final
    ) -> TranscriptSegment {
        TranscriptSegment(text: text, startTime: start, endTime: start + 1, state: state, localeIdentifier: "en-US")
    }

    private func wait(for condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return condition()
    }

    // MARK: - Starting

    @Test("With permission, a Microphone meeting starts and listens to the input it was set up with")
    func startsWithPermission() async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([microphone]))

        #expect(meeting.runtime.status == .transcribing)
        #expect(meeting.runtime.meeting?.captureMode == .microphone)
        #expect(meeting.capturer.prepareCount == 1)
        #expect(meeting.capturer.preparedConfigurations.first?.mode == .microphone)
        #expect(meeting.capturer.configurations.last?.mode == .microphone)
        #expect(meeting.capturer.configurations.last?.sourceIDs == [input.id])
        #expect(meeting.runtime.audioRetentionState == .idle, "a Microphone meeting keeps no recording")
        #expect(meeting.runtime.requestedCaptureFormat == nil, "the device decides its own format")
        #expect(meeting.activity.isAsserted)
    }

    @Test("A refused permission ends the start before anything is created")
    func permissionDeniedCreatesNothing() async {
        let meeting = await makeMeeting()
        meeting.capturer.prepareError = .microphoneAccessDenied
        await meeting.runtime.start(request([microphone]))

        #expect(meeting.runtime.captureState.failureMessage?.contains("Privacy & Security › Microphone") == true)
        #expect(meeting.persistence.entries.isEmpty, "no transcript, no session record")
        #expect(meeting.transcriber.startCount == 0)
        #expect(meeting.capturer.startCount == 0)
        #expect(!meeting.runtime.isRunning)
        #expect(!meeting.activity.isAsserted)
        #expect(meeting.runtime.meeting == nil)
        #expect(meeting.runtime.outcome == nil, "a meeting that never began has no ending to report")

        // Access granted afterwards: the same screen starts normally.
        meeting.capturer.prepareError = nil
        await meeting.runtime.start(request([microphone]))
        #expect(meeting.runtime.status == .transcribing)
    }

    @Test("Through the real microphone capturer, a refusal prompts once and a restriction not at all")
    func realCapturerRefusalsLeaveNoArtifacts() async {
        let cases: [(authorization: MicrophoneAuthorization, prompts: Int)] = [
            (.notDetermined, 1), (.denied, 0), (.restricted, 0)
        ]
        for (authorization, prompts) in cases {
            let access = FakeMicrophoneAccess(authorization: authorization, answer: false, input: input)
            let persistence = FakeTranscriptPersistence()
            let runtime = MeetingRuntime(
                transcriber: FakeSpeechTranscriber(),
                persistence: persistence,
                audio: FakeAudioRetention(),
                processActivity: FakeMeetingActivity(),
                makeCapturer: { consumer in
                    CaptureModeRouter(
                        applications: FakeCapturer(consumer: consumer),
                        microphone: MicrophoneAudioCapturer(consumer: consumer, access: access)
                    )
                }
            )
            await runtime.prepare()
            await runtime.start(request([microphone]))

            #expect(access.requests == prompts)
            #expect(persistence.entries.isEmpty)
            #expect(runtime.captureState.failureMessage != nil)
            #expect(!runtime.isRunning)
        }
    }

    @Test("An input that fails to start closes the transcript as a start that never began")
    func inputStartupFailure() async {
        let meeting = await makeMeeting()
        meeting.capturer.startError = .systemFailure("The audio engine could not start.")
        await meeting.runtime.start(request([microphone]))

        #expect(meeting.persistence.outcomes == [.failed])
        #expect(meeting.runtime.captureState.failureMessage?.contains("could not start") == true)
        #expect(meeting.runtime.outcome?.category == .startFailure)
        #expect(!meeting.runtime.isRunning)
        #expect(meeting.transcriber.stopCount == 1)
        #expect(!meeting.activity.isAsserted)
    }

    @Test("A Microphone meeting that asks to keep audio is refused, not quietly changed")
    func retentionIsRefused() async {
        let meeting = await makeMeeting()
        #expect(!meeting.runtime.canStart(request([microphone], retention: .compressed)))
        await meeting.runtime.start(request([microphone], retention: .compressed))

        #expect(meeting.runtime.captureState.failureMessage?.contains("keep no audio") == true)
        #expect(meeting.persistence.entries.isEmpty)
        #expect(meeting.capturer.prepareCount == 0)
    }

    // MARK: - Conflicting starts

    @Test("Application audio and the microphone in one request are refused deterministically")
    func mixedRequestIsRefused() async {
        let meeting = await makeMeeting()
        let meet = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")
        #expect(!meeting.runtime.canStart(request([meet, microphone])))
        await meeting.runtime.start(request([meet, microphone]))

        #expect(meeting.runtime.captureState.failureMessage?.contains("not both") == true)
        #expect(meeting.capturer.prepareCount == 0)
        #expect(meeting.persistence.entries.isEmpty)
    }

    @Test("A second start while the first waits on a permission prompt is refused, and the first proceeds")
    func startDuringPromptIsRefused() async {
        let meeting = await makeMeeting()
        meeting.capturer.holdsPrepare = true
        let runtime = meeting.runtime
        let micRequest = request([microphone], title: "First")
        let first = Task { await runtime.start(micRequest) }
        #expect(await wait { meeting.capturer.isHoldingPrepare })
        #expect(meeting.runtime.captureState == .preparing)

        let meet = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")
        #expect(!meeting.runtime.canStart(request([meet], title: "Second")))
        await meeting.runtime.start(request([meet], title: "Second"))
        #expect(meeting.capturer.prepareCount == 1, "the second start never reached the capturer")

        meeting.capturer.releasePrepare()
        await first.value
        #expect(meeting.runtime.status == .transcribing)
        #expect(meeting.runtime.meeting?.title == "First")
        #expect(meeting.capturer.startCount == 1)
        #expect(meeting.capturer.configurations.map(\.mode) == [.microphone])
    }

    @Test("A running Microphone meeting refuses an App Audio start, and the other way round")
    func runningMeetingRefusesTheOtherMode() async {
        let meeting = await makeMeeting()
        let meet = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")
        await meeting.runtime.start(request([microphone]))
        await meeting.runtime.start(request([meet]))
        #expect(meeting.capturer.startCount == 1)
        #expect(meeting.runtime.meeting?.captureMode == .microphone)

        await meeting.runtime.stop()
        await meeting.runtime.start(request([meet]))
        await meeting.runtime.start(request([microphone]))
        #expect(meeting.capturer.startCount == 2)
        #expect(meeting.runtime.meeting?.captureMode == .applications)
    }

    // MARK: - Audio and speech

    @Test("Microphone audio reaches recognition and the media clock through the shared fan-out")
    func audioReachesThePipeline() async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([microphone]))
        for _ in 0..<50 { meeting.capturer.deliver(buffer(frames: 882, sampleRate: 44_100)) }

        #expect(meeting.transcriber.receivedBuffers.count == 50)
        #expect(abs(meeting.runtime.capturedDuration - 1.0) < 1e-9, "fifty 20 ms buffers at 44.1 kHz")
        #expect(await wait { meeting.runtime.activity.sampleCount == 50 })
    }

    @Test("Pause and resume keep media-time offsets, and resume listens to the same input")
    func pauseResumeMediaTime() async {
        let harness = ReliabilityHarness()
        await harness.start(title: "Microphone Pause", sources: [microphone])
        harness.deliver(seconds: 1, count: 10)
        let before = harness.emitFinal("Before the pause.")
        #expect(await harness.waitForSegments(1))

        await harness.pause(for: 600)
        #expect(harness.runtime.status == .paused)
        await harness.resume()
        harness.deliver(seconds: 1, count: 5)
        let after = harness.emitFinal("After the pause.")
        #expect(await harness.waitForSegments(2))

        #expect(harness.writtenOffsets == [before, after])
        #expect(harness.writtenOffsets == [10, 15], "ten minutes paused added nothing to media time")
        #expect(harness.markerDurations == [10, 10])
        #expect(harness.capturer.configurations.count == 2)
        #expect(harness.capturer.configurations[0] == harness.capturer.configurations[1])
    }

    @Test("A resume refused because the input changed leaves the meeting paused and resumable")
    func resumeRefusedWhenInputChanged() async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([microphone]))
        await meeting.runtime.pause()
        meeting.capturer.startError = .microphoneInputChanged
        await meeting.runtime.resume()

        #expect(meeting.runtime.status == .paused)
        #expect(meeting.runtime.pauseFailureMessage?.contains("does not switch microphones") == true)
        #expect(meeting.persistence.isOpen)

        meeting.capturer.startError = nil
        await meeting.runtime.resume()
        #expect(meeting.runtime.status == .transcribing)
    }

    @Test("Stop finalises the meeting as completed, in the ordinary order")
    func stopFinalises() async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([microphone]))
        meeting.transcriber.emit(.final(segment("Last words.", start: 0)))
        await meeting.runtime.stop()

        #expect(meeting.persistence.segments.map(\.text) == ["Last words."])
        #expect(meeting.persistence.outcomes == [.completed])
        #expect(meeting.capturer.stopCount == 1)
        #expect(!meeting.capturer.isCapturing)
        #expect(!meeting.runtime.isRunning)
        #expect(!meeting.activity.isAsserted)
        #expect(meeting.runtime.outcome?.category == .completed)
    }

    @Test("The input changing mid-meeting ends it as interrupted, keeping everything written")
    func inputChangeInterrupts() async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([microphone]))
        meeting.transcriber.emit(.final(segment("Said before the headset was unplugged.", start: 0)))
        #expect(await wait { meeting.persistence.segments.count == 1 })

        meeting.capturer.interrupt(.interrupted(MicrophoneAudioCapturer.configurationChangeDescription))
        #expect(await wait { meeting.persistence.outcomes == [.interrupted] })

        #expect(meeting.runtime.outcome?.category == .interrupted)
        #expect(meeting.runtime.captureState.failureMessage?.contains("rather than switch") == true)
        #expect(meeting.persistence.segments.map(\.text) == ["Said before the headset was unplugged."])
        #expect(await wait { !meeting.activity.isAsserted })
    }

    @Test("A recogniser that falls behind the microphone leaves one gap incident, as for App Audio")
    func gapIncidentsAreShared() async throws {
        let harness = ReliabilityHarness()
        await harness.start(title: "Microphone Backlog", sources: [microphone])
        harness.deliver(seconds: 1, count: 120)
        for step in 0..<40 {
            let start = 60 + Double(step) * 0.5
            harness.dropAudio(seconds: 0.5, from: start, to: start + 0.5)
        }
        harness.reportRecognitionCaughtUp()

        #expect(await harness.wait { harness.writtenGaps.count == 1 })
        let gap = try #require(harness.writtenGaps.first)
        #expect(gap.reason == .audioDropped)
        #expect(gap.startTime == 60)
        #expect(gap.endTime == 80)
        #expect(abs(gap.duration - 20) < 0.001)
    }

    // MARK: - Durable Markdown, the session record, recovery and History

    /// Runs work in a save folder of its own, removed afterwards.
    private func withSaveFolder(_ body: (URL) async throws -> Void) async throws {
        let root = URL.temporaryDirectory.appending(
            path: "scribekit-microphone-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }

    /// A runtime writing real files.
    private func makeDurableMeeting(zone: TimeZone) -> (MeetingRuntime, FakeSpeechTranscriber, FakeCapturer) {
        let transcriber = FakeSpeechTranscriber()
        var capturer: FakeCapturer!
        let runtime = MeetingRuntime(
            monitor: AudioCaptureActivityMonitor(minimumPublishInterval: .zero),
            transcriber: transcriber,
            persistence: MarkdownTranscriptStore(access: FakeSecurityScopedAccess(), timeZone: zone),
            audio: RetainedAudioRecorder(),
            elapsed: MeetingElapsedClock(now: { Date(timeIntervalSince1970: 1_000) }, interval: nil),
            processActivity: FakeMeetingActivity(),
            makeCapturer: { consumer in
                capturer = FakeCapturer(consumer: consumer)
                return capturer
            }
        )
        return (runtime, transcriber, capturer)
    }

    @Test("Finalised microphone speech reaches durable Markdown that names its source, and History reads it")
    func durableMarkdownAndHistory() async throws {
        try await withSaveFolder { root in
            let zone = TimeZone(identifier: "America/New_York")!
            let (runtime, transcriber, capturer) = makeDurableMeeting(zone: zone)
            await runtime.prepare()
            await runtime.start(request([microphone], title: "Microphone Notes", destination: root))
            let layout = try #require(runtime.persistenceState.layout)

            capturer.deliver(buffer())
            transcriber.emit(.final(segment("The quick brown fox jumps over the lazy dog.", start: 0)))
            transcriber.emit(.partial(segment("A guess that is never saved", start: 2, state: .partial)))
            await runtime.stop()

            let text = try String(contentsOf: layout.transcriptURL, encoding: .utf8)
            #expect(text.contains("**Sources:** Microphone (Studio Mic)\n"))
            #expect(text.contains("The quick brown fox jumps over the lazy dog."))
            #expect(!text.contains("never saved"))
            #expect(text.contains("**Ended:**"))

            let record = try SessionRecoveryMetadata.decoded(from: Data(contentsOf: layout.metadataURL))
            #expect(record.captureMode == .microphone)
            #expect(record.sourceNames == ["Microphone (Studio Mic)"])
            #expect(record.status == .completed)
            #expect(record.audioRetention == AudioRetentionMode.none)
            #expect(record.audioPath == nil)
            let recordText = try String(contentsOf: layout.metadataURL, encoding: .utf8)
            #expect(!recordText.contains(input.id), "the device identifier is never written")

            let files = try FileManager.default
                .contentsOfDirectory(at: layout.directory, includingPropertiesForKeys: nil)
                .map(\.lastPathComponent)
            #expect(!files.contains { $0.hasPrefix("audio.") }, "no microphone audio reaches the disk")

            let history = try await HistoryService(store: FileManagerHistoryStore(), access: FakeSecurityScopedAccess())
                .load(root)
            let document = try #require(history.documents.first)
            #expect(document.session.captureMode == .microphone)
            #expect(document.session.sourceNames == ["Microphone (Studio Mic)"])
            #expect(document.spans.map(\.text) == ["The quick brown fox jumps over the lazy dog."])
        }
    }

    @Test("A Microphone meeting ScribeKit never finished is recovered as one")
    func recoveryIdentifiesMicrophoneMeetings() async throws {
        try await withSaveFolder { root in
            let zone = TimeZone(identifier: "America/New_York")!
            let (runtime, transcriber, _) = makeDurableMeeting(zone: zone)
            await runtime.prepare()
            await runtime.start(request([microphone], title: "Cut Short", destination: root))
            transcriber.emit(.final(segment("Durable before the crash.", start: 0)))
            let layout = try #require(runtime.persistenceState.layout)
            #expect(await wait {
                (try? String(contentsOf: layout.transcriptURL, encoding: .utf8))?
                    .contains("Durable before the crash.") == true
            })

            // Read from disk as a fresh launch would, with the meeting still
            // open: exactly what a killed process leaves behind.
            let report = try await SessionRecoveryService(access: FakeSecurityScopedAccess(), timeZone: zone)
                .scan(root)
            let candidate = try #require(report.candidates.first)
            #expect(candidate.metadata.captureMode == .microphone)
            #expect(candidate.metadata.status == .inProgress)
            #expect(candidate.metadata.sourceNames == ["Microphone (Studio Mic)"])

            await runtime.stop()
        }
    }

    // MARK: - Lifetime

    @Test("Losing focus, hiding, minimising and closing windows are not inputs to a running meeting")
    func applicationStateDoesNotControlTheMeeting() async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([microphone]))

        let center = NotificationCenter.default
        for name in [
            NSApplication.willResignActiveNotification,
            NSApplication.didResignActiveNotification,
            NSApplication.willHideNotification,
            NSApplication.didHideNotification,
            NSApplication.didChangeOcclusionStateNotification
        ] {
            center.post(name: name, object: NSApplication.shared)
        }
        // A window of the test's own, so every observer receives the kind of
        // object these notifications always carry.
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        for name in [
            NSWindow.didMiniaturizeNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.willCloseNotification
        ] {
            center.post(name: name, object: window)
        }
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current]
        )
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
        await Task.yield()

        #expect(meeting.runtime.status == .transcribing)
        #expect(meeting.capturer.stopCount == 0)
        #expect(meeting.transcriber.stopCount == 0)
        #expect(meeting.persistence.isOpen)
        #expect(meeting.activity.isAsserted)

        // And it is still doing its work, not merely still claiming to.
        meeting.capturer.deliver(buffer())
        meeting.transcriber.emit(.final(segment("Spoken while ScribeKit was in the background.", start: 0)))
        #expect(await wait { meeting.persistence.segments.count == 1 })
        #expect(meeting.transcriber.receivedBuffers.count == 1)
    }

    @Test("Building, switching and discarding the window's screens changes nothing about the meeting")
    func viewRecreationAndTabSwitching() async {
        let meeting = await makeMeeting()
        await meeting.runtime.start(request([microphone]))
        let diagnostics = MeetingDiagnostics(runtime: meeting.runtime)
        let access = FakeMicrophoneAccess(authorization: .authorized, input: input)

        for _ in 0..<5 {
            let selection = ScribeKitTabSelection()
            _ = ScribeKitRootView(runtime: meeting.runtime, diagnostics: diagnostics)
            _ = MeetingSetupView(
                runtime: meeting.runtime,
                diagnostics: diagnostics,
                sourceProvider: UnusedSourceProvider(),
                microphoneAccess: access,
                saveLocation: NoSaveLocation(),
                preferences: MemoryPreferences()
            )
            _ = HistoryView(runtime: meeting.runtime, model: HistoryModel(saveLocation: NoSaveLocation()))
            selection.tab = .history
            selection.tab = .meeting
        }

        #expect(meeting.runtime.status == .transcribing)
        #expect(meeting.capturer.startCount == 1)
        #expect(meeting.capturer.stopCount == 0)
        #expect(meeting.transcriber.startCount == 1)
        #expect(meeting.persistence.isOpen)
        #expect(!access.wasConsulted, "building the screen reads nothing until it appears")
    }

    // MARK: - App Audio is unchanged

    @Test("An App Audio meeting never consults the microphone and keeps its own behaviour")
    func applicationAudioIsUnchanged() async {
        let access = FakeMicrophoneAccess(authorization: .notDetermined, input: input)
        var applications: FakeCapturer!
        let persistence = FakeTranscriptPersistence()
        let audio = FakeAudioRetention()
        let runtime = MeetingRuntime(
            transcriber: FakeSpeechTranscriber(),
            persistence: persistence,
            audio: audio,
            processActivity: FakeMeetingActivity(),
            makeCapturer: { consumer in
                applications = FakeCapturer(consumer: consumer)
                return CaptureModeRouter(
                    applications: applications,
                    microphone: MicrophoneAudioCapturer(consumer: consumer, access: access)
                )
            }
        )
        await runtime.prepare()
        let meet = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")
        await runtime.start(request([meet], retention: .compressed))

        #expect(runtime.status == .transcribing)
        #expect(runtime.meeting?.captureMode == .applications)
        #expect(applications.configurations.last?.mode == .applications)
        #expect(applications.configurations.last?.sourceIDs == ["com.example.Meet"])
        #expect(runtime.audioRetentionState.url != nil, "App Audio still keeps audio when asked")
        #expect(runtime.requestedCaptureFormat?.sampleRate == 48_000)

        await runtime.pause()
        await runtime.resume()
        await runtime.stop()
        #expect(persistence.outcomes == [.completed])
        #expect(!access.wasConsulted, "no microphone permission is read, asked for or needed")
    }

    @Test("A diagnostic report says a meeting used the microphone without naming it")
    func diagnosticsNameTheModeOnly() async throws {
        let harness = ReliabilityHarness()
        let canary = MicrophoneInput(id: "CanaryDevice-7731", name: "Canary Microphone 7731")
        await harness.start(title: "Canary Title 7731", sources: [.microphone(canary)])
        harness.deliver(seconds: 1, count: 3)

        let diagnostics = MeetingDiagnostics(runtime: harness.runtime)
        let report = diagnostics.makeReport()
        let json = try String(decoding: report.encoded(), as: UTF8.self)
        #expect(!json.contains("Canary Microphone 7731"))
        #expect(!json.contains("CanaryDevice-7731"))
        #expect(report.session?.captureMode == "microphone")
        #expect(report.session?.capturedSampleRate == nil, "a microphone asks for no format")
        await harness.stop()
    }
}
