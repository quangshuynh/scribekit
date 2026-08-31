//
//  MeetingRuntimeTests.swift
//  ScribeKitTests
//

import Foundation
import Synchronization
import Testing
@testable import ScribeKit

@MainActor
@Suite("MeetingRuntime")
struct MeetingRuntimeTests {

    private let meet = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")
    private let browser = CaptureSource.application(bundleIdentifier: "com.example.Browser", displayName: "Browser")

    private let format = CapturedAudioFormat(
        sampleRate: 48_000,
        channelCount: 1,
        bitsPerChannel: 32,
        isFloat: true,
        isInterleaved: false
    )

    /// Builds a model over a fake capturer and a fake transcriber, prepared as
    /// the screen prepares it.
    ///
    /// - Parameter availability: What the recogniser reports about itself.
    /// - Returns: The model and the two fakes behind it.
    private func makeModel(
        availability: SpeechRecognitionAvailability = .available(localeIdentifier: "en-US")
    ) async -> (MeetingRuntime, FakeCapturer, FakeSpeechTranscriber) {
        let (model, capturer, transcriber, _) = await makeMeeting(availability: availability)
        return (model, capturer, transcriber)
    }

    /// Builds a model over fake capture, recognition and transcript writing.
    ///
    /// - Parameter availability: What the recogniser reports about itself.
    /// - Returns: The model and the three doubles behind it.
    private func makeMeeting(
        availability: SpeechRecognitionAvailability = .available(localeIdentifier: "en-US")
    ) async -> (MeetingRuntime, FakeCapturer, FakeSpeechTranscriber, FakeTranscriptPersistence) {
        let (model, capturer, transcriber, persistence, _) = await makeRetainingMeeting(availability: availability)
        return (model, capturer, transcriber, persistence)
    }

    /// Builds a model over fake capture, recognition, transcript writing and
    /// audio retention.
    ///
    /// - Parameter availability: What the recogniser reports about itself.
    /// - Returns: The model and the four doubles behind it.
    private func makeRetainingMeeting(
        availability: SpeechRecognitionAvailability = .available(localeIdentifier: "en-US")
    ) async -> (
        MeetingRuntime,
        FakeCapturer,
        FakeSpeechTranscriber,
        FakeTranscriptPersistence,
        FakeAudioRetention
    ) {
        let transcriber = FakeSpeechTranscriber()
        transcriber.availabilityResult = availability
        let persistence = FakeTranscriptPersistence()
        let audio = FakeAudioRetention()
        var capturer: FakeCapturer!
        let model = MeetingRuntime(
            monitor: AudioCaptureActivityMonitor(minimumPublishInterval: .zero),
            transcriber: transcriber,
            persistence: persistence,
            audio: audio,
            makeCapturer: { consumer in
                capturer = FakeCapturer(consumer: consumer)
                return capturer
            }
        )
        await model.prepare()
        return (model, capturer, transcriber, persistence, audio)
    }

    /// The folder a test meeting writes to. Nothing is created there; the
    /// writer is a double.
    private let destination = URL(filePath: "/tmp/scribekit-tests", directoryHint: .isDirectory)

    /// A meeting to start, over the given selection.
    ///
    /// - Parameter sources: The applications to capture.
    /// - Returns: The request.
    private func request(
        _ sources: [CaptureSource],
        title: String = "Interval Six",
        retention: AudioRetentionMode = .none
    ) -> MeetingStartRequest {
        MeetingStartRequest(
            title: title,
            sources: sources,
            destination: destination,
            audioRetention: retention
        )
    }

    /// A synthetic buffer of the shape ScreenCaptureKit delivers.
    ///
    /// - Parameters:
    ///   - frames: How many frames to carry.
    ///   - peak: The level to report.
    /// - Returns: A buffer ready to deliver.
    private func buffer(frames: Int, peak: Float = 0.25) -> CapturedPCMBuffer {
        CapturedPCMBuffer(
            format: format,
            frameCount: frames,
            presentationTime: 12,
            peakAmplitude: peak,
            samples: [Float](repeating: peak, count: frames)
        )
    }

    /// A finalised segment, as a recogniser would report one.
    ///
    /// - Parameters:
    ///   - text: The recognised text.
    ///   - start: Seconds from the start of the run.
    /// - Returns: The segment.
    private func segment(_ text: String, start: Double = 0) -> TranscriptSegment {
        TranscriptSegment(
            text: text,
            startTime: start,
            endTime: start + 1,
            state: .final,
            localeIdentifier: "en-US"
        )
    }

