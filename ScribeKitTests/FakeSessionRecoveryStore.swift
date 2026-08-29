//
//  FakeSessionRecoveryStore.swift
//  ScribeKitTests
//

import Foundation
import Synchronization
@testable import ScribeKit

/// An in-memory save folder: session directories, the raw bytes of their
/// records, and the transcripts beside them.
///
/// Records are held as bytes rather than as decoded values so a test can plant
/// truncated JSON or a record from a schema this build has never seen, which
/// is exactly what a damaged folder contains and exactly what a typed double
/// could not represent.
nonisolated final class FakeSessionRecoveryStore: SessionRecoveryStoring, @unchecked Sendable {

    private struct State {
        var directories: [String: [URL]] = [:]
        var metadata: [String: Data] = [:]
        var transcripts: [String: TranscriptFileInfo] = [:]
        var unreadableTranscripts: Set<String> = []
        var appends: [(url: URL, text: String)] = []
        var writes: [SessionRecoveryMetadata] = []
        var listingFails = false
        var writeFails = false
        var appendFails = false
        var onWrite: (@Sendable (SessionRecoveryMetadata) -> Void)?
    }

    private let state = Mutex(State())

    /// Creates an empty save folder.
    init() {}

    // MARK: - Arrangement

    /// Adds a session directory holding a decodable record and a transcript.
    ///
    /// - Parameters:
    ///   - directory: The session directory.
    ///   - destination: The save folder it sits in.
    ///   - metadata: The record to place in it, or `nil` for a directory with
    ///     no ScribeKit record at all.
    ///   - transcript: The transcript's description, or `nil` when the record
    ///     names a transcript that is not there.
    func addSession(
        _ directory: URL,
        in destination: URL,
        metadata: SessionRecoveryMetadata?,
        transcript: TranscriptFileInfo? = TranscriptFileInfo(byteCount: 512, modifiedAt: nil)
    ) throws {
        try addSession(
            directory,
            in: destination,
            rawMetadata: metadata.map { try $0.encoded() },
            transcript: transcript
        )
    }

    /// Adds a session directory holding exactly these bytes as its record.
    ///
    /// - Parameters:
    ///   - directory: The session directory.
    ///   - destination: The save folder it sits in.
    ///   - rawMetadata: The bytes of `session.json`, which need not be valid.
    ///   - transcript: The transcript's description, or `nil` when there is
    ///     none.
    func addSession(
        _ directory: URL,
        in destination: URL,
        rawMetadata: Data?,
        transcript: TranscriptFileInfo? = TranscriptFileInfo(byteCount: 512, modifiedAt: nil)
    ) throws {
        let layout = SessionArtifactLayout(directory: directory)
        state.withLock { state in
            state.directories[Self.key(destination), default: []].append(directory)
            if let rawMetadata { state.metadata[Self.key(layout.metadataURL)] = rawMetadata }
            if let transcript { state.transcripts[Self.key(layout.transcriptURL)] = transcript }
        }
    }

    /// Makes listing the save folder fail, as an unreachable volume would.
    func failListing() { state.withLock { $0.listingFails = true } }

    /// Makes every record write fail.
    func failWrites() { state.withLock { $0.writeFails = true } }

    /// Makes every transcript append fail.
    func failAppends() { state.withLock { $0.appendFails = true } }

    /// Makes one transcript present but impossible to read.
    ///
    /// - Parameter url: The transcript's location.
    func makeTranscriptUnreadable(at url: URL) {
        state.withLock { _ = $0.unreadableTranscripts.insert(Self.key(url)) }
    }

    /// Observes each record write as it happens, so a test can check what the
    /// rest of the world looked like at that moment.
    ///
    /// - Parameter body: Called with the record about to be stored.
    func observeWrites(_ body: @escaping @Sendable (SessionRecoveryMetadata) -> Void) {
        state.withLock { $0.onWrite = body }
    }

    // MARK: - Observation

    /// Every record written, in order.
    var writes: [SessionRecoveryMetadata] { state.withLock { $0.writes } }

    /// The record currently stored for a session, if any.
    ///
    /// - Parameter directory: The session directory.
    /// - Returns: The decoded record, or `nil` when none is stored or the
    ///   stored bytes are not a readable record.
    func storedMetadata(in directory: URL) -> SessionRecoveryMetadata? {
        let key = Self.key(SessionArtifactLayout(directory: directory).metadataURL)
        guard let data = state.withLock({ $0.metadata[key] }) else { return nil }
        return try? SessionRecoveryMetadata.decoded(from: data)
    }

    /// The raw bytes currently stored for a session, so a test can prove a
    /// damaged record was left exactly as it was.
    ///
    /// - Parameter directory: The session directory.
    /// - Returns: The bytes, or `nil` when nothing is stored.
    func storedBytes(in directory: URL) -> Data? {
        state.withLock { $0.metadata[Self.key(SessionArtifactLayout(directory: directory).metadataURL)] }
    }

    /// Everything appended to transcripts, in order.
    var appends: [(url: URL, text: String)] { state.withLock { $0.appends } }

    // MARK: - SessionRecoveryStoring

    func sessionDirectories(in destination: URL) throws -> [URL] {
        try state.withLock { state in
            if state.listingFails { throw SessionRecoveryError.destinationUnavailable }
            return (state.directories[Self.key(destination)] ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
    }

    func loadMetadata(from layout: SessionArtifactLayout) throws -> SessionRecoveryMetadata {
        guard let data = state.withLock({ $0.metadata[Self.key(layout.metadataURL)] }) else {
            throw SessionRecoveryError.metadataMissing
        }
        return try SessionRecoveryMetadata.decoded(from: data)
    }

    func writeMetadata(_ metadata: SessionRecoveryMetadata, to layout: SessionArtifactLayout) throws {
        let observer: (@Sendable (SessionRecoveryMetadata) -> Void)? = try state.withLock { state in
            if state.writeFails { throw SessionRecoveryError.metadataWriteFailed }
            return state.onWrite
        }
        observer?(metadata)

        let data = try metadata.encoded()
        state.withLock { state in
            state.metadata[Self.key(layout.metadataURL)] = data
            state.writes.append(metadata)
        }
    }

    func transcriptInfo(at url: URL) throws -> TranscriptFileInfo {
        try state.withLock { state in
            if state.unreadableTranscripts.contains(Self.key(url)) {
                throw SessionRecoveryError.transcriptUnreadable
            }
            guard let info = state.transcripts[Self.key(url)] else {
                throw SessionRecoveryError.transcriptMissing
            }
            return info
        }
    }

    func appendToTranscript(_ text: String, at url: URL) throws {
        try state.withLock { state in
            if state.appendFails { throw SessionRecoveryError.transcriptAnnotationFailed }
            state.appends.append((url: url, text: text))
        }
    }

    /// The key a URL is stored under, so paths built the same way match.
    ///
    /// - Parameter url: The location.
    /// - Returns: Its path.
    private static func key(_ url: URL) -> String {
        url.path(percentEncoded: false)
    }
}
