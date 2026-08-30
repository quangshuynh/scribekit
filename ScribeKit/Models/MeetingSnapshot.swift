//
//  MeetingSnapshot.swift
//  ScribeKit
//

import Foundation

/// The configuration one meeting was started with, fixed for its whole run.
///
/// A meeting is started from settings the user can keep editing afterwards —
/// the title field, the application checkboxes, the retention picker, the save
/// folder, the recognition language. None of those edits may reach a meeting
/// that is already running: the transcript header has been written, the audio
/// file has been opened in one format, and capture is attached to one set of
/// applications. Taking a copy at the moment of the start is what makes that
/// true by construction rather than by remembering to disable controls.
///
/// It is also what the menu bar shows. A window that has been closed cannot be
/// asked what the meeting is called.
nonisolated struct MeetingSnapshot: Equatable, Sendable {
    /// The session as it was described at the start: title, sources,
    /// destination, retention mode and creation time.
    let session: MeetingSession

    /// The BCP-47 locale recognition was started in.
    let localeIdentifier: String

    /// Creates a snapshot.
    ///
    /// - Parameters:
    ///   - session: The session the meeting was started as.
    ///   - localeIdentifier: The recognition locale for this run.
    init(session: MeetingSession, localeIdentifier: String) {
        self.session = session
        self.localeIdentifier = localeIdentifier
    }

    /// The title to show, with the placeholder substituted for an empty one.
    var title: String { session.displayTitle }

    /// The applications this meeting captures.
    var sources: [CaptureSource] { session.selectedSources }

    /// The folder this meeting writes to.
    var destination: URL { session.destination }

    /// How much audio this meeting keeps.
    var audioRetention: AudioRetentionMode { session.audioRetention }

    /// When the meeting started.
    var startedAt: Date { session.createdAt }

    /// The selected applications named in one phrase, or `nil` when there are
    /// none to name.
    var sourceSummary: String? {
        guard !sources.isEmpty else { return nil }
        return sources.map(\.displayName).formatted(.list(type: .and))
    }
}
