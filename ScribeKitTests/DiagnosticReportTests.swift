//
//  DiagnosticReportTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// What a diagnostic report says about a Mac, and what it refuses to say.
///
/// The report is a support artifact, so these are tests about a published
/// format: that it is versioned, that two reports of the same state are the
/// same bytes, and that each reachable meeting state is described by a stable
/// name rather than by a sentence somebody might reword.
@MainActor
struct DiagnosticReportTests {

    /// A readiness state with everything satisfied, built from values that
    /// carry a path and an application name so that dropping them is visible.
    private func satisfiedSetup(
        path: String = "/Users/example/Meetings",
        droppedNames: [String] = []
    ) -> MeetingDiagnostics.SetupState {
        let saveLocation = SaveLocationReadiness.ready(path: path)
        let sources = CaptureSourceReadiness.discovered(
            available: 4,
            selected: 1,
            droppedSelections: droppedNames
        )
        return MeetingDiagnostics.SetupState(
            readiness: MeetingStartReadiness(
                saveLocation: saveLocation,
                captureSources: sources,
                speech: .available(localeIdentifier: "en-US"),
                meetingIsActive: false
            ),
            saveLocation: saveLocation,
            sources: sources,
            recovery: .clear
        )
    }

    @Test("A report states the schema it was written to")
    func reportIsVersioned() async throws {
        let harness = ReliabilityHarness()
        let report = DiagnosticReport.make(runtime: harness.runtime, setup: satisfiedSetup())
        #expect(report.schemaVersion == DiagnosticReport.currentSchemaVersion)
        let json = try String(decoding: report.encoded(), as: UTF8.self)
        #expect(json.contains("\"schemaVersion\" : 1"))
    }

    @Test("Two reports of the same state are the same bytes")
    func encodingIsDeterministic() async throws {
        let harness = ReliabilityHarness()
        let moment = Date(timeIntervalSinceReferenceDate: 12_345)
        let setup = satisfiedSetup()
        let first = DiagnosticReport.make(
            runtime: harness.runtime, setup: setup, generatedAt: moment
        )
        let second = DiagnosticReport.make(
            runtime: harness.runtime, setup: setup, generatedAt: moment
        )
        #expect(try first.encoded() == second.encoded())
    }

    @Test("Timestamps are written in one machine-readable form")
    func timestampsAreStable() async throws {
        let harness = ReliabilityHarness()
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        let report = DiagnosticReport.make(
            runtime: harness.runtime, setup: satisfiedSetup(), generatedAt: moment
        )
        let json = try String(decoding: report.encoded(), as: UTF8.self)
        #expect(json.contains("\"generatedAt\" : \"2023-11-14T22:13:20Z\""))
    }

