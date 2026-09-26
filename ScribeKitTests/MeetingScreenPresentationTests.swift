//
//  MeetingScreenPresentationTests.swift
//  ScribeKitTests
//

import AppKit
import Testing
@testable import ScribeKit

/// Which arrangement the Meeting screen shows.
@Suite("Meeting screen layout")
struct MeetingScreenLayoutTests {

    @Test("A meeting that is starting, running, paused or stopping is shown as a session")
    func runningIsSession() {
        #expect(MeetingScreenLayout(isRunning: true, outcome: nil) == .session)
        #expect(MeetingScreenLayout(isRunning: true, outcome: .startFailure) == .session)
    }

    @Test("With nothing running and nothing ended, the setup form is shown")
    func idleIsSetup() {
        #expect(MeetingScreenLayout(isRunning: false, outcome: nil) == .setup)
    }

    @Test("A meeting that never started is reported on the setup form, where it can be corrected")
    func startFailureIsSetup() {
        #expect(MeetingScreenLayout(isRunning: false, outcome: .startFailure) == .setup)
    }

    @Test("A meeting that ended after capturing something stays on screen with its transcript")
    func endedIsSession() {
        let categories: [MeetingOutcomePresentation.Category] = [
            .completed, .interrupted, .transcriptFailure, .audioFailure, .recognitionFailure
        ]
        for category in categories {
            #expect(MeetingScreenLayout(isRunning: false, outcome: category) == .session, "\(category)")
        }
    }
}

/// The status line at the top of a meeting.
@Suite("Meeting session status")
struct MeetingSessionStatusTests {

    /// One status line for each thing a meeting can be doing.
    static let everyStatus: [MeetingSessionStatus] = [
        MeetingSessionStatus(status: .preparing, isRecovering: false, captureMode: .microphone, outcome: nil),
        MeetingSessionStatus(status: .transcribing, isRecovering: false, captureMode: .microphone, outcome: nil),
        MeetingSessionStatus(status: .transcribing, isRecovering: true, captureMode: .microphone, outcome: nil),
        MeetingSessionStatus(status: .paused, isRecovering: false, captureMode: .microphone, outcome: nil),
        MeetingSessionStatus(status: .stopping, isRecovering: false, captureMode: .microphone, outcome: nil),
        MeetingSessionStatus(status: .completed, isRecovering: false, captureMode: .microphone, outcome: .completed),
        MeetingSessionStatus(status: .idle, isRecovering: false, captureMode: .microphone, outcome: .interrupted),
        MeetingSessionStatus(status: .failed(message: "x"), isRecovering: false, captureMode: .microphone,
                             outcome: .transcriptFailure)
    ]

    @Test("A running Microphone meeting is Listening; an App Audio one is Capturing; both are live")
    func liveWording() {
        let microphone = MeetingSessionStatus(status: .transcribing, isRecovering: false,
                                              captureMode: .microphone, outcome: nil)
        let applications = MeetingSessionStatus(status: .transcribing, isRecovering: false,
                                                captureMode: .applications, outcome: nil)
        #expect(microphone.title == "Listening")
        #expect(applications.title == "Capturing")
        #expect(microphone.tone == .live)
        #expect(applications.tone == .live)
    }

    @Test("A recogniser being restarted is a warning, not a live state")
    func recovering() {
        let status = MeetingSessionStatus(status: .transcribing, isRecovering: true,
                                          captureMode: .applications, outcome: nil)
        #expect(status.tone == .warning)
        #expect(status.title != "Capturing")
    }

    @Test("A failure is stated as one even before its ending is recorded")
    func failureBeforeOutcome() {
        let status = MeetingSessionStatus(status: .failed(message: "disk"), isRecovering: false,
                                          captureMode: .microphone, outcome: nil)
        #expect(status.tone == .critical)
        #expect(status.title != "Finished")
    }

    @Test("How a meeting ended decides its status once it has")
    func endings() {
        let finished = MeetingSessionStatus(status: .completed, isRecovering: false,
                                            captureMode: .microphone, outcome: .completed)
        let interrupted = MeetingSessionStatus(status: .idle, isRecovering: false,
                                               captureMode: .microphone, outcome: .interrupted)
        #expect(finished.tone == .positive)
        #expect(interrupted.tone == .warning)
        #expect(finished.title != interrupted.title)
    }

    @Test("Every state's symbol exists")
    func symbolsExist() {
        for status in Self.everyStatus {
            #expect(NSImage(systemSymbolName: status.symbolName, accessibilityDescription: nil) != nil,
                    "\(status.symbolName) is not an SF Symbol")
        }
    }

    @Test("Every state has its own word, so none is told apart by colour alone")
    func wordsAreDistinct() {
        let titles = Self.everyStatus.map(\.title)
        #expect(Set(titles).count == titles.count)
    }
}
