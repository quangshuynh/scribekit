//
//  MeetingRuntimeStatusTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@Suite("MeetingRuntimeStatus")
struct MeetingRuntimeStatusTests {

    private let layout = SessionArtifactLayout(directory: URL(filePath: "/tmp/scribekit-tests/session"))
    private let audioURL = URL(filePath: "/tmp/scribekit-tests/session/audio.m4a")

    /// Builds a status from subsystem states, defaulting the ones a case does
    /// not care about to idle.
    private func status(
        capture: AudioCaptureState = .idle,
        transcription: TranscriptionState = .idle,
        persistence: TranscriptPersistenceState = .idle,
        audio: AudioRetentionState = .idle
    ) -> MeetingRuntimeStatus {
        MeetingRuntimeStatus(
            capture: capture,
            transcription: transcription,
            persistence: persistence,
            audio: audio
        )
    }

    @Test("Four idle subsystems are one idle meeting")
    func idle() {
        #expect(status() == .idle)
        #expect(!status().isActive)
    }

    @Test("A meeting whose files are being created is preparing")
    func preparing() {
        let preparing = status(capture: .preparing, transcription: .preparing, persistence: .preparing)
        #expect(preparing == .preparing)
        #expect(preparing.isActive)
    }

    @Test("Capture and recognition both running is one transcribing meeting")
    func transcribing() {
        let running = status(capture: .capturing, transcription: .transcribing, persistence: .saving(layout))
        #expect(running == .transcribing)
        #expect(running.isActive)
    }

    @Test("A recogniser restarting mid-meeting does not stop the meeting being transcribed")
    func recovering() {
        #expect(status(capture: .capturing, transcription: .recovering, persistence: .saving(layout)) == .transcribing)
    }

    @Test("A teardown in progress is stopping")
    func stopping() {
        let stopping = status(capture: .stopping, transcription: .stopping, persistence: .saving(layout))
        #expect(stopping == .stopping)
        #expect(stopping.isActive)
    }

    @Test("A closed transcript with nothing running is a completed meeting")
    func completed() {
        let completed = status(persistence: .saved(layout))
        #expect(completed == .completed)
        #expect(!completed.isActive)
    }

    @Test("A failed transcript is what the meeting failed of, even while teardown runs")
    func persistenceFailureWins() {
        let failed = status(
            capture: .stopping,
            transcription: .stopping,
            persistence: .failed(message: "Not being saved.", layout: layout)
        )
        #expect(failed == .failed(message: "Not being saved."))
        #expect(!failed.isActive)
        #expect(failed.failureMessage == "Not being saved.")
    }

    @Test("A failed recording fails the meeting even though the transcript closed normally")
    func retentionFailureWins() {
        let failed = status(
            persistence: .saved(layout),
            audio: .failed(message: "Not being recorded.", url: audioURL)
        )
        #expect(failed == .failed(message: "Not being recorded."))
    }

    @Test("Capture and recognition failures are reported when no artifact failed")
    func subsystemFailures() {
        #expect(status(capture: .failed(message: "Capture stopped.")) == .failed(message: "Capture stopped."))
        #expect(
            status(transcription: .failed(message: "Recognition stopped."))
                == .failed(message: "Recognition stopped.")
        )
    }

    @Test("A meeting is never reported as completed while an artifact is still open")
    func openArtifactIsNotCompleted() {
        #expect(status(persistence: .saved(layout), audio: .retaining(audioURL)) == .preparing)
    }
}
