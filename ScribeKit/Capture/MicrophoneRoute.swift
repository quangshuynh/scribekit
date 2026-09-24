//
//  MicrophoneRoute.swift
//  ScribeKit
//

import Foundation

/// The shape of the audio an input delivers: what a running meeting's tap
/// was installed for.
nonisolated struct MicrophoneStreamFormat: Equatable, Sendable {
    /// Frames per second.
    let sampleRate: Double

    /// Channels per frame.
    let channelCount: Int
}

/// What a Microphone meeting was listening to when it started.
///
/// The fixed point every later change is judged against. A meeting's input is
/// bound to one device for its whole run — System Default is resolved to a
/// device at the start — so this is a device, a format and, for the record,
/// what the Mac's default was at that moment.
nonisolated struct MicrophoneRouteBaseline: Equatable, Sendable {
    /// The UID of the device the meeting's audio unit is bound to.
    let inputID: MicrophoneInput.ID

    /// The format the tap was installed for.
    let format: MicrophoneStreamFormat

    /// The UID of the Mac's default input at the start.
    let defaultInputID: MicrophoneInput.ID?
}

/// What the audio system reports after something about it changed.
///
/// Read fresh from Core Audio and the audio engine each time — never inferred
/// from which notification arrived — because the same notification is posted
/// for a headphone plugged in, a microphone unplugged and a sample rate
/// changed, and only one of those should end a meeting.
nonisolated struct MicrophoneRouteObservation: Equatable, Sendable {
    /// Whether the bound device is still present and alive.
    let inputIsPresent: Bool

    /// The UID of the device the meeting's audio unit is listening to now,
    /// or `nil` when it could not be read.
    let listeningInputID: MicrophoneInput.ID?

    /// The format the input delivers now, or `nil` when it could not be read.
    let format: MicrophoneStreamFormat?

    /// Whether the audio engine is still running.
    let engineIsRunning: Bool

    /// The UID of the Mac's default input now.
    let defaultInputID: MicrophoneInput.ID?
}

/// A change that leaves the meeting listening to the microphone it started
/// with.
nonisolated enum MicrophoneRouteChange: String, Equatable, Sendable {
    /// The Mac's default input moved to another device. The meeting stays on
    /// its own: System Default was resolved when it started.
    case systemDefaultChanged

    /// Nothing about the meeting's input changed — an output device came or
    /// went, or the notification described something else.
    case unrelated
}

/// A change that means the meeting is no longer hearing its microphone.
nonisolated enum MicrophoneRouteLoss: String, Equatable, Sendable {
    /// The bound device was disconnected or became unusable.
    case inputDisconnected

    /// The audio unit is listening to a device other than the bound one.
    case inputChanged

    /// The input now delivers audio in a different format than the tap was
    /// installed for.
    case formatChanged

    /// The audio engine stopped by itself.
    case engineStopped

    /// What the interruption says, in words that name no device: the reason
    /// reaches the screen and diagnostics, and neither needs to know which
    /// hardware it was.
    var interruptionDescription: String {
        switch self {
        case .inputDisconnected:
            "the microphone this meeting was using was disconnected, so ScribeKit stopped listening rather "
            + "than switch to another microphone"
        case .inputChanged:
            "the audio input moved to another microphone, so ScribeKit stopped listening rather than "
            + "transcribe a microphone nobody chose"
        case .formatChanged:
            "the microphone's audio format changed, so ScribeKit stopped listening"
        case .engineStopped:
            "macOS stopped the microphone input, so ScribeKit stopped listening"
        }
    }
}

/// What a change to the audio system means for a running Microphone meeting.
nonisolated enum MicrophoneRouteAssessment: Equatable, Sendable {
    /// The meeting keeps listening; nothing it depends on changed.
    case unaffected(MicrophoneRouteChange)

    /// The meeting's input is gone or different, so the meeting ends.
    case lost(MicrophoneRouteLoss)

    /// Judges an observation against the meeting's start.
    ///
    /// The questions are asked in order of how certain the answer is. A device
    /// that is not there is gone, whatever the engine says. A unit listening
    /// to another device would put someone else's speech in the transcript.
    /// A format the tap was not built for cannot be trusted. An engine that
    /// stopped delivers nothing. Only when all four hold does a change leave
    /// the meeting alone — including the Mac's default input moving, which a
    /// meeting bound to its own device does not follow.
    ///
    /// Anything that could not be read counts against continuing: a meeting
    /// that cannot show it is still hearing its microphone stops rather than
    /// carrying on unverified.
    ///
    /// - Parameters:
    ///   - observation: What the audio system reports now.
    ///   - baseline: What the meeting started with.
    /// - Returns: Whether the meeting keeps listening, and why.
    static func assess(
        _ observation: MicrophoneRouteObservation,
        against baseline: MicrophoneRouteBaseline
    ) -> MicrophoneRouteAssessment {
        guard observation.inputIsPresent else { return .lost(.inputDisconnected) }
        guard observation.listeningInputID == baseline.inputID else { return .lost(.inputChanged) }
        guard observation.format == baseline.format else { return .lost(.formatChanged) }
        guard observation.engineIsRunning else { return .lost(.engineStopped) }
        if observation.defaultInputID != baseline.defaultInputID { return .unaffected(.systemDefaultChanged) }
        return .unaffected(.unrelated)
    }
}
