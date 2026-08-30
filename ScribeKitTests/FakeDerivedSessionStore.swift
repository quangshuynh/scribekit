//
//  FakeDerivedSessionStore.swift
//  ScribeKitTests
//

import Foundation
import Synchronization
@testable import ScribeKit

/// An in-memory derived sidecar: the bytes at one session's `derived.json`,
/// and a switch that makes writing it fail.
///
/// Bytes rather than a value so a test can plant a damaged record or one from
/// a schema this build has never seen, which is what a folder actually holds
/// when a sidecar goes wrong.
nonisolated final class FakeDerivedSessionStore: DerivedSessionStoring, @unchecked Sendable {

    private struct State {
        var files: [String: Data] = [:]
        var writeFails = false
        var writes = 0
    }

    private let state = Mutex(State())

    /// Creates a store holding no sidecar at all.
    init() {}

    // MARK: - Arrangement

    /// Plants the raw bytes of a session's sidecar.
    ///
    /// - Parameters:
    ///   - data: The sidecar's contents, which need not be valid.
    ///   - layout: The session it belongs to.
    func plant(_ data: Data, for layout: SessionArtifactLayout) {
        state.withLock { $0.files[Self.key(layout)] = data }
    }

    /// Makes every write fail, as a full or read-only volume would.
    ///
    /// - Parameter fails: Whether writing fails.
    func failWrites(_ fails: Bool = true) { state.withLock { $0.writeFails = fails } }

    // MARK: - Observation

    /// How many writes have been attempted, so a test can prove typing does
    /// not reach the disk.
    var writeCount: Int { state.withLock { $0.writes } }

    /// The bytes currently stored for a session, so a test can prove a
    /// refused write left them exactly as they were.
    ///
    /// - Parameter layout: The session.
    /// - Returns: The bytes, or `nil` when there is no sidecar.
    func storedBytes(for layout: SessionArtifactLayout) -> Data? {
        state.withLock { $0.files[Self.key(layout)] }
    }

    // MARK: - DerivedSessionStoring

    func readDerivedState(
        from layout: SessionArtifactLayout,
        sessionID: UUID
    ) throws -> DerivedSessionState? {
        guard let state = try storedState(for: layout) else { return nil }
        guard state.sessionID == sessionID else { throw DerivedSessionError.sessionMismatch }
        return state
    }

    @discardableResult
    func writeDerivedState(
        _ newState: DerivedSessionState,
        to layout: SessionArtifactLayout,
        expectedRevision: UUID?,
        at date: Date
    ) throws -> DerivedSessionState {
        let onDisk = try storedState(for: layout)
        guard onDisk?.revision == expectedRevision else { throw DerivedSessionError.staleWrite }

        let written = newState.preparedForWrite(at: date)
        let data = try written.encoded()
        try state.withLock { state in
            state.writes += 1
            if state.writeFails { throw DerivedSessionError.writeFailed }
            state.files[Self.key(layout)] = data
        }
        return written
    }

    /// Decodes whatever is planted for a session.
    ///
    /// - Parameter layout: The session.
    /// - Returns: The record, or `nil` when there is no sidecar.
    /// - Throws: Whatever decoding refuses.
    private func storedState(for layout: SessionArtifactLayout) throws -> DerivedSessionState? {
        guard let data = state.withLock({ $0.files[Self.key(layout)] }) else { return nil }
        return try DerivedSessionState.decoded(from: data)
    }

    /// The key a session is stored under.
    ///
    /// - Parameter layout: The session.
    /// - Returns: Its sidecar's path.
    private static func key(_ layout: SessionArtifactLayout) -> String {
        layout.derivedURL.path(percentEncoded: false)
    }
}