    @Test("A report is useful before anything has run")
    func reportWithNoMeeting() async throws {
        let harness = ReliabilityHarness()
        let report = DiagnosticReport.make(runtime: harness.runtime, setup: satisfiedSetup())
        #expect(report.session == nil)
        #expect(report.lastOutcome == nil)
        #expect(report.runtime.status == "idle")
        #expect(report.runtime.isRunning == false)
        #expect(report.readiness?.canStart == true)
        #expect(report.storage?.saveLocationResolved == true)
        #expect(report.recovery.sessionMetadataSchemaVersion
            == SessionRecoveryMetadata.currentSchemaVersion)
    }

    @Test("A window that never opened is not reported as an unready one")
    func setupThatWasNeverShownIsAbsentRatherThanBlank() async throws {
        let harness = ReliabilityHarness()
        let report = DiagnosticReport.make(runtime: harness.runtime, setup: nil)
        #expect(report.readiness == nil)
        #expect(report.storage == nil)
        #expect(report.recovery.scanned == false)
    }

    @Test("A running meeting is described by its counts")
    func activeMeetingIsSummarised() async throws {
        let harness = ReliabilityHarness()
        await harness.start(retention: .compressed)
        harness.deliver(seconds: 1, count: 30)
        harness.emitFinal("hello")
        _ = await harness.wait { harness.runtime.transcriptSpanCount == 1 }

        let report = DiagnosticReport.make(runtime: harness.runtime, setup: satisfiedSetup())
        let session = try #require(report.session)
        #expect(session.phase == "active")
        #expect(session.retentionMode == "compressed")
        #expect(session.recognitionLocaleIdentifier == "en-US")
        #expect(session.selectedSourceCount == 1)
        #expect(session.capturedDurationSeconds == 30)
        #expect(session.transcriptSpanCount == 1)
        #expect(session.pauseCount == 0)
        #expect(session.recordingPresent)
        #expect(session.capturedSampleRate == 48_000)
        #expect(session.capturedChannelCount == 1)
        #expect(report.runtime.status == "transcribing")
    }

    @Test("A paused meeting states that it is paused, and how often")
    func pausedMeetingIsSummarised() async throws {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 10)
        await harness.pause()

        let report = DiagnosticReport.make(runtime: harness.runtime, setup: satisfiedSetup())
        #expect(report.runtime.status == "paused")
        #expect(report.session?.pauseCount == 1)
        #expect(report.session?.capturedDurationSeconds == 10)
    }

    @Test("A meeting the user stopped is reported as completed")
    func completedMeetingIsSummarised() async throws {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 5)
        await harness.stop()

        let report = DiagnosticReport.make(runtime: harness.runtime, setup: satisfiedSetup())
        #expect(report.session?.phase == "ended")
        #expect(report.lastOutcome?.category == "completed")
        #expect(report.lastOutcome?.diagnosticCategory == nil)
        #expect(report.lastOutcome?.capturedAudio == true)
    }

    @Test("A meeting whose capture died is reported as interrupted")
    func interruptedMeetingIsSummarised() async throws {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 3)
        harness.capturer.interrupt(.interrupted("stream ended"))
        _ = await harness.wait { harness.runtime.lastCompletion != nil }

        let report = DiagnosticReport.make(runtime: harness.runtime, setup: satisfiedSetup())
        #expect(report.lastOutcome?.category == "interrupted")
        #expect(report.lastOutcome?.diagnosticCategory == .captureInterrupted)
    }

    @Test("A meeting whose transcript stopped being written is reported as one")
    func failedMeetingIsSummarised() async throws {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 2)
        harness.persistence.failAppends(with: TranscriptPersistenceError(.writeFailed))
        harness.emitFinal("anything")
        _ = await harness.wait { harness.runtime.lastCompletion != nil }

        let report = DiagnosticReport.make(runtime: harness.runtime, setup: satisfiedSetup())
        #expect(report.lastOutcome?.category == "transcriptFailure")
        #expect(report.lastOutcome?.diagnosticCategory == .transcriptPersistence)
        #expect(report.runtime.transcript == "failed")
    }

    @Test("A meeting keeping no audio says so, and opens no recording")
    func retentionOffIsReported() async throws {
        let harness = ReliabilityHarness()
        await harness.start(retention: .none)
        harness.deliver()

        let report = DiagnosticReport.make(runtime: harness.runtime, setup: satisfiedSetup())
        #expect(report.session?.retentionMode == "none")
        #expect(report.session?.recordingPresent == false)
        #expect(report.runtime.audio == "idle")
    }

    @Test("A meeting keeping raw audio says which mode it is in")
    func rawRetentionIsReported() async throws {
        let harness = ReliabilityHarness()
        await harness.start(retention: .raw)
        harness.deliver()

        let report = DiagnosticReport.make(runtime: harness.runtime, setup: satisfiedSetup())
        #expect(report.session?.retentionMode == "raw")
        #expect(report.session?.recordingPresent == true)
    }

    @Test("An unready prerequisite is named without its explanation")
    func unavailableReadinessIsReported() async throws {
        let saveLocation = SaveLocationReadiness.unusable(
            message: "The folder at /Users/example/Meetings is no longer available."
        )
        let sources = CaptureSourceReadiness.accessUnavailable(
            message: "ScribeKit has no Screen & System Audio Recording access."
        )
        let readiness = MeetingStartReadiness(
            saveLocation: saveLocation,
            captureSources: sources,
            speech: .modelNotInstalled(localeIdentifier: "en-US"),
            meetingIsActive: false
        )
        let section = DiagnosticReport.Readiness(readiness, sources: sources)
        #expect(section.canStart == false)
        #expect(section.blocker == "saveLocation")
        #expect(section.prerequisites.map(\.name)
            == ["saveLocation", "captureAccess", "speechRecognition", "captureSource"])
        #expect(section.prerequisites.first?.status == "blocked")
        #expect(section.discoveredSourceCount == nil)

        let storage = DiagnosticReport.Storage(saveLocation: saveLocation, sources: sources)
        #expect(storage.saveLocationChosen)
        #expect(storage.saveLocationResolved == false)
        #expect(storage.captureAccessAvailable == false)
    }

    @Test("A folder chosen but not remembered is distinguished from one that is")
    func saveLocationStandingIsReported() {
        let remembered = DiagnosticReport.Storage(
            saveLocation: .ready(path: "/Users/example/Meetings"),
            sources: .notAttempted
        )
        #expect(remembered.saveLocationRemembered)
        #expect(remembered.captureAccessAvailable == nil)

        let notRemembered = DiagnosticReport.Storage(
            saveLocation: .readyNotRemembered(
                path: "/Users/example/Meetings",
                message: "This choice will not survive a relaunch."
            ),
            sources: .noApplicationsFound
        )
        #expect(notRemembered.saveLocationChosen)
        #expect(notRemembered.saveLocationResolved)
        #expect(notRemembered.saveLocationRemembered == false)
        #expect(notRemembered.captureAccessAvailable == true)

        let none = DiagnosticReport.Storage(saveLocation: .notChosen, sources: .discovering)
        #expect(none.saveLocationChosen == false)
    }

    @Test("A session record this build cannot read is counted and named")
    func recoveryProblemsAreNamed() {
        let directory = URL(filePath: "/Users/example/Meetings/2026-08-31 Standup")
        let report = SessionRecoveryReport(
            candidates: [],
            problems: [
                SessionRecoveryProblem(directory: directory, error: .metadataMalformed),
                SessionRecoveryProblem(directory: directory, error: .unsupportedSchemaVersion(9)),
                SessionRecoveryProblem(directory: directory, error: .metadataMalformed)
            ]
        )
        let section = DiagnosticReport.Recovery(.found(report))
        #expect(section.scanned)
        #expect(section.unfinishedSessionCount == 0)
        #expect(section.unreadableSessionCount == 3)
        #expect(section.problems == ["metadataMalformed", "unsupportedSchemaVersion"])
    }

    @Test("A scan that has not run is not a scan that found nothing")
    func recoveryBeforeScanning() {
        #expect(DiagnosticReport.Recovery(.unchecked).scanned == false)
        #expect(DiagnosticReport.Recovery(.checking).scanned == false)
        #expect(DiagnosticReport.Recovery(.clear).scanned)
    }
}

