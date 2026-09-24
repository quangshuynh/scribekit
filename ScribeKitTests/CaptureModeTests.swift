//
//  CaptureModeTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// Which capture mode a selection describes, and the rules that keep a
/// meeting to exactly one of them.
@MainActor
@Suite("Capture mode")
struct CaptureModeTests {

    private let meet = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")
    private let browser = CaptureSource.application(bundleIdentifier: "com.example.Browser", displayName: "Browser")
    private let microphone = CaptureSource.microphone(MicrophoneInput(id: "AppleUSBAudioEngine:1", name: "Studio Mic"))
    private let destination = URL(filePath: "/tmp/scribekit-tests", directoryHint: .isDirectory)

    private func request(
        _ sources: [CaptureSource],
        retention: AudioRetentionMode = .none
    ) -> MeetingStartRequest {
        MeetingStartRequest(title: "Standup", sources: sources, destination: destination, audioRetention: retention)
    }

    @Test("Applications alone are App Audio, and one microphone alone is Microphone")
    func modeFromSources() {
        #expect(CaptureMode(sources: [meet, browser]) == .applications)
        #expect(CaptureMode(sources: [microphone]) == .microphone)
        #expect(CaptureMode(sources: []) == .applications, "nothing selected is still application capture")
    }

    @Test("A selection mixing applications and the microphone describes no mode")
    func mixtureIsNoMode() {
        #expect(CaptureMode(sources: [meet, microphone]) == nil)
        #expect(CaptureMode(sources: [microphone, microphone]) == nil)
    }

    @Test("A request is refused for its shape before anything is created")
    func requestRefusals() {
        #expect(request([]).refusal == .noSourcesSelected)
        #expect(request([meet, microphone]).refusal == .mixedCaptureModes)
        #expect(request([microphone], retention: .raw).refusal == .microphoneAudioNotRetained)
        #expect(request([microphone], retention: .compressed).refusal == .microphoneAudioNotRetained)
        #expect(request([microphone]).refusal == nil)
        #expect(request([meet], retention: .raw).refusal == nil, "App Audio may keep audio as before")
    }

    @Test("The capture configuration carries the mode and the microphone's identity")
    func configurationFromSources() {
        let mic = AudioCaptureConfiguration(sources: [microphone])
        #expect(mic.mode == .microphone)
        #expect(mic.sourceIDs == ["AppleUSBAudioEngine:1"])

        let apps = AudioCaptureConfiguration(sources: [meet, browser])
        #expect(apps.mode == .applications)
        #expect(apps.sourceIDs == ["com.example.Meet", "com.example.Browser"])
        #expect(AudioCaptureConfiguration(sourceIDs: ["com.example.Meet"]).mode == .applications)
    }

    @Test("A microphone is named as one in the transcript; an application as itself")
    func transcriptNames() {
        #expect(microphone.transcriptName == "Microphone (Studio Mic)")
        #expect(meet.transcriptName == "Meet")
    }

    @Test("A snapshot knows which mode its meeting is in and names the microphone as one")
    func snapshotMode() {
        let snapshot = MeetingSnapshot(
            session: request([microphone]).makeSession(createdAt: Date(timeIntervalSince1970: 0)),
            localeIdentifier: "en-US"
        )
        #expect(snapshot.captureMode == .microphone)
        #expect(snapshot.sourceSummary == "Microphone (Studio Mic)")

        let apps = MeetingSnapshot(
            session: request([meet]).makeSession(createdAt: Date(timeIntervalSince1970: 0)),
            localeIdentifier: "en-US"
        )
        #expect(apps.captureMode == .applications)
        #expect(apps.sourceSummary == "Meet")
    }

    @Test("Each new capture error names what to do, and is classified for diagnostics")
    func errorsAreDescribedAndClassified() {
        let denied = AudioCaptureError.microphoneAccessDenied
        #expect(denied.errorDescription?.contains("Privacy & Security › Microphone") == true)
        #expect(AudioCaptureError.microphoneAccessRestricted.errorDescription?.contains("restricted") == true)
        let changed = AudioCaptureError.microphoneInputChanged.errorDescription
        #expect(changed?.contains("System Settings › Sound") == true)

        #expect(DiagnosticCategory(AudioCaptureError.microphoneAccessDenied) == .microphoneAccess)
        #expect(DiagnosticCategory(AudioCaptureError.microphoneAccessRestricted) == .microphoneAccess)
        #expect(DiagnosticCategory(AudioCaptureError.microphoneUnavailable) == .captureDiscovery)
        #expect(DiagnosticCategory(AudioCaptureError.microphoneInputChanged) == .captureDiscovery)
        #expect(DiagnosticCategory(AudioCaptureError.mixedCaptureModes) == .captureStart)
        // Screen recording refusals keep their own category.
        #expect(DiagnosticCategory(AudioCaptureError.permissionDenied) == .captureAccess)
    }

    @Test("The remembered capture mode round-trips and defaults to App Audio")
    func preferenceRoundTrip() throws {
        let suite = "CaptureModeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = UserDefaultsMeetingSetupPreferences(defaults: defaults)
        #expect(preferences.captureMode == .applications)
        preferences.captureMode = .microphone
        #expect(UserDefaultsMeetingSetupPreferences(defaults: defaults).captureMode == .microphone)
        defaults.set("both", forKey: "com.scribekit.meetingSetup.captureMode")
        #expect(preferences.captureMode == .applications, "an unreadable value is not a mode")
    }
}
