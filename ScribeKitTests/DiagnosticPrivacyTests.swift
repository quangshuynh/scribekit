//
//  DiagnosticPrivacyTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// The tests that decide whether ScribeKit can be supported without being
/// trusted.
///
/// A meeting is run with deliberately identifiable material in every field a
/// report could reach — the title, the transcript, the applications, the
/// folder, the sentences the readiness rows show — and the exported bytes are
/// searched for it. A future field that carries any of it fails here rather
/// than on somebody's Mac.
@MainActor
struct DiagnosticPrivacyTests {

    private static let transcriptCanary = "SECRET_TRANSCRIPT_CANARY"
    private static let partialCanary = "SECRET_PARTIAL_CANARY"
    private static let titleCanary = "SECRET_MEETING_TITLE_CANARY"
    private static let noteCanary = "SECRET_NOTE_CANARY"
    private static let applicationCanary = "SECRET_APP_CANARY"
    private static let folderCanary = "/Users/secret-user/PrivateMeetings"

    /// Every string the report must not contain.
    private static let canaries = [
        transcriptCanary, partialCanary, titleCanary, noteCanary,
        applicationCanary, folderCanary, "secret-user", "PrivateMeetings"
    ]

    /// A setup state whose every human-readable field is a canary.
    private func poisonedSetup() -> MeetingDiagnostics.SetupState {
        let saveLocation = SaveLocationReadiness.readyNotRemembered(
            path: Self.folderCanary,
            message: "Meetings are saved to \(Self.folderCanary). \(Self.noteCanary)"
        )
        let sources = CaptureSourceReadiness.discovered(
            available: 3,
            selected: 1,
            droppedSelections: [Self.applicationCanary]
        )
        let recovery = SessionRecoveryReport(
            candidates: [],
            problems: [
                SessionRecoveryProblem(
                    directory: URL(filePath: "\(Self.folderCanary)/\(Self.titleCanary)"),
                    error: .metadataMalformed
                )
            ]
        )
        return MeetingDiagnostics.SetupState(
            readiness: MeetingStartReadiness(
                saveLocation: saveLocation,
                captureSources: sources,
                speech: .available(localeIdentifier: "en-US"),
                meetingIsActive: true
            ),
            saveLocation: saveLocation,
            sources: sources,
            recovery: .found(recovery)
        )
    }

    /// Runs a meeting whose every field is a canary, and returns the report it
    /// would export.
    ///
    /// - Parameter stopping: Whether to end the meeting before reporting.
    /// - Returns: The encoded report, as text to search.
    private func poisonedReport(stopping: Bool) async throws -> String {
        let harness = ReliabilityHarness()
        let source = CaptureSource.application(
            bundleIdentifier: Self.applicationCanary,
            displayName: Self.applicationCanary
        )
        await harness.runtime.prepare()
        await harness.runtime.start(MeetingStartRequest(
            title: Self.titleCanary,
            sources: [source],
            destination: URL(filePath: Self.folderCanary, directoryHint: .isDirectory),
            audioRetention: .compressed
        ))
        harness.deliver(seconds: 1, count: 5)
        harness.transcriber.emit(.partial(TranscriptSegment(
            text: Self.partialCanary,
            startTime: 0,
            endTime: 1,
            state: .partial,
            localeIdentifier: "en-US"
        )))
        harness.emitFinal(Self.transcriptCanary)
        _ = await harness.wait { harness.runtime.transcriptSpanCount == 1 }
        if stopping { await harness.stop() }

        let diagnostics = MeetingDiagnostics(
            runtime: harness.runtime,
            writer: DiagnosticReportWriter(store: { _, _ in })
        )
        diagnostics.publish(poisonedSetup())
        return try String(decoding: diagnostics.makeReport().encoded(), as: UTF8.self)
    }

    @Test("A report of a running meeting carries none of its content")
    func activeMeetingReportIsClean() async throws {
        let json = try await poisonedReport(stopping: false)
        for canary in Self.canaries {
            #expect(!json.contains(canary), "the report leaked \(canary)")
        }
    }

    @Test("A report of a finished meeting carries none of its content either")
    func endedMeetingReportIsClean() async throws {
        let json = try await poisonedReport(stopping: true)
        for canary in Self.canaries {
            #expect(!json.contains(canary), "the report leaked \(canary)")
        }
    }

    @Test("No absolute path reaches a report")
    func noAbsolutePaths() async throws {
        let json = try await poisonedReport(stopping: true)
        #expect(!json.contains("/Users"))
        #expect(!json.contains("file://"))
        #expect(!json.contains(NSHomeDirectory()))
        #expect(!json.contains(NSUserName()))
    }

    @Test("A report's fields are the ones that were reviewed")
    func reportCarriesOnlyReviewedFields() async throws {
        let json = try await poisonedReport(stopping: true)
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        #expect(object.keys.sorted() == [
            "application", "generatedAt", "lastOutcome", "readiness", "recovery",
            "runtime", "schemaVersion", "session", "storage", "system"
        ])

        let session = try #require(object["session"] as? [String: Any])
        #expect(session.keys.sorted() == [
            "capturedChannelCount", "capturedDurationSeconds", "capturedSampleRate",
            "gapCount", "pauseCount", "phase", "recognitionLocaleIdentifier",
            "recognitionRestartCount", "recordingPresent", "retentionMode",
            "selectedSourceCount", "startedAt", "transcriptSpanCount",
            "untranscribedSeconds", "wallDurationSeconds"
        ])

        let readiness = try #require(object["readiness"] as? [String: Any])
        let prerequisites = try #require(readiness["prerequisites"] as? [[String: Any]])
        // The rows the screen shows carry a `detail` sentence naming the
        // folder and the applications. It is not carried here, and a future
        // field that reinstated it would fail this.
        for row in prerequisites {
            #expect(row.keys.sorted() == ["name", "status"])
        }
    }

    @Test("A meeting title is left out even when it is the only thing named")
    func titleIsNeverReported() async throws {
        let json = try await poisonedReport(stopping: true)
        #expect(!json.lowercased().contains("\"title\""))
        #expect(!json.contains(MeetingSession.untitledPlaceholder))
    }

    @Test("Recognised speech does not reach the summary through its counts")
    func transcriptIsCountedNotQuoted() async throws {
        let harness = ReliabilityHarness()
        await harness.start()
        harness.deliver(seconds: 1, count: 2)
        harness.emitFinal(Self.transcriptCanary)
        harness.emitFinal(Self.transcriptCanary)
        _ = await harness.wait { harness.runtime.transcriptSpanCount == 2 }

        let report = DiagnosticReport.make(runtime: harness.runtime, setup: nil)
        #expect(report.session?.transcriptSpanCount == 2)
        let json = try String(decoding: report.encoded(), as: UTF8.self)
        #expect(!json.contains(Self.transcriptCanary))
    }
}
