//
//  DerivedSessionModel.swift
//  ScribeKit
//

import Foundation

/// Owns one meeting's user-derived state while its detail pane is on screen:
/// the notes being typed and which review candidates have been dealt with.
///
/// Everything the user changes here is written to `.scribekit/derived.json`
/// and nowhere else. The transcript, the recording, the session record and the
/// review sidecar are read-only source material, and this model has no way to
/// reach them — its only collaborator is ``DerivedSessionService``.
///
/// Two save models, deliberately different, because the two actions are
/// different. Marking a passage reviewed is a discrete decision and is written
/// as it is made. Notes are typed, so they are held in memory and written when
/// the user asks, which keeps a keystroke from being a disk write and keeps
/// "saved" a claim ScribeKit only makes after a write succeeded.
@MainActor
@Observable
final class DerivedSessionModel {

    /// Whether this meeting's derived state can be read and written.
    enum State: Equatable {
        /// No meeting is selected.
        case idle

        /// The sidecar is being read.
        case loading

        /// The sidecar was read, or there is none, and the user can write.
        case ready

        /// Something is at the sidecar's location that this build must not
        /// overwrite: damaged bytes, a newer schema, or another meeting's
        /// state. Reading and writing are both refused, and the file is left
        /// exactly as it is.
        case refused(message: String)

        /// The meeting has no recorded identity, so there is nothing to
        /// attach derived state to.
        case unsupported(message: String)
    }

    /// Where the meeting's derived state stands.
    private(set) var state: State = .idle

    /// The notes as the user is typing them, bound to the editor.
    ///
    /// Held verbatim. ScribeKit does not render, reflow, trim or generate any
    /// of it, and nothing writes into it but the user.
    var notesDraft = ""

    /// Whether a write is under way.
    private(set) var isSaving = false

    /// Why the last write did not happen, when it did not.
    private(set) var failureMessage: String?

    /// The state as it is actually on disk, or `nil` when there is no sidecar.
    private(set) var saved: DerivedSessionState?

    private let service: DerivedSessionService
    private var directory: URL?
    private var destination: URL?
    private var sessionID: UUID?

    /// Creates the model.
    ///
    /// - Parameter service: Reads and writes the derived sidecar. The default
    ///   reaches the real filesystem; tests substitute one built on a store
    ///   double.
    init(service: DerivedSessionService = DerivedSessionService()) {
        self.service = service
    }

    /// Whether the editor and the review marks accept input.
    var isEditable: Bool { state == .ready }

    /// Whether the notes in the editor differ from the notes on disk.
    var hasUnsavedNotes: Bool { notesDraft != (saved?.notes ?? "") }

    /// One sentence describing where the notes stand, honest about what has
    /// actually reached the disk.
    var statusDescription: String {
        if let failureMessage { return failureMessage }
        if isSaving { return "Saving…" }
        if hasUnsavedNotes { return "Unsaved changes." }
        if let updatedAt = saved?.updatedAt {
            return "Saved \(updatedAt.formatted(date: .abbreviated, time: .shortened))."
        }
        return "No notes yet."
    }

    /// Forgets whatever meeting was selected.
    func clear() {
        directory = nil
        destination = nil
        sessionID = nil
        saved = nil
        notesDraft = ""
        failureMessage = nil
        isSaving = false
        state = .idle
    }

