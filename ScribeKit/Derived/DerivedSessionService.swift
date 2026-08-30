//
//  DerivedSessionService.swift
//  ScribeKit
//

import Foundation

/// Reads and writes one meeting's derived state, holding sandbox access for
/// exactly the length of each call.
///
/// The service is an actor, so its filesystem work runs off the main actor and
/// one operation at a time. It mirrors ``HistoryService``: security-scoped
/// access to the save folder is opened for a read or a write and closed again,
/// and History holds no claim on the user's folder while notes are merely
/// being typed. The only lease in History that outlives a call is the one
/// ``RetainedAudioPlayer`` holds while audio is actually playing.
///
/// It runs when it is asked to. No timer, no filesystem watcher, no repeat
/// scan, and nothing left running when a call returns.
actor DerivedSessionService {

    private let store: any DerivedSessionStoring
    private let access: any SecurityScopedResourceAccessing

    /// Creates a service.
    ///
    /// - Parameters:
    ///   - store: How the derived sidecar is read and written. The system by
    ///     default; tests substitute a double that can fail on demand.
    ///   - access: How security-scoped access is started and stopped.
    init(
        store: any DerivedSessionStoring = FileManagerDerivedSessionStore(),
        access: any SecurityScopedResourceAccessing = SystemSecurityScopedResourceAccess()
    ) {
        self.store = store
        self.access = access
    }

    /// Reads one meeting's derived state.
    ///
    /// - Parameters:
    ///   - sessionID: The identity the meeting's record carries.
    ///   - directory: The session's directory.
    ///   - destination: The save folder the session sits in, or `nil` when
    ///     there is no security scope to open.
    /// - Returns: The state, or `nil` when the meeting has no sidecar.
    /// - Throws: ``DerivedSessionError`` describing what was found and left
    ///   untouched.
    func load(
        sessionID: UUID,
        in directory: URL,
        destination: URL?
    ) throws -> DerivedSessionState? {
        try withAccess(to: destination) {
            try store.readDerivedState(
                from: SessionArtifactLayout(directory: directory),
                sessionID: sessionID
            )
        }
    }

    /// Writes one meeting's derived state.
    ///
    /// - Parameters:
    ///   - state: The user's state to record.
    ///   - directory: The session's directory.
    ///   - destination: The save folder the session sits in, or `nil` when
    ///     there is no security scope to open.
    ///   - expectedRevision: The revision the caller loaded, or `nil` when it
    ///     found no sidecar.
    ///   - date: The moment to record as the update time.
    /// - Returns: The record as it was written.
    /// - Throws: ``DerivedSessionError`` describing why nothing was written.
    @discardableResult
    func save(
        _ state: DerivedSessionState,
        in directory: URL,
        destination: URL?,
        expectedRevision: UUID?,
        at date: Date = Date()
    ) throws -> DerivedSessionState {
        try withAccess(to: destination) {
            try store.writeDerivedState(
                state,
                to: SessionArtifactLayout(directory: directory),
                expectedRevision: expectedRevision,
                at: date
            )
        }
    }

    /// Runs work with security-scoped access to the save folder held open for
    /// exactly the length of that work.
    ///
    /// - Parameters:
    ///   - destination: The folder the user chose, or `nil` when none is
    ///     known and the work runs without a scope.
    ///   - body: The work to perform.
    /// - Returns: Whatever `body` returns.
    /// - Throws: ``DerivedSessionError/unreadable`` when macOS refuses access,
    ///   or whatever `body` throws.
    private func withAccess<T>(to destination: URL?, perform body: () throws -> T) throws -> T {
        guard let destination else { return try body() }
        do {
            return try SecurityScopedAccess.withAccess(to: destination, using: access) { _ in try body() }
        } catch is SaveLocationError {
            throw DerivedSessionError.unreadable
        }
    }
}
