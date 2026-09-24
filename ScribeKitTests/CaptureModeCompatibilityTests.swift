//
//  CaptureModeCompatibilityTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// The capture mode as it is written down, and as earlier builds wrote nothing
/// about it: the session record, the transcript header, and the words the menu
/// bar uses for each kind of meeting.
@Suite("Capture mode, persisted and presented")
struct CaptureModeCompatibilityTests {

    private let sessionID = UUID(uuidString: "0E6C21B4-7A38-4F1E-9D2A-3C5B8F10A7D4")!
    private let startedAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func record(_ mode: CaptureMode?) -> SessionRecoveryMetadata {
        SessionRecoveryMetadata(
            sessionID: sessionID,
            title: "Thinking Aloud",
            startedAt: startedAt,
            sourceNames: ["Microphone (Studio Mic)"],
            localeIdentifier: "en-US",
            captureMode: mode,
            audioRetention: AudioRetentionMode.none,
            status: .inProgress
        )
    }

    @Test("The record states its capture mode and reads it back")
    func recordRoundTrips() throws {
        let microphone = record(.microphone)
        let text = try String(decoding: microphone.encoded(), as: UTF8.self)
        #expect(text.contains("\"captureMode\" : \"microphone\""))
        #expect(try SessionRecoveryMetadata.decoded(from: microphone.encoded()) == microphone)

        let applications = record(.applications)
        #expect(try String(decoding: applications.encoded(), as: UTF8.self)
            .contains("\"captureMode\" : \"applications\""))
    }

    @Test("A record with no capture mode writes no key, as records before it did")
    func absentModeWritesNothing() throws {
        let text = try String(decoding: record(nil).encoded(), as: UTF8.self)
        #expect(!text.contains("captureMode"))
    }

    @Test("Every change the lifecycle makes to a record keeps its capture mode")
    func lifecycleKeepsTheMode() {
        let open = record(.microphone)
        #expect(open.pausing(at: startedAt, capturedDuration: 10).captureMode == .microphone)
        #expect(open.notingOpenGap(startedAt: startedAt).captureMode == .microphone)
        #expect(open.closed(.completed, at: startedAt, capturedDuration: 60).captureMode == .microphone)
        #expect(open.closed(.interrupted, at: startedAt).captureMode == .microphone)
        #expect(open.markingInterruption(recordedAt: startedAt).captureMode == .microphone)
    }

    @Test("A v0.1.0 session record, which predates capture modes, still decodes unchanged")
    func releasedRecordsStillDecode() throws {
        // Every field a 0.1.0 build wrote for a finished App Audio meeting.
        let json = """
            {
              "audioRetention" : "compressed",
              "audioPath" : "audio.m4a",
              "capturedDuration" : 1843.2,
              "endedAt" : "2026-09-10T15:31:00Z",
              "localeIdentifier" : "en-US",
              "schemaVersion" : 1,
              "sessionID" : "\(sessionID.uuidString)",
              "sourceNames" : ["QuickTime Player", "Safari"],
              "startedAt" : "2026-09-10T15:00:00Z",
              "status" : "completed",
              "title" : "Design Review",
              "transcriptPath" : "transcript.md"
            }
            """
        let decoded = try SessionRecoveryMetadata.decoded(from: Data(json.utf8))
        #expect(decoded.captureMode == nil)
        #expect(decoded.sourceNames == ["QuickTime Player", "Safari"])
        #expect(decoded.status == .completed)
        #expect(decoded.audioRetention == .compressed)
    }

    @Test("A Microphone transcript's header is read back like any other")
    func microphoneTranscriptParses() {
        let markdown = """
            # Thinking Aloud

            **Date:** 2026-09-24
            **Started:** 9:15 AM
            **Sources:** Microphone (Studio Mic)
            **Language:** en-US
            **Captured by:** ScribeKit

            ## Transcript

            ### 9:15 AM

            **9:15:02 AM**

            The quick brown fox jumps over the lazy dog.

            """
        let document = TranscriptDocument.parse(markdown)
        #expect(document.isScribeKitTranscript)
        #expect(document.title == "Thinking Aloud")
        #expect(document.sourceNames == ["Microphone (Studio Mic)"])
        #expect(document.spans.map(\.text) == ["The quick brown fox jumps over the lazy dog."])
    }

    @Test("The formatter writes the microphone into the header exactly as it names it")
    func formatterHeader() {
        let formatter = TranscriptMarkdownFormatter(
            startedAt: startedAt,
            timeZone: TimeZone(identifier: "UTC")!
        )
        let microphone = CaptureSource.microphone(MicrophoneInput(id: "DeviceUID-4417", name: "Studio Mic"))
        let header = formatter.header(
            title: "Thinking Aloud",
            sourceNames: [microphone.transcriptName],
            localeIdentifier: "en-US"
        )
        #expect(header.contains("**Sources:** Microphone (Studio Mic)\n"))
        #expect(!header.contains("DeviceUID-4417"), "the device identifier stays out of the document")
    }
}

/// What the menu bar says a meeting is doing, for each capture mode.
@MainActor
@Suite("Menu bar, by capture mode")
struct MeetingMenuBarCaptureModeTests {

    private func snapshot(_ sources: [CaptureSource]) -> MeetingSnapshot {
        MeetingSnapshot(
            session: MeetingSession(
                title: "Thinking Aloud",
                selectedSources: sources,
                destination: URL(filePath: "/tmp/scribekit-tests", directoryHint: .isDirectory)
            ),
            localeIdentifier: "en-US"
        )
    }

    @Test("A Microphone meeting is listened to, not captured, and says so when paused")
    func microphoneWording() {
        let meeting = snapshot([.microphone(MicrophoneInput(id: "id", name: "Studio Mic"))])
        let running = MeetingMenuBarPresentation(
            status: .transcribing, meeting: meeting, transcript: nil, audio: nil, canStop: true
        )
        #expect(running.details.first == "Listening to Microphone (Studio Mic)")

        let paused = MeetingMenuBarPresentation(
            status: .paused, meeting: meeting, transcript: nil, audio: nil, canStop: true
        )
        #expect(paused.details.first == "Paused; not listening to Microphone (Studio Mic)")
    }

    @Test("An App Audio meeting keeps the words it had")
    func applicationWordingUnchanged() {
        let meeting = snapshot([.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")])
        let running = MeetingMenuBarPresentation(
            status: .transcribing, meeting: meeting, transcript: nil, audio: nil, canStop: true
        )
        #expect(running.details.first == "Capturing Meet")
    }
}