    /// Reads the derived state of one meeting.
    ///
    /// Unsaved notes are not carried across a selection change: choosing
    /// another meeting reloads the editor from disk, so what it shows is
    /// always what was actually written.
    ///
    /// Re-reading the same meeting is not that. History rebuilds its listing
    /// for reasons the user did not ask for — returning to the tab, a meeting
    /// finishing elsewhere — and text typed into the editor survives one,
    /// because losing it would be data loss without an action to blame it on.
    /// It is carried only when the sidecar on disk is still the version the
    /// editor was working from; a file that changed underneath is shown as it
    /// now is rather than being silently outranked by a draft.
    ///
    /// - Parameters:
    ///   - session: The meeting whose detail pane is open.
    ///   - destination: The save folder it sits in, for sandbox access.
    func load(_ session: HistorySession, destination: URL?) async {
        let previousSessionID = sessionID
        let previousRevision = saved?.revision
        let carriedDraft = session.sessionID != nil
            && session.sessionID == previousSessionID
            && hasUnsavedNotes
            ? notesDraft
            : nil

        clear()
        directory = session.directory
        self.destination = destination

        guard let id = session.sessionID else {
            state = .unsupported(
                message: "This meeting has no ScribeKit session record, so there is no identity to attach "
                    + "notes or review marks to. Its transcript is unaffected."
            )
            return
        }
        sessionID = id
        state = .loading

        do {
            let loaded = try await service.load(sessionID: id, in: session.directory, destination: destination)
            saved = loaded
            if let carriedDraft, loaded?.revision == previousRevision {
                notesDraft = carriedDraft
            } else {
                notesDraft = loaded?.notes ?? ""
            }
            state = .ready
        } catch {
            state = .refused(message: Self.message(for: error))
        }
    }

    /// Writes the notes in the editor.
    ///
    /// The reviewed marks already on disk are carried through unchanged, so
    /// saving notes never revises a decision the user made about a passage.
    func saveNotes() async {
        await write(notes: notesDraft, reviewed: saved?.reviewedSpanIndexes ?? [])
    }

    /// Records the user's disposition for one review candidate, writing it
    /// immediately.
    ///
    /// Notes being typed are not written by this: the notes already on disk
    /// are carried through, and unsaved text stays unsaved until the user
    /// saves it.
    ///
    /// - Parameters:
    ///   - reviewed: Whether the passage has been dealt with.
    ///   - spanIndex: The candidate's span index, as `review.json` numbers it.
    func setReviewed(_ reviewed: Bool, spanIndex: Int) async {
        let current = saved?.reviewedSpanIndexes ?? []
        var indexes = Set(current)
        if reviewed { indexes.insert(spanIndex) } else { indexes.remove(spanIndex) }
        guard Set(current) != indexes else { return }
        await write(notes: saved?.notes ?? "", reviewed: indexes.sorted())
    }

    /// Whether the user has marked one candidate as dealt with.
    ///
    /// A mark whose span index no longer names a candidate resolves to
    /// nothing: it is never shown against another passage, and it stays in the
    /// file rather than being quietly discarded.
    ///
    /// - Parameter spanIndex: The candidate's span index.
    /// - Returns: Whether it is marked reviewed.
    func isReviewed(spanIndex: Int) -> Bool {
        saved?.isReviewed(spanIndex: spanIndex) ?? false
    }

    /// How many of a meeting's candidates the user has dealt with.
    ///
    /// - Parameter spanIndexes: The span indexes the meeting actually has
    ///   candidates for.
    /// - Returns: How many of them are marked reviewed.
    func reviewedCount(among spanIndexes: [Int]) -> Int {
        spanIndexes.count { isReviewed(spanIndex: $0) }
    }

    /// Writes one version of the derived state and adopts it only if the write
    /// succeeded.
    ///
    /// A failure leaves ``saved`` alone and ``notesDraft`` untouched, so the
    /// screen keeps showing what the user typed and never claims a write that
    /// did not happen.
    ///
    /// - Parameters:
    ///   - notes: The notes to record.
    ///   - reviewed: The span indexes to record as reviewed.
    private func write(notes: String, reviewed: [Int]) async {
        guard state == .ready, let directory, let sessionID else { return }
        isSaving = true
        failureMessage = nil

        let candidate = DerivedSessionState(
            sessionID: sessionID,
            notes: notes,
            reviewedSpanIndexes: reviewed
        )
        do {
            saved = try await service.save(
                candidate,
                in: directory,
                destination: destination,
                expectedRevision: saved?.revision
            )
        } catch {
            failureMessage = Self.message(for: error)
        }
        isSaving = false
    }

    /// Converts an error into a message for the screen.
    ///
    /// - Parameter error: What the service reported.
    /// - Returns: A user-facing description; raw OS codes are never the whole
    ///   explanation.
    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
