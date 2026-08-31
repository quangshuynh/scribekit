//
//  MeetingOutcomePresentation.swift
//  ScribeKit
//

import Foundation

/// How a meeting ended, recorded when its artifacts were closed.
///
/// The outcome alone does not say enough to explain a failure: a start that
/// never captured a second and a meeting that died an hour in are both recorded
/// as ``SessionCompletionOutcome/failed``, and what to tell the user about the
/// artifacts is not the same for the two. ``capturedAudio`` is the fact that
/// separates them, so it is kept beside the outcome rather than guessed at
/// afterwards from a clock that reads zero either way.
nonisolated struct MeetingCompletion: Equatable, Sendable {
    /// What the session record was closed as.
    let outcome: SessionCompletionOutcome

    /// Whether capture actually ran before the meeting ended.
    let capturedAudio: Bool
}

/// What to tell the user about a meeting that has ended.
///
/// The three endings ScribeKit records are not interchangeable — a meeting the
/// user stopped, a meeting whose capture died under it, and a meeting whose
/// durable artifacts stopped being written are three different claims — and
/// this type is where that distinction becomes words. It answers the same three
/// questions every time: what happened, what it means for this meeting, and
/// what can be done next. The framework's own text, when there is any, is
/// secondary detail rather than the headline.
nonisolated struct MeetingOutcomePresentation: Equatable, Sendable {

    /// The kind of ending, which is what a test should assert rather than a
    /// paragraph that may be reworded.
    enum Category: Equatable, Sendable {
        /// The user stopped the meeting and every artifact closed cleanly.
        case completed

        /// Capture stopped without being asked to.
        case interrupted

        /// The canonical transcript stopped being written.
        case transcriptFailure

        /// The retained recording stopped being written or could not be
        /// finalised.
        case audioFailure

        /// Recognition could not be brought back.
        case recognitionFailure

        /// The meeting never began: a start failed before any audio was
        /// captured.
        case startFailure
    }

    /// The kind of ending.
    let category: Category

    /// A short phrase naming what happened.
    let headline: String

    /// What it means for this meeting's transcript and recording.
    let meaning: String

    /// What the user can do now.
    let nextStep: String

    /// The subsystem's own message, shown under the explanation when there is
    /// one worth showing.
    let detail: String?

    /// Whether this ending is a failure, as opposed to a finished meeting.
    ///
    /// An interruption counts: the meeting did not end because someone ended
    /// it, and describing it as a finished meeting would be the one thing this
    /// type exists to prevent.
    var isFailure: Bool { category != .completed }

    /// The whole message as one string, used as the accessibility value so
    /// assistive technology hears what the panel shows.
    var accessibilityDescription: String {
        [headline, meaning, nextStep, detail].compactMap { $0 }.joined(separator: " ")
    }

    /// Describes a meeting that has ended.
    ///
    /// - Parameters:
    ///   - completion: How the meeting was closed, or `nil` when none has
    ///     ended in this launch.
    ///   - capture: The capture subsystem's final state.
    ///   - transcription: The recogniser's final state.
    ///   - persistence: The durable transcript's final state.
    ///   - audio: The retained recording's final state.
    /// - Returns: `nil` when there is no ended meeting to describe.
    init?(
        completion: MeetingCompletion?,
        capture: AudioCaptureState,
        transcription: TranscriptionState,
        persistence: TranscriptPersistenceState,
        audio: AudioRetentionState
    ) {
        guard let completion else { return nil }

        switch completion.outcome {
        case .completed:
            category = .completed
            headline = "Meeting finished"
            meaning = "You stopped it. The transcript was flushed and closed, and any recording was "
                + "finalised, so both hold everything the meeting produced."
            nextStep = "Open it from History to read it back, or start another meeting."
            detail = nil

        case .interrupted:
            category = .interrupted
            headline = "Meeting interrupted"
            meaning = "Audio capture stopped without being asked to, so ScribeKit ended the meeting. "
                + "Everything captured up to that moment reached the transcript and any recording, and both "
                + "were closed. The meeting is recorded as Interrupted, not as finished."
            nextStep = "The saved transcript and recording are in the meeting folder and in History. "
                + "ScribeKit does not continue an interrupted meeting; start a new one when you are ready."
            detail = capture.failureMessage

        case .failed:
            let reason = Self.failureDetail(
                capture: capture,
                transcription: transcription,
                persistence: persistence,
                audio: audio
            )
            detail = reason.message

            guard completion.capturedAudio else {
                category = .startFailure
                headline = "The meeting did not start"
                meaning = "Nothing was captured and nothing was transcribed. A meeting folder ScribeKit had "
                    + "already created is left where it is, holding an empty transcript; ScribeKit does not "
                    + "delete it."
                nextStep = "Correct what is described below, then start the meeting again."
                return
            }

            switch reason.category {
            case .transcriptFailure:
                category = .transcriptFailure
                headline = "Meeting stopped: the transcript could not be saved"
                meaning = "ScribeKit stopped capture and recognition because it could no longer write the "
                    + "transcript safely. Nothing spoken after that moment was transcribed. Everything "
                    + "written before it is still in the file, which was closed and recorded as failed."
                nextStep = "Check the save folder — a disconnected disk, a full one, or access that was "
                    + "revoked are the usual causes — then start another meeting."
            case .audioFailure:
                category = .audioFailure
                headline = "Meeting stopped: the recording could not be saved"
                meaning = "The transcript holds everything that was recognised and was closed. The audio "
                    + "file stopped being written, so it is incomplete and may not play; it was left in the "
                    + "meeting folder exactly as it is, because meeting audio cannot be captured again."
                nextStep = "Start another meeting. Choosing not to keep audio records the transcript only."
            case .recognitionFailure:
                category = .recognitionFailure
                headline = "Meeting stopped: speech recognition could not continue"
                meaning = "The recogniser stopped and could not be restarted, so ScribeKit stopped capture "
                    + "rather than keep recording audio nothing was transcribing. The transcript and any "
                    + "recording hold everything up to that point and were closed."
                nextStep = "There is no way to continue this meeting. Start another one."
            case .startFailure, .completed, .interrupted:
                category = .startFailure
                headline = "The meeting ended in a failure"
                meaning = "ScribeKit ended the meeting and closed its artifacts as far as it could. "
                    + "Everything that reached the transcript and any recording was kept."
                nextStep = "Start another meeting."
            }
        }
    }

    /// Picks which subsystem's failure the meeting ended of.
    ///
    /// The order is the artifact order the runtime itself fails in: the
    /// canonical transcript first, then the retained recording, then the
    /// recogniser, then capture. It matches ``MeetingRuntimeStatus``, so the
    /// menu bar's failure message and this panel name the same thing.
    private static func failureDetail(
        capture: AudioCaptureState,
        transcription: TranscriptionState,
        persistence: TranscriptPersistenceState,
        audio: AudioRetentionState
    ) -> (category: Category, message: String?) {
        if let message = persistence.failureMessage { return (.transcriptFailure, message) }
        if let message = audio.failureMessage { return (.audioFailure, message) }
        if let message = transcription.failureMessage { return (.recognitionFailure, message) }
        if let message = capture.failureMessage { return (.startFailure, message) }
        return (.startFailure, nil)
    }
}
