//
//  DerivedSessionStore.swift
//  ScribeKit
//

import Foundation

/// The one write boundary History has, and everything it may touch.
///
/// ``HistoryStoring`` stays read-only by construction: it has no method that
/// creates, replaces, appends to or deletes anything, so "listing, previewing
/// and searching a meeting leaves every artifact byte-identical" remains a
/// property of the type system. Notes and reviewed state are writes, so they
/// get their own boundary rather than a hole in that one, and this boundary
/// can only reach `.scribekit/derived.json`:
///
/// ```
/// HistoryStoring          reads transcript.md, session.json, review.json, audio
/// DerivedSessionStoring   reads and writes .scribekit/derived.json
/// ```
///
/// Neither the transcript, the recording, the session record nor the review
/// sidecar is addressable from here. A failed derived write therefore cannot
/// damage a source artifact — there is no path from this protocol to one.
///
/// Nothing here starts or stops security-scoped access; ``DerivedSessionService``
/// owns that, so a read or a write cannot open a claim something else has to
/// close.
nonisolated protocol DerivedSessionStoring: Sendable {

    /// Reads a session's derived state.
    ///
    /// Absence is an answer rather than a failure: a meeting the user has
    /// written nothing about has no sidecar, which is the state every meeting
    /// recorded before this file existed is in.
    ///
    /// - Parameters:
    ///   - layout: Where the session's artifacts live.
    ///   - sessionID: The identity the meeting's record carries.
    /// - Returns: The state, or `nil` when there is no sidecar.
    /// - Throws: ``DerivedSessionError/unreadable``,
    ///   ``DerivedSessionError/malformed``,
    ///   ``DerivedSessionError/unsupportedSchemaVersion(_:)`` or
    ///   ``DerivedSessionError/sessionMismatch``. Each of them leaves the file
    ///   exactly as it was.
    func readDerivedState(
        from layout: SessionArtifactLayout,
        sessionID: UUID
    ) throws -> DerivedSessionState?

    /// Writes a session's derived state, refusing to land on a version the
    /// caller never saw.
    ///
    /// The write is atomic and the check happens immediately before it: what
    /// is on disk is read, and its revision must be the one the caller loaded.
    /// Anything else — a different revision, a file that appeared where there
    /// was none, a sidecar this build cannot interpret — is refused, so a
    /// damaged or newer-format file is never silently overwritten.
    ///
    /// - Parameters:
    ///   - state: The user's state to record. Its revision token is replaced.
    ///   - layout: Where the session's artifacts live.
    ///   - expectedRevision: The revision the caller loaded, or `nil` when it
    ///     found no sidecar at all.
    ///   - date: The moment to record as the update time.
    /// - Returns: The record as it was written, carrying its new revision.
    /// - Throws: ``DerivedSessionError/staleWrite`` when the file changed
    ///   since it was loaded, ``DerivedSessionError/writeFailed`` when it
    ///   could not be written, or the same reading errors
    ///   ``readDerivedState(from:sessionID:)`` throws.
    @discardableResult
    func writeDerivedState(
        _ state: DerivedSessionState,
        to layout: SessionArtifactLayout,
        expectedRevision: UUID?,
        at date: Date
    ) throws -> DerivedSessionState
}

/// The derived sidecar as `FileManager` reads and writes it.
nonisolated struct FileManagerDerivedSessionStore: DerivedSessionStoring {

    /// Creates the system-backed store.
    init() {}

    func readDerivedState(
        from layout: SessionArtifactLayout,
        sessionID: UUID
    ) throws -> DerivedSessionState? {
        guard let state = try readState(at: layout.derivedURL) else { return nil }
        guard state.sessionID == sessionID else { throw DerivedSessionError.sessionMismatch }
        return state
    }

    @discardableResult
    func writeDerivedState(
        _ state: DerivedSessionState,
        to layout: SessionArtifactLayout,
        expectedRevision: UUID?,
        at date: Date
    ) throws -> DerivedSessionState {
        let onDisk = try readState(at: layout.derivedURL)
        guard onDisk?.revision == expectedRevision else { throw DerivedSessionError.staleWrite }
        if let onDisk, onDisk.sessionID != state.sessionID { throw DerivedSessionError.sessionMismatch }

        let written = state.preparedForWrite(at: date)
        let data = try written.encoded()
        do {
            try FileManager.default.createDirectory(
                at: layout.metadataDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: layout.derivedURL, options: [.atomic])
        } catch {
            throw DerivedSessionError.writeFailed
        }
        return written
    }

    /// Reads whatever is at a sidecar's location, without judging whose it is.
    ///
    /// - Parameter url: The sidecar's location.
    /// - Returns: The decoded record, or `nil` when there is no file.
    /// - Throws: ``DerivedSessionError/unreadable`` when a file is present but
    ///   cannot be read, or whatever decoding refuses.
    private func readState(at url: URL) throws -> DerivedSessionState? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DerivedSessionError.unreadable
        }
        return try DerivedSessionState.decoded(from: data)
    }
}
