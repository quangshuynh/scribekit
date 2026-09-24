//
//  MeetingStartRequest.swift
//  ScribeKit
//

import Foundation

/// Everything a meeting needs to begin: what to call it, what to listen to,
/// where to write it and what to keep.
///
/// The request exists so the setup screen hands over one value instead of four
/// arguments, and so a coordinator can be asked whether a start is possible
/// before one is attempted. A destination is required, not optional: a meeting
/// without somewhere to write its transcript is not a meeting ScribeKit offers
/// to start.
nonisolated struct MeetingStartRequest: Equatable, Sendable {
    /// The user-entered title, which may be empty.
    let title: String

    /// What to capture: the applications for an App Audio meeting, or the
    /// one microphone input for a Microphone meeting.
    let sources: [CaptureSource]

    /// The folder the user chose for meeting artifacts.
    let destination: URL

    /// How much captured audio the session keeps.
    let audioRetention: AudioRetentionMode

    /// Creates a request.
    ///
    /// - Parameters:
    ///   - title: The user-entered title.
    ///   - sources: The applications, or the microphone input, to capture.
    ///   - destination: The folder the user chose.
    ///   - audioRetention: The session's retention choice.
    init(
        title: String,
        sources: [CaptureSource],
        destination: URL,
        audioRetention: AudioRetentionMode = .default
    ) {
        self.title = title
        self.sources = sources
        self.destination = destination
        self.audioRetention = audioRetention
    }

    /// The capture mode the sources describe, or `nil` when they mix modes.
    var captureMode: CaptureMode? { CaptureMode(sources: sources) }

    /// Why this request cannot become a meeting, judged from the request
    /// alone, or `nil` when nothing in it rules a start out.
    ///
    /// The checks are the shape of the request, not the state of the Mac:
    /// something to capture, one capture mode, and no recording for a
    /// Microphone meeting. Microphone meetings write a transcript and never a
    /// recording, so a request to keep one is refused rather than quietly
    /// changed into a request that keeps nothing.
    var refusal: AudioCaptureError? {
        guard !sources.isEmpty else { return .noSourcesSelected }
        guard let captureMode else { return .mixedCaptureModes }
        if captureMode == .microphone, audioRetention.retainsAudio { return .microphoneAudioNotRetained }
        return nil
    }

    /// Builds the session metadata this request describes.
    ///
    /// - Parameter createdAt: When the session started.
    /// - Returns: The session, in its initial state.
    func makeSession(createdAt: Date) -> MeetingSession {
        MeetingSession(
            title: title,
            createdAt: createdAt,
            audioRetention: audioRetention,
            selectedSources: sources,
            destination: destination
        )
    }
}