    /// The state the model should reach when a capture error is reported.
    ///
    /// - Parameter error: The error the capturer raised.
    /// - Returns: The expected failure state.
    private func failure(_ error: AudioCaptureError) -> AudioCaptureState {
        .failed(message: error.errorDescription ?? "")
    }

    /// Waits for a main-actor condition that a background delivery will satisfy.
    ///
    /// - Parameter condition: The condition to wait for.
    /// - Returns: `true` when it became true before the attempts ran out.
    private func wait(for condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test("Starting from idle captures the selected applications")
    func startsFromIdle() async {
        let (model, capturer, _) = await makeModel()
        #expect(model.captureState == .idle)
        #expect(model.canStart(request([meet])))

        await model.start(request([meet, browser]))

        #expect(model.captureState == .capturing)
        #expect(capturer.startCount == 1)
        #expect(capturer.configurations.first?.sourceIDs == [meet.id, browser.id])
        #expect(capturer.configurations.first?.sampleRate == AudioCaptureConfiguration.defaultSampleRate)
        #expect(capturer.configurations.first?.channelCount == AudioCaptureConfiguration.defaultChannelCount)
    }

    @Test("Starting is not offered without a selection")
    func startNeedsSelection() async {
        let (model, capturer, _) = await makeModel()

        #expect(!model.canStart(request([])))

        await model.start(request([]))

        #expect(model.captureState == failure(.noSourcesSelected))
        #expect(capturer.isCapturing == false)
    }

    @Test("Starting again while capturing does not reach the capturer")
    func duplicateStartIsIgnored() async {
        let (model, capturer, _) = await makeModel()
        await model.start(request([meet]))

        #expect(!model.canStart(request([meet])))
        await model.start(request([meet]))

        #expect(model.captureState == .capturing)
        #expect(capturer.startCount == 1)
    }

    @Test("Stopping while capturing returns to idle")
    func stopsFromCapturing() async {
        let (model, capturer, _) = await makeModel()
        await model.start(request([meet]))

        #expect(model.canStop)
        await model.stop()

        #expect(model.captureState == .idle)
        #expect(capturer.stopCount == 1)
        #expect(capturer.isCapturing == false)
    }

    @Test("Stopping while idle does nothing")
    func stopWhileIdleIsHarmless() async {
        let (model, capturer, _) = await makeModel()

        #expect(!model.canStop)
        await model.stop()
        await model.stop()

        #expect(model.captureState == .idle)
        #expect(capturer.stopCount == 0)
    }

    @Test("Capture can be started again after being stopped")
    func restartsAfterStop() async {
        let (model, capturer, _) = await makeModel()
        await model.start(request([meet]))
        await model.stop()

        await model.start(request([meet]))

        #expect(model.captureState == .capturing)
        #expect(capturer.startCount == 2)
    }

    @Test("A refused start is reported as a failure, not as capture")
    func startFailureIsReported() async {
        let (model, capturer, _) = await makeModel()
        capturer.startError = .permissionDenied

        await model.start(request([meet]))

        #expect(model.captureState == failure(.permissionDenied))
        #expect(!model.canStop)
        #expect(model.canStart(request([meet])))
    }

    @Test("A selected application that is gone is named in the failure")
    func missingSourceIsNamed() async {
        let (model, capturer, _) = await makeModel()
        capturer.startError = .sourcesUnavailable([meet.id])

        await model.start(request([meet, browser]))

        #expect(model.captureState == .failed(message: "No longer running, so capture did not start: Meet"))
    }

    @Test("A stream that stops by itself moves capture into failure")
    func interruptionFailsCapture() async {
        let (model, capturer, _) = await makeModel()
        await model.start(request([meet]))

        capturer.interrupt(.interrupted("The stream was stopped by the user"))

        #expect(await wait { model.captureState != .capturing })
        #expect(model.captureState == .failed(message: "Capture stopped: The stream was stopped by the user"))
    }

    @Test("An interruption after a deliberate stop does not overwrite the idle state")
    func lateInterruptionIsIgnored() async {
        let (model, capturer, _) = await makeModel()
        await model.start(request([meet]))
        await model.stop()

        capturer.interrupt(.interrupted("The stream was stopped by the user"))
        try? await Task.sleep(for: .milliseconds(50))

        #expect(model.captureState == .idle)
    }

    @Test("Delivered samples reach the published activity")
    func activityFollowsDeliveredSamples() async {
        let (model, capturer, transcriber) = await makeModel()
        await model.start(request([meet]))
        #expect(model.activity == .none)

        capturer.deliver(buffer(frames: 1_024))

        #expect(await wait { model.activity.sampleCount == 1 })
        #expect(model.activity.frameCount == 1_024)
        #expect(model.activity.format == format)
        #expect(model.activity.peakAmplitude == 0.25)
        #expect(transcriber.receivedBuffers.count == 1)
    }

    @Test("A new capture starts from empty activity")
    func activityResetsOnStart() async {
        let (model, capturer, _) = await makeModel()
        await model.start(request([meet]))
        capturer.deliver(buffer(frames: 512, peak: 0.5))
        #expect(await wait { model.activity.sampleCount == 1 })

        await model.stop()
        await model.start(request([meet]))

        #expect(await wait { model.activity == .none })
    }

    // MARK: - Transcription

    @Test("Recognition is started before capture, so no audio is captured unheard")
    func startsRecognitionBeforeCapture() async {
        let (model, capturer, transcriber) = await makeModel()

        await model.start(request([meet]))

        #expect(model.transcriptionState == .transcribing)
        #expect(model.captureState == .capturing)
        #expect(transcriber.startCount == 1)
        #expect(transcriber.configurations.first?.localeIdentifier == "en-US")
        #expect(capturer.startCount == 1)
    }

    @Test("A recogniser that will not start stops the pipeline before capture begins")
    func recognitionFailureStopsStart() async {
        let (model, capturer, transcriber) = await makeModel()
        transcriber.startError = .systemFailure("no model")

        await model.start(request([meet]))

        #expect(model.transcriptionState == .failed(message: "Transcription could not start: no model"))
        #expect(model.captureState == .idle)
        #expect(capturer.startCount == 0)
    }

    @Test("Capture failing after recognition started tears the recogniser down again")
    func captureFailureStopsRecognition() async {
        let (model, capturer, transcriber) = await makeModel()
        capturer.startError = .permissionDenied

        await model.start(request([meet]))

        #expect(model.captureState == failure(.permissionDenied))
        #expect(model.transcriptionState == .idle)
        #expect(transcriber.stopCount == 1)
    }

    @Test("Unavailable recognition is reported instead of capturing audio nothing will read")
    func unavailableRecognitionRefusesStart() async {
        let (model, capturer, transcriber) = await makeModel(
            availability: .modelNotInstalled(localeIdentifier: "de-DE")
        )

        #expect(!model.canStart(request([meet])))
        await model.start(request([meet]))

        #expect(model.captureState == .idle)
        #expect(transcriber.startCount == 0)
        #expect(capturer.startCount == 0)
        if case .failed = model.transcriptionState {} else {
            Issue.record("Expected a failure explaining the missing model")
        }
    }

    @Test("Stopping stops capture first and the recogniser afterwards")
    func stopFinalisesRecognitionAfterCapture() async {
        let (model, capturer, transcriber) = await makeModel()
        await model.start(request([meet]))

        await model.stop()

        #expect(model.captureState == .idle)
        #expect(model.transcriptionState == .idle)
        #expect(capturer.stopCount == 1)
        #expect(transcriber.stopCount == 1)
    }

    @Test("The pipeline can be started again after being stopped")
    func restartsWholePipeline() async {
        let (model, capturer, transcriber) = await makeModel()
        await model.start(request([meet]))
        await model.stop()

        await model.start(request([meet]))

        #expect(model.captureState == .capturing)
        #expect(model.transcriptionState == .transcribing)
        #expect(transcriber.startCount == 2)
        #expect(capturer.startCount == 2)
    }

    @Test("Repeated partials leave one live guess and no transcript entries")
    func partialsDoNotAccumulate() async {
        let (model, _, transcriber) = await makeModel()
        await model.start(request([meet]))

        for text in ["Today", "Today we", "Today we are"] {
            transcriber.emit(.partial(TranscriptSegment(
                text: text,
                startTime: 0,
                endTime: 2,
                state: .partial,
                localeIdentifier: "en-US"
            )))
        }

        #expect(await wait { model.transcript.partialSegment?.text == "Today we are" })
        #expect(model.transcript.finalizedSegments.isEmpty)
    }

    @Test("A finalised span replaces the live guess with exactly one entry")
    func finalReplacesPartial() async {
        let (model, _, transcriber) = await makeModel()
        await model.start(request([meet]))
        transcriber.emit(.partial(TranscriptSegment(
            text: "Today we",
            startTime: 0,
            endTime: 2,
            state: .partial,
            localeIdentifier: "en-US"
        )))
        #expect(await wait { model.transcript.partialSegment != nil })

        transcriber.emit(.final(segment("Today we are learning Swift.")))

        #expect(await wait { model.transcript.finalizedSegments.count == 1 })
        #expect(model.transcript.partialSegment == nil)
        #expect(model.transcript.finalizedSegments.first?.text == "Today we are learning Swift.")
    }

    @Test("A recogniser that stops by itself is restarted while capture continues")
    func recoversFromRecognitionInterruption() async {
        let (model, capturer, transcriber) = await makeModel()
        await model.start(request([meet]))

        transcriber.emit(.interrupted(.recognitionFailed(message: "resources")))

        #expect(await wait { transcriber.startCount == 2 })
        #expect(model.transcriptionState == .transcribing)
        #expect(model.captureState == .capturing)
        #expect(capturer.stopCount == 0)
        #expect(model.transcript.lastInterruption != nil)
    }

    @Test("A recogniser that keeps stopping is reported as failed rather than restarted forever")
    func boundedRecoveryAttempts() async {
        let (model, _, transcriber) = await makeModel()
        await model.start(request([meet]))

        for _ in 0...MeetingRuntime.maximumRecoveryAttempts {
            transcriber.emit(.interrupted(.recognitionFailed(message: "resources")))
            try? await Task.sleep(for: .milliseconds(30))
        }

        #expect(await wait {
            if case .failed = model.transcriptionState { return true }
            return false
        })
        #expect(transcriber.startCount <= MeetingRuntime.maximumRecoveryAttempts + 1)
    }

    @Test("Dropped audio is recorded as a gap rather than passed over")
    func droppedAudioIsRecorded() async {
        let (model, _, transcriber) = await makeModel()
        await model.start(request([meet]))

        transcriber.emit(.interrupted(.audioDropped(seconds: 1.5)))

        #expect(await wait { model.transcript.untranscribedSeconds == 1.5 })
    }

    @Test("Capture stopping by itself also stops recognition")
    func captureInterruptionStopsRecognition() async {
        let (model, capturer, transcriber) = await makeModel()
        await model.start(request([meet]))

        capturer.interrupt(.interrupted("The stream was stopped by the user"))

        #expect(await wait { model.transcriptionState == .idle })
        #expect(transcriber.stopCount == 1)
        if case .failed = model.captureState {} else {
            Issue.record("Expected capture to report the interruption")
        }
    }

    @Test("A new run starts from an empty transcript")
    func transcriptResetsOnStart() async {
        let (model, _, transcriber) = await makeModel()
        await model.start(request([meet]))
        transcriber.emit(.final(segment("First run.")))
        #expect(await wait { model.transcript.finalizedSegments.count == 1 })
        await model.stop()

        await model.start(request([meet]))

        #expect(model.transcript.isEmpty)
    }

    @Test("The locale is explicit and only changes when it is chosen")
    func localeSelectionIsExplicit() async {
        let (model, _, transcriber) = await makeModel()
        transcriber.locales = [
            TranscriptionLocale(id: "en-US", isInstalled: true),
            TranscriptionLocale(id: "fr-FR", isInstalled: true)
        ]
        await model.prepare()

        await model.selectLocale("fr-FR")

        #expect(model.localeIdentifier == "fr-FR")
        #expect(model.availableLocales.map(\.id) == ["en-US", "fr-FR"])

        await model.start(request([meet]))
        await model.selectLocale("en-US")

        #expect(model.localeIdentifier == "fr-FR")
    }

    // MARK: - Durable transcript

    @Test("Starting a meeting creates the transcript before anything is captured")
    func sessionIsCreatedFirst() async {
        let (model, capturer, transcriber, persistence) = await makeMeeting()

        await model.start(request([meet]))

        if case let .started(directory) = persistence.entries.first {
            #expect(directory.deletingLastPathComponent().path() == destination.path())
            #expect(directory.lastPathComponent.hasSuffix("-interval-six"))
        } else {
            Issue.record("Expected the session directory to be created first")
        }
        #expect(persistence.isOpen)
        #expect(transcriber.startCount == 1)
        #expect(capturer.startCount == 1)
        if case .saving = model.persistenceState {} else {
            Issue.record("Expected the meeting to be saving")
        }
    }

    @Test("A meeting cannot start without somewhere to write its transcript")
    func startNeedsADestination() async {
        let (model, _, _) = await makeModel()

        #expect(!model.canStart(nil))
    }

    @Test("A transcript that cannot be created stops the meeting before it captures anything")
    func persistenceFailurePreventsStart() async {
        let (model, capturer, transcriber, persistence) = await makeMeeting()
        persistence.failStart(with: TranscriptPersistenceError(.directoryCreationFailed))

        await model.start(request([meet]))

        #expect(model.captureState == .idle)
        #expect(model.transcriptionState == .idle)
        #expect(model.persistenceState.failureMessage != nil)
        #expect(transcriber.startCount == 0)
        #expect(capturer.startCount == 0)
        #expect(!persistence.isOpen)
    }

    @Test("A recogniser that will not start closes the transcript it had opened, unfinished")
    func recognitionFailureClosesTheSession() async {
        let (model, _, transcriber, persistence) = await makeMeeting()
        transcriber.startError = .systemFailure("no model")

        await model.start(request([meet]))

        #expect(!persistence.isOpen)
        // The meeting never captured a second, so it did not finish: it never
        // began.
        #expect(persistence.entries.last == .finished(.failed))
    }

    @Test("Capture that will not start closes the transcript it had opened, unfinished")
    func captureFailureClosesTheSession() async {
        let (model, capturer, _, persistence) = await makeMeeting()
        capturer.startError = .permissionDenied

        await model.start(request([meet]))

        #expect(!persistence.isOpen)
        #expect(persistence.entries.last == .finished(.failed))
    }

    @Test("Finalised speech is written and partial guesses never are")
    func onlyFinalisedSpeechIsWritten() async {
        let (model, _, transcriber, persistence) = await makeMeeting()
        await model.start(request([meet]))

        for text in ["Today", "Today we", "Today we are"] {
            transcriber.emit(.partial(TranscriptSegment(
                text: text,
                startTime: 0,
                endTime: 2,
                state: .partial,
                localeIdentifier: "en-US"
            )))
        }
        transcriber.emit(.final(segment("Today we are learning Swift.")))

        #expect(await wait { persistence.segments.count == 1 })
        #expect(persistence.segments.first?.text == "Today we are learning Swift.")
        #expect(persistence.segments.allSatisfy { $0.state == .final })
    }

    @Test("Each finalised span becomes exactly one durable entry, in order")
    func segmentsAreWrittenOnceAndInOrder() async {
        let (model, _, transcriber, persistence) = await makeMeeting()
        await model.start(request([meet]))

        transcriber.emit(.final(segment("First.", start: 0)))
        transcriber.emit(.final(segment("Second.", start: 4)))
        transcriber.emit(.final(segment("Third.", start: 9)))

        #expect(await wait { persistence.segments.count == 3 })
        #expect(persistence.segments.map(\.text) == ["First.", "Second.", "Third."])
    }

    @Test("Dropped audio is written as a gap where the pipeline says it fell")
    func gapsAreWritten() async {
        let (model, _, transcriber, persistence) = await makeMeeting()
        await model.start(request([meet]))

        transcriber.emit(.interrupted(.audioDropped(seconds: 0.8, startTime: 12.5)))

        #expect(await wait { persistence.gaps.count == 1 })
        #expect(persistence.gaps.first == TranscriptGap(startTime: 12.5, duration: 0.8, reason: .audioDropped))
    }

    @Test("Time lost to a recogniser restart is written as a gap with no invented position")
    func recoveryGapIsWritten() async {
        let (model, _, transcriber, persistence) = await makeMeeting()
        await model.start(request([meet]))

        transcriber.emit(.interrupted(.recognitionFailed(message: "resources")))

        #expect(await wait { persistence.gaps.count == 1 })
        #expect(persistence.gaps.first?.reason == .recognizerRestarted)
        #expect(persistence.gaps.first?.startTime == nil)
    }

    @Test("Stopping flushes and closes the transcript before the meeting is over")
    func stopFlushesBeforeCompleting() async {
        let (model, _, transcriber, persistence) = await makeMeeting()
        await model.start(request([meet]))
        transcriber.emit(.final(segment("Saved.")))
        #expect(await wait { persistence.segments.count == 1 })

        persistence.delayFinish(by: .milliseconds(50))
        await model.stop()

        #expect(!persistence.isOpen)
        #expect(persistence.entries.last == .finished(.completed))
        if case let .saved(layout) = model.persistenceState {
            #expect(layout.transcriptURL.lastPathComponent == "transcript.md")
        } else {
            Issue.record("Expected the transcript to be reported as saved")
        }
    }

    @Test("A span finalised as the meeting stops is not lost in flight")
    func stopWaitsForEventsStillInFlight() async {
        let (model, _, transcriber, persistence) = await makeMeeting()
        await model.start(request([meet]))

        transcriber.emit(.final(segment("The last sentence of the meeting.")))
        await model.stop()

        #expect(persistence.segments.map(\.text) == ["The last sentence of the meeting."])
        #expect(persistence.entries.last == .finished(.completed))
    }

    @Test("A transcript that stops being writable fails the meeting instead of transcribing into nothing")
    func writeFailureStopsTheMeeting() async {
        let (model, capturer, transcriber, persistence) = await makeMeeting()
        await model.start(request([meet]))
        persistence.failAppends(with: TranscriptPersistenceError(.writeFailed))

        transcriber.emit(.final(segment("This will not reach the file.")))

        #expect(await wait { model.persistenceState.failureMessage != nil })
        #expect(await wait { model.captureState == .idle && model.transcriptionState == .idle })
        #expect(!persistence.isOpen)
        #expect(capturer.stopCount == 1)
        #expect(transcriber.stopCount == 1)
        #expect(persistence.segments.isEmpty)
    }

    @Test("A failed transcript is not overwritten with a claim that it was saved")
    func failureSurvivesStop() async {
        let (model, _, transcriber, persistence) = await makeMeeting()
        await model.start(request([meet]))
        persistence.failAppends(with: TranscriptPersistenceError(.writeFailed))
        transcriber.emit(.final(segment("Lost.")))
        #expect(await wait { model.persistenceState.failureMessage != nil })

        await model.stop()

        #expect(model.persistenceState.failureMessage != nil)
    }

    @Test("A transcript that cannot be closed is reported rather than called saved")
    func finishFailureIsReported() async {
        let (model, _, _, persistence) = await makeMeeting()
        await model.start(request([meet]))
        persistence.failFinish(with: TranscriptPersistenceError(.flushFailed))

        await model.stop()

        #expect(model.persistenceState.failureMessage != nil)
    }

    @Test("Capture stopping by itself still closes the transcript")
    func captureInterruptionClosesTheSession() async {
        let (model, capturer, _, persistence) = await makeMeeting()
        await model.start(request([meet]))

        capturer.interrupt(.interrupted("The stream was stopped by the user"))

        #expect(await wait { !persistence.isOpen })
        #expect(persistence.entries.last == .finished(.interrupted))
    }

    @Test("A second meeting writes a new session rather than reopening the last one")
    func restartWritesANewSession() async {
        let (model, _, transcriber, persistence) = await makeMeeting()
        await model.start(request([meet]))
        transcriber.emit(.final(segment("First meeting.")))
        #expect(await wait { persistence.segments.count == 1 })
        await model.stop()

        await model.start(request([meet]))

        #expect(persistence.isOpen)
        #expect(persistence.entries.filter { if case .started = $0 { true } else { false } }.count == 2)
        #expect(persistence.entries.filter { $0 == .finished(.completed) }.count == 1)
    }

    // MARK: - Session record

    @Test("A meeting with nowhere to record its session never reaches capture")
    func aMeetingWithoutASessionRecordDoesNotStart() async {
        let (model, capturer, transcriber, persistence) = await makeMeeting()
        persistence.failStart(with: TranscriptPersistenceError(.recoveryMetadataFailed))

        await model.start(request([meet]))

        #expect(model.persistenceState.failureMessage != nil)
        #expect(model.captureState == .idle)
        #expect(model.transcriptionState == .idle)
        #expect(capturer.startCount == 0)
        #expect(transcriber.startCount == 0)
        #expect(!persistence.isOpen)
    }

    @Test("A meeting ended by a save failure is closed as failed, not as completed")
    func aSaveFailureClosesTheSessionAsFailed() async {
        let (model, _, transcriber, persistence) = await makeMeeting()
        await model.start(request([meet]))
        persistence.failAppends(with: TranscriptPersistenceError(.writeFailed))

        transcriber.emit(.final(segment("This will not reach the file.")))

        #expect(await wait { !persistence.isOpen })
        #expect(persistence.outcomes == [.failed])
    }

    @Test("A meeting stopped by the user is closed as completed")
    func aNormalStopClosesTheSessionAsCompleted() async {
        let (model, _, transcriber, persistence) = await makeMeeting()
        await model.start(request([meet]))
        transcriber.emit(.final(segment("Saved.")))
        #expect(await wait { persistence.segments.count == 1 })

        await model.stop()

        #expect(persistence.outcomes == [.completed])
    }

    @Test("Capture failing by itself closes the session as an interruption, not as a completion")
    func aCaptureFailureClosesAsAnInterruption() async {
        let (model, capturer, _, persistence) = await makeMeeting()
        await model.start(request([meet]))

        capturer.interrupt(.interrupted("The stream was stopped by the user"))

        // The transcript did finish, and that is not the same claim as the
        // meeting having finished: nobody stopped this one.
        #expect(await wait { !persistence.isOpen })
        #expect(persistence.outcomes == [.interrupted])
    }

    // MARK: - Audio retention

    @Test("Keeping no audio opens no recording and writes no buffer")
    func noneModeRetainsNothing() async {
        let (model, capturer, transcriber, persistence, audio) = await makeRetainingMeeting()

        await model.start(request([meet]))
        capturer.deliver(buffer(frames: 960))
        capturer.deliver(buffer(frames: 960))
        transcriber.emit(.final(segment("Transcribed but not recorded.")))
        #expect(await wait { persistence.segments.count == 1 })
        await model.stop()

        #expect(audio.entries == [.started(mode: .none, url: nil)])
        #expect(audio.appendCount == 0)
        #expect(model.audioRetentionState == .idle)
        #expect(persistence.outcomes == [.completed])
    }

    @Test("Retaining audio records every captured buffer to the session's file", arguments: [
        (AudioRetentionMode.raw, "audio.caf"),
        (AudioRetentionMode.compressed, "audio.m4a")
    ])
    func retainingModesRecordCapturedAudio(mode: AudioRetentionMode, name: String) async {
        let (model, capturer, _, _, audio) = await makeRetainingMeeting()

        await model.start(request([meet], retention: mode))
        capturer.deliver(buffer(frames: 960))
        capturer.deliver(buffer(frames: 960))

        #expect(audio.appendCount == 2)
        if case let .retaining(url) = model.audioRetentionState {
            #expect(url.lastPathComponent == name)
        } else {
            Issue.record("Expected the meeting to be recording audio")
        }

        await model.stop()

        #expect(audio.entries.last == .finished)
        if case let .retained(url) = model.audioRetentionState {
            #expect(url.lastPathComponent == name)
        } else {
            Issue.record("Expected the recording to be reported as saved")
        }
    }

    @Test("An audio file that cannot be created stops the meeting before it captures anything")
    func audioStartFailurePreventsStart() async {
        let (model, capturer, transcriber, persistence, audio) = await makeRetainingMeeting()
        audio.failStart()

        await model.start(request([meet], retention: .raw))

        #expect(model.captureState == .idle)
        #expect(model.transcriptionState == .idle)
        #expect(model.audioRetentionState.failureMessage != nil)
        #expect(transcriber.startCount == 0)
        #expect(capturer.startCount == 0)
        #expect(!persistence.isOpen)
        // The transcript was created and is closed again, but the meeting never
        // ran, so nothing records it as completed.
        #expect(persistence.outcomes == [.failed])
    }

    @Test("A session is recorded as completed only after the recording has been closed")
    func completionFollowsTheRecording() async {
        let (model, capturer, _, persistence, audio) = await makeRetainingMeeting()
        let recordingWasClosed = Mutex(false)
        persistence.observeFinish { recordingWasClosed.withLock { $0 = !audio.isOpen } }

        await model.start(request([meet], retention: .raw))
        capturer.deliver(buffer(frames: 960))
        await model.stop()

        #expect(recordingWasClosed.withLock { $0 })
        #expect(audio.entries.last == .finished)
        #expect(persistence.outcomes == [.completed])
    }

    @Test("A recording that cannot be finalised is not a completed meeting")
    func finishFailureIsNotACompletion() async {
        let (model, capturer, transcriber, persistence, audio) = await makeRetainingMeeting()
        await model.start(request([meet], retention: .compressed))
        capturer.deliver(buffer(frames: 960))
        transcriber.emit(.final(segment("This still reaches the transcript.")))
        #expect(await wait { persistence.segments.count == 1 })
        audio.failFinish()

        await model.stop()

        #expect(model.audioRetentionState.failureMessage != nil)
        #expect(model.audioRetentionState.url?.lastPathComponent == "audio.m4a")
        // The transcript finished normally and is reported as such; the session
        // record is what refuses to claim the meeting completed.
        #expect(persistence.segments.count == 1)
        #expect(persistence.outcomes == [.failed])
        if case .saved = model.persistenceState {} else {
            Issue.record("Expected the transcript to be reported as saved")
        }
    }

    @Test("A recording that stops being written ends the meeting rather than losing audio quietly")
    func writeFailureEndsTheMeeting() async {
        let (model, capturer, _, persistence, audio) = await makeRetainingMeeting()
        await model.start(request([meet], retention: .raw))
        capturer.deliver(buffer(frames: 960))

        audio.reportFailure()

        #expect(await wait { !persistence.isOpen })
        #expect(await wait { model.captureState == .idle && model.transcriptionState == .idle })
        #expect(model.audioRetentionState.failureMessage != nil)
        #expect(model.audioRetentionState.url?.lastPathComponent == "audio.caf")
        // The file is closed and left where it is; nothing deletes it.
        #expect(audio.entries.last == .cancelled)
        #expect(persistence.outcomes == [.failed])
    }

    @Test("A transcript that stops being saved still closes the recording rather than discarding it")
    func transcriptFailureKeepsTheRecording() async {
        let (model, capturer, transcriber, persistence, audio) = await makeRetainingMeeting()
        await model.start(request([meet], retention: .raw))
        capturer.deliver(buffer(frames: 960))
        persistence.failAppends(with: TranscriptPersistenceError(.writeFailed))

        transcriber.emit(.final(segment("This will not reach the file.")))

        #expect(await wait { model.persistenceState.failureMessage != nil })
        #expect(await wait { audio.entries.last == .finished })
        #expect(persistence.outcomes == [.failed])
        if case .retained = model.audioRetentionState {} else {
            Issue.record("Expected the recording to be closed rather than abandoned")
        }
    }

    @Test("Enabling audio retention does not change a word of the transcript")
    func retentionDoesNotChangeTheTranscript() async {
        let spoken = ["Today we are learning about closures.", "A closure captures its environment."]

        var written: [[String]] = []
        for mode in [AudioRetentionMode.none, .raw, .compressed] {
            let (model, capturer, transcriber, persistence, _) = await makeRetainingMeeting()
            await model.start(request([meet], retention: mode))
            capturer.deliver(buffer(frames: 960))
            for (index, text) in spoken.enumerated() {
                transcriber.emit(.final(segment(text, start: Double(index) * 2)))
            }
            #expect(await wait { persistence.segments.count == spoken.count })
            await model.stop()
            written.append(persistence.segments.map(\.text))
        }

        #expect(written == [spoken, spoken, spoken])
    }

    @Test("A second meeting records into its own session directory")
    func restartRecordsIntoANewSession() async {
        let (model, capturer, _, _, audio) = await makeRetainingMeeting()

        await model.start(request([meet], title: "First Meeting", retention: .raw))
        capturer.deliver(buffer(frames: 960))
        await model.stop()
        await model.start(request([browser], title: "Second Meeting", retention: .raw))
        capturer.deliver(buffer(frames: 960))
        await model.stop()

        let started: [URL] = audio.entries.compactMap {
            if case let .started(_, url) = $0 { url } else { nil }
        }
        #expect(started.count == 2)
        #expect(started[0] != started[1])
        #expect(started.allSatisfy { $0.lastPathComponent == "audio.caf" })
    }

    @Test("Capture stopping by itself still closes the recording before the session is recorded")
    func captureInterruptionClosesTheRecording() async {
        let (model, capturer, _, persistence, audio) = await makeRetainingMeeting()
        await model.start(request([meet], retention: .compressed))
        capturer.deliver(buffer(frames: 960))

        capturer.interrupt(.interrupted("The stream was stopped by the user"))

        #expect(await wait { !persistence.isOpen })
        #expect(audio.entries.last == .finished)
        #expect(persistence.outcomes == [.interrupted])
    }
}
