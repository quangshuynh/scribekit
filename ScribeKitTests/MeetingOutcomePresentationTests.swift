//
//  MeetingOutcomePresentationTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@Suite("MeetingOutcomePresentation")
struct MeetingOutcomePresentationTests {

    private let layout = SessionArtifactLayout(
        directory: URL(filePath: "/tmp/scribekit/meeting", directoryHint: .isDirectory)
    )

    /// Builds a presentation over the states a given ending leaves behind.
    private func presentation(
        outcome: SessionCompletionOutcome,
        capturedAudio: Bool = true,
        capture: AudioCaptureState = .idle,
        transcription: TranscriptionState = .idle,
        persistence: TranscriptPersistenceState = .idle,
        audio: AudioRetentionState = .idle
    ) -> MeetingOutcomePresentation? {
        MeetingOutcomePresentation(
            completion: MeetingCompletion(outcome: outcome, capturedAudio: capturedAudio),
            capture: capture,
            transcription: transcription,
            persistence: persistence,
            audio: audio
        )
    }

    @Test("Nothing is said about a launch in which no meeting has ended")
    func noCompletion() {
        let presentation = MeetingOutcomePresentation(
            completion: nil,
            capture: .idle,
            transcription: .idle,
            persistence: .idle,
            audio: .idle
        )
        #expect(presentation == nil)
    }

    @Test("A meeting the user stopped is reported as finished")
    func completed() {
        let presentation = presentation(outcome: .completed, persistence: .saved(layout))
        #expect(presentation?.category == .completed)
        #expect(presentation?.isFailure == false)
        #expect(presentation?.detail == nil)
    }

    @Test("Capture ending by itself is reported as interrupted, never as finished")
    func interrupted() {
        let presentation = presentation(
            outcome: .interrupted,
            capture: .failed(message: "Capture stopped: the stream ended."),
            persistence: .saved(layout)
        )
        #expect(presentation?.category == .interrupted)
        #expect(presentation?.isFailure == true)
        #expect(presentation?.headline.contains("interrupted") == true)
        #expect(presentation?.detail == "Capture stopped: the stream ended.")
        #expect(presentation?.meaning.contains("Interrupted") == true)
        #expect(presentation?.meaning.contains("closed") == true)
    }

    @Test("A transcript that stopped being written is the reason the meeting ended")
    func transcriptFailure() {
        let presentation = presentation(
            outcome: .failed,
            persistence: .failed(message: "The transcript could not be written to.", layout: layout)
        )
        #expect(presentation?.category == .transcriptFailure)
        #expect(presentation?.meaning.contains("could no longer write the transcript") == true)
        #expect(presentation?.detail == "The transcript could not be written to.")
    }

    @Test("A recording that failed is reported without implying the transcript was lost")
    func audioFailure() {
        let presentation = presentation(
            outcome: .failed,
            persistence: .saved(layout),
            audio: .failed(message: "The audio file could not be completed.", url: nil)
        )
        #expect(presentation?.category == .audioFailure)
        #expect(presentation?.meaning.contains("transcript") == true)
        #expect(presentation?.meaning.contains("left in the meeting folder") == true)
    }

    @Test("A recogniser that could not be brought back ends the meeting truthfully")
    func recognitionFailure() {
        let presentation = presentation(
            outcome: .failed,
            transcription: .failed(message: "Speech recognition stopped repeatedly."),
            persistence: .saved(layout)
        )
        #expect(presentation?.category == .recognitionFailure)
        #expect(presentation?.nextStep.contains("Start another") == true)
    }

    @Test("A start that never captured a second is not described as a meeting that ended")
    func startFailure() {
        let presentation = presentation(
            outcome: .failed,
            capturedAudio: false,
            persistence: .failed(message: "The meeting folder could not be created.", layout: nil)
        )
        #expect(presentation?.category == .startFailure)
        #expect(presentation?.headline == "The meeting did not start")
        #expect(presentation?.detail == "The meeting folder could not be created.")
    }

    @Test("Capture failing at start is a start failure, not an interruption")
    func captureStartFailure() {
        let presentation = presentation(
            outcome: .failed,
            capturedAudio: false,
            capture: .failed(message: "Capture could not start."),
            persistence: .saved(layout)
        )
        #expect(presentation?.category == .startFailure)
    }

    @Test("The transcript is named as the reason before the recording is")
    func transcriptFailureOutranksAudio() {
        let presentation = presentation(
            outcome: .failed,
            persistence: .failed(message: "The transcript could not be written to.", layout: layout),
            audio: .failed(message: "The audio file could not be completed.", url: nil)
        )
        #expect(presentation?.category == .transcriptFailure)
    }

    @Test("Every ending answers what happened, what it means and what to do next")
    func everyEndingIsActionable() {
        let endings: [MeetingOutcomePresentation?] = [
            presentation(outcome: .completed, persistence: .saved(layout)),
            presentation(outcome: .interrupted, capture: .failed(message: "x"), persistence: .saved(layout)),
            presentation(outcome: .failed, persistence: .failed(message: "x", layout: layout)),
            presentation(outcome: .failed, persistence: .saved(layout), audio: .failed(message: "x", url: nil)),
            presentation(outcome: .failed, transcription: .failed(message: "x"), persistence: .saved(layout)),
            presentation(outcome: .failed, capturedAudio: false, persistence: .failed(message: "x", layout: nil))
        ]
        #expect(endings.allSatisfy { $0 != nil })
        for case let ending? in endings {
            #expect(!ending.headline.isEmpty)
            #expect(!ending.meaning.isEmpty)
            #expect(!ending.nextStep.isEmpty)
            #expect(ending.accessibilityDescription.contains(ending.headline))
        }
    }

    @Test("The menu bar says interrupted for an interruption and failed for a failure")
    func menuBarDistinguishesEndings() {
        let interrupted = MeetingMenuBarPresentation(
            status: .failed(message: "Capture stopped."),
            meeting: nil,
            transcript: nil,
            audio: nil,
            canStop: false,
            outcome: presentation(
                outcome: .interrupted,
                capture: .failed(message: "Capture stopped."),
                persistence: .saved(layout)
            )
        )
        #expect(interrupted.statusLine == "Meeting interrupted")

        let failed = MeetingMenuBarPresentation(
            status: .failed(message: "The transcript could not be written to."),
            meeting: nil,
            transcript: nil,
            audio: nil,
            canStop: false,
            outcome: presentation(
                outcome: .failed,
                persistence: .failed(message: "The transcript could not be written to.", layout: layout)
            )
        )
        #expect(failed.statusLine == "Meeting failed")
    }
}
