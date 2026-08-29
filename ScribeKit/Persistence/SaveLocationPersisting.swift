//
//  SaveLocationPersisting.swift
//  ScribeKit
//

import Foundation

/// Remembers the folder the user chose for meeting artifacts, so the choice
/// survives relaunch.
///
/// The protocol exists so presentation code depends on "a save location can be
/// remembered" rather than on how macOS grants a sandboxed process durable
/// access. The production implementation stores a security-scoped bookmark;
/// tests substitute an in-memory double, so no bookmark, sandbox permission or
/// real folder is needed to exercise the states around it.
nonisolated protocol SaveLocationPersisting {
    /// Remembers a directory the user selected.
    ///
    /// - Parameter url: The directory to remember. It must come from a user
    ///   selection; a path assembled by ScribeKit carries no access rights.
    /// - Throws: ``SaveLocationError`` when durable access cannot be recorded.
    func save(_ url: URL) throws

    /// Restores the remembered directory.
    ///
    /// Implementations validate the directory before returning it, so a caller
    /// receives either a directory it can use or an error explaining why it
    /// cannot. Access is not left open by this call.
    ///
    /// - Returns: The remembered directory, or `nil` when none was stored.
    /// - Throws: ``SaveLocationError`` when something was stored but cannot be
    ///   turned back into a usable directory.
    func restore() throws -> URL?

    /// Forgets the remembered directory.
    ///
    /// - Throws: ``SaveLocationError`` when the stored data cannot be removed.
    func clear() throws
}

/// A reason a save location could not be remembered, restored or forgotten.
///
/// The reason is what the interface explains to the user; ``underlying`` keeps
/// the originating system error for diagnostics, and is deliberately not part
/// of equality so callers and tests can match on the reason alone.
struct SaveLocationError: Error {
    /// What went wrong, in ScribeKit's own terms rather than the system's.
    enum Reason: Equatable, Sendable {
        /// Durable access to the selected directory could not be recorded.
        case bookmarkCreationFailed

        /// Stored access data could not be turned back into a directory,
        /// typically because the folder was deleted or its volume is absent.
        case bookmarkResolutionFailed

        /// Stored access data was out of date and could not be renewed.
        case staleBookmarkNotRefreshed

        /// The system refused access to the restored directory.
        case accessDenied

        /// The restored location is missing, or is no longer a directory.
        case directoryUnavailable

        /// The stored data is not something this app wrote.
        case malformedStoredData
    }

    /// What went wrong.
    let reason: Reason

    /// The system error behind ``reason``, when there was one.
    let underlying: Error?

    /// Creates an error.
    ///
    /// - Parameters:
    ///   - reason: What went wrong.
    ///   - underlying: The originating system error, kept for diagnostics.
    init(_ reason: Reason, underlying: Error? = nil) {
        self.reason = reason
        self.underlying = underlying
    }
}

extension SaveLocationError: LocalizedError {
    /// A message for the setup screen that explains the situation without
    /// quoting a raw OS error code.
    var errorDescription: String? {
        switch reason {
        case .bookmarkCreationFailed:
            "ScribeKit could not remember this folder, so it will need to be chosen again next launch."
        case .bookmarkResolutionFailed:
            "The saved folder could not be found. It may have been deleted, renamed or moved to a disk that is not connected."
        case .staleBookmarkNotRefreshed:
            "The saved folder moved and ScribeKit could not renew its access. Choose the folder again."
        case .accessDenied:
            "macOS did not grant ScribeKit access to the saved folder. Choose the folder again to restore permission."
        case .directoryUnavailable:
            "The saved location is no longer an available folder. Choose another one."
        case .malformedStoredData:
            "The saved folder setting was unreadable and has been ignored. Choose the folder again."
        }
    }
}
