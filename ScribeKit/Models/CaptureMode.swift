//
//  CaptureMode.swift
//  ScribeKit
//

import Foundation

/// Where a meeting's audio comes from.
///
/// A meeting has exactly one. App Audio captures the applications the user
/// selected through ScreenCaptureKit; Microphone listens to the Mac's current
/// sound input. The two are never mixed in one meeting: a request that names
/// both is refused rather than quietly narrowed to one of them.
///
/// Everything downstream of capture — recognition, the transcript, gap
/// incidents, the session record, History — is the same for both. The mode
/// decides which capturer runs and what the setup screen asks for, and it is
/// recorded so a meeting can be told apart afterwards.
nonisolated enum CaptureMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Audio produced by the applications the user selected.
    case applications

    /// The Mac's current microphone input.
    case microphone

    var id: String { rawValue }

    /// The name the interface uses for the mode.
    var displayName: String {
        switch self {
        case .applications: "App Audio"
        case .microphone: "Microphone"
        }
    }

    /// The mode a set of sources describes, or `nil` when they describe more
    /// than one.
    ///
    /// This is the one place that answers the question, so a request, the
    /// capture configuration built from it and the snapshot of the running
    /// meeting cannot disagree about which mode a meeting is in. An empty
    /// selection is application capture with nothing selected, which is
    /// refused for that reason rather than for being a different mode.
    ///
    /// - Parameter sources: The sources a meeting would capture.
    /// - Returns: ``microphone`` for exactly one microphone source,
    ///   ``applications`` for sources that contain no microphone, and `nil`
    ///   for any mixture.
    init?(sources: [CaptureSource]) {
        let microphones = sources.filter { $0.kind == .microphone }.count
        switch (microphones, sources.count) {
        case (0, _): self = .applications
        case (1, 1): self = .microphone
        default: return nil
        }
    }
}
