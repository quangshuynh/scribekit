//
//  HistoryModel.swift
//  ScribeKit
//

import AppKit
import Foundation

/// Owns the History screen: what was found in the save folder, what the user
/// typed into the search field, and what matched it.
///
/// The model holds state and delegates every filesystem decision to
/// ``HistoryService``, so the screen displays history rather than implementing
/// it. It owns no meeting: it never creates a ``MeetingRuntime``, never starts
/// or stops capture, and never attaches a transcription consumer, so opening,
/// searching or refreshing History cannot reach a meeting that is running.
///
/// Nothing here is a singleton, nothing polls and nothing watches the
/// filesystem. A load happens when History appears, when the user asks for
/// one, and when a meeting finishes; each load replaces the previous one
/// wholesale, so a session whose folder has since been removed does not linger
/// as a stale row.
@MainActor
@Observable
final class HistoryModel {

    /// What the screen has to say about the save folder.
    ///
    /// One value describes the whole situation, so "not loaded yet" cannot be
    /// confused with "loaded and empty", and a folder that could not be opened
    /// is never silently the same as a folder with no meetings in it.
    enum State: Equatable {
        /// The folder has not been read yet.
        case unloaded

        /// The folder is being read.
        case loading

        /// The folder was read; the report says what was in it.
        case loaded(HistoryReport)

        /// The folder could not be opened, so nothing is known about it.
        case unavailable(message: String)
    }

    /// What the screen shows.
    private(set) var state: State = .unloaded

    /// The save folder the current listing came from.
    private(set) var destination: URL?

    /// What the user typed into the search field.
    ///
    /// Setting it re-runs the search over the documents already in memory. No
    /// file is read, so a keystroke costs a walk over text that is already
    /// there.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            refreshResults()
        }
    }

    /// The sessions matching ``query``, best match first, or every session
    /// when nothing has been typed.
    private(set) var results: [HistorySearchResult] = []

    /// The loaded transcripts, prepared for matching.
    ///
    /// Built once per load and replaced by the next one. It is derived
    /// entirely from the Markdown on disk and is never written anywhere, so
    /// dropping it costs nothing but the work of reading the folder again.
    private var index = TranscriptSearchIndex.empty

    /// Plays retained audio for review.
    ///
    /// Owned here rather than by a view, so a claim on the user's folder
    /// cannot outlive the screen that opened it: leaving History, refreshing
    /// it or selecting another meeting stops playback and releases the lease.
    let player: RetainedAudioPlayer

    private let service: HistoryService
    private let saveLocation: SaveLocationPersisting

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - service: Reads the save folder. The default reaches the real
    ///     filesystem; tests substitute one built on a store double.
    ///   - saveLocation: Where the chosen folder is remembered. History reads
    ///     the same bookmark the meeting screen does and never looks anywhere
    ///     the user did not choose.
    ///   - player: Plays retained audio for review. Holds a security-scoped
    ///     lease for exactly as long as a recording is being read. A fresh one
    ///     by default; a test substitutes one built on an access double.
    init(
        service: HistoryService = HistoryService(),
        saveLocation: SaveLocationPersisting = SecurityScopedSaveLocationStore(),
        player: RetainedAudioPlayer? = nil
    ) {
        self.service = service
        self.saveLocation = saveLocation
        self.player = player ?? RetainedAudioPlayer()
    }

    /// The sessions and their text, as the last load produced them.
    var documents: [TranscriptSearchDocument] {
        guard case let .loaded(report) = state else { return [] }
        return report.documents
    }

    /// Session directories that could not be interpreted.
    var problems: [HistoryProblem] {
        guard case let .loaded(report) = state else { return [] }
        return report.problems
    }

    /// How many meetings the last load found.
    var sessionCount: Int { documents.count }

    /// Whether a load is under way.
    var isLoading: Bool { state == .loading }

    /// Why the folder could not be read, when it could not be.
    var unavailableMessage: String? {
        guard case let .unavailable(message) = state else { return nil }
        return message
    }

    /// Whether the folder was read and held no meetings at all.
    var isEmpty: Bool {
        guard case let .loaded(report) = state else { return false }
        return report.isEmpty
    }

    /// Reads the save folder and rebuilds the search documents from it.
    ///
    /// The folder comes from the bookmark the user's choice was stored under.
    /// When it cannot be restored or opened, the screen says so rather than
    /// listing meetings from somewhere the user did not choose.
    func load() async {
        player.stop()
        state = .loading
        index = .empty
        results = []

        let folder: URL?
        do {
            folder = try saveLocation.restore()
        } catch {
            destination = nil
            state = .unavailable(message: Self.message(for: error))
            return
        }
        guard let folder else {
            destination = nil
            state = .unavailable(message: Self.message(for: HistoryError.noDestination))
            return
        }

        destination = folder
        do {
            let report = try await service.load(folder)
            index = TranscriptSearchIndex(report.documents)
            state = .loaded(report)
        } catch {
            state = .unavailable(message: Self.message(for: error))
        }
        refreshResults()
    }

    /// The text of one session, for the detail pane's preview.
    ///
    /// - Parameter id: The session's directory.
    /// - Returns: Its document, or `nil` when the session is not in the
    ///   current listing.
    func document(for id: URL) -> TranscriptSearchDocument? {
        documents.first { $0.id == id }
    }

    /// Reveals a file in the Finder.
    ///
    /// Access to the save folder is taken for the length of the call and
    /// released again, the same narrow claim a load takes.
    ///
    /// - Parameter url: The file to reveal.
    func showInFinder(_ url: URL) {
        withDestinationAccess { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    /// Opens a transcript in whichever application the user has set for
    /// Markdown.
    ///
    /// ScribeKit has no transcript editor and this is not one: the file is
    /// handed to another application exactly as it is on disk.
    ///
    /// - Parameter url: The transcript to open.
    func openTranscript(_ url: URL) {
        withDestinationAccess { NSWorkspace.shared.open(url) }
    }

    /// Plays the retained audio around one review candidate.
    ///
    /// Nothing is written: the recording is opened read-only, and listening to
    /// a passage changes no artifact and no review state.
    ///
    /// - Parameters:
    ///   - candidate: The span to hear.
    ///   - session: The meeting it belongs to, which names the recording.
    func play(_ candidate: TranscriptReviewCandidate, of session: HistorySession) async {
        guard let audio = session.audio else { return }
        await player.play(
            RetainedAudioPlaybackPlan(candidate: candidate, audio: audio),
            in: destination
        )
    }

    /// Stops playback and gives up the claim it held on the user's folder.
    func stopPlayback() {
        player.stop()
    }

    /// Re-runs the search over the documents in memory.
    private func refreshResults() {
        results = TranscriptSearch.results(for: query, in: index)
    }

    /// Runs work with security-scoped access to the save folder held open for
    /// exactly the length of that work.
    ///
    /// - Parameter body: The work to perform.
    private func withDestinationAccess(_ body: () -> Void) {
        guard let destination else {
            body()
            return
        }
        try? SecurityScopedAccess.withAccess(to: destination) { _ in body() }
    }

    /// Converts an error into a message for the screen.
    ///
    /// - Parameter error: The error the service or the bookmark store
    ///   reported.
    /// - Returns: A user-facing description; raw OS codes are never the whole
    ///   explanation.
    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