/// The mapping from ScribeKit's own errors to the names a support conversation
/// uses.
struct DiagnosticCategoryTests {

    @Test("Each reachable subsystem failure has a stable support name")
    func categoriesCoverReachableFailures() {
        #expect(DiagnosticCategory(AudioCaptureError.permissionDenied) == .captureAccess)
        #expect(DiagnosticCategory(AudioCaptureError.sourcesUnavailable(["a"])) == .captureDiscovery)
        #expect(DiagnosticCategory(AudioCaptureError.systemFailure("x")) == .captureStart)
        #expect(DiagnosticCategory(AudioCaptureError.interrupted("x")) == .captureInterrupted)
        #expect(DiagnosticCategory(TranscriptionError.unavailable(.unsupportedSystem))
            == .recognitionAvailability)
        #expect(DiagnosticCategory(TranscriptionError.systemFailure("x")) == .recognitionStart)
        #expect(DiagnosticCategory(TranscriptPersistenceError(.accessDenied)) == .saveLocation)
        #expect(DiagnosticCategory(TranscriptPersistenceError(.writeFailed)) == .transcriptPersistence)
        #expect(DiagnosticCategory(TranscriptPersistenceError(.recoveryMetadataFailed))
            == .sessionMetadata)
        #expect(DiagnosticCategory(AudioRetentionError(.audioWriteFailed)) == .audioPersistence)
        #expect(DiagnosticCategory(SessionRecoveryError.metadataMalformed) == .recoveryMetadata)
    }

    @Test("An error from outside ScribeKit is not given a name it does not have")
    func unknownErrorsAreUnclassified() {
        struct Anything: Error {}
        #expect(DiagnosticCategory(Anything()) == nil)
    }

    @Test("A finished meeting has no failure category")
    func completedOutcomeHasNoCategory() {
        #expect(DiagnosticCategory(outcome: .completed) == nil)
        #expect(DiagnosticCategory(outcome: .recognitionFailure) == .recognitionRestartExhausted)
        #expect(DiagnosticCategory(outcome: .startFailure) == .captureStart)
    }
}

/// Removing paths from text ScribeKit did not write.
struct DiagnosticSanitizationTests {

    @Test("A quoted file is removed rather than reported")
    func pathsAreRemoved() {
        let sanitized = DiagnosticSafety.sanitized(
            "Could not write /Users/secret-user/PrivateMeetings/transcript.md today"
        )
        #expect(!sanitized.contains("secret-user"))
        #expect(!sanitized.contains("PrivateMeetings"))
        #expect(sanitized.contains("<path>"))
        #expect(sanitized.contains("Could not write"))
    }

    @Test("A URL and a tilde path are removed too")
    func urlsAndHomePathsAreRemoved() {
        #expect(!DiagnosticSafety.sanitized("open file:///Users/secret-user/a.m4a failed")
            .contains("secret-user"))
        #expect(!DiagnosticSafety.sanitized("in ~/Documents/Meetings").contains("Documents"))
    }

    @Test("Text with no path is left alone")
    func ordinaryTextSurvives() {
        #expect(DiagnosticSafety.sanitized("The operation could not be completed.")
            == "The operation could not be completed.")
    }
}
