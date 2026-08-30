//
//  FakeHistoryStore.swift
//  ScribeKitTests
//

import Foundation
import Synchronization
@testable import ScribeKit

/// An in-memory save folder for history: session directories, the raw bytes of
/// their records, their transcripts and the recordings beside them.
///
/// Records are held as bytes rather than as decoded values so a test can plant
/// truncated JSON or a record from a schema this build has never seen, which
/// is exactly what a damaged folder contains and exactly what a typed double
/// could not represent.
nonisolated final class FakeHistoryStore: HistoryStoring, @unchecked Sendable {

    private struct State {
        var directories: [String: [URL]] = [:]
        var metadata: [String: Data] = [:]
        var files: [String: SessionFileInfo] = [:]
        var transcripts: [String: String] = [:]
        var review: [String: Data] = [:]
        var unreadableMetadata: Set<String> = []
        var unreadableTranscripts: Set<String> = []
        var listingFails = false
        var reads = 0
    }

    private let state = Mutex(State())

    /// Creates an empty save folder.
    init() {}

    // MARK: - Arrangement

    /// Adds a session directory holding a record and a transcript.
    ///
    /// - Parameters:
    ///   - directory: The session directory.
    ///   - destination: The save folder it sits in.
    ///   - metadata: The record to place in it, or `nil` for a directory with
    ///     no ScribeKit record at all.
    ///   - transcript: The transcript's text, or `nil` when the directory has
    ///     no transcript.
    ///   - transcriptInfo: The transcript's size and modification date.
    func addSession(
        _ directory: URL,
        in destination: URL,
        metadata: SessionRecoveryMetadata?,
        transcript: String?,
        transcriptInfo: SessionFileInfo? = nil
    ) throws {
        try addSession(
            directory,
            in: destination,
            rawMetadata: metadata.map { try $0.encoded() },
            transcript: transcript,
            transcriptInfo: transcriptInfo
        )
    }

    /// Adds a session directory holding exactly these bytes as its record.
    ///
    /// - Parameters:
    ///   - directory: The session directory.
    ///   - destination: The save folder it sits in.
    ///   - rawMetadata: The bytes of `session.json`, which need not be valid.
    ///   - transcript: The transcript's text, or `nil` when there is none.
    ///   - transcriptInfo: The transcript's size and modification date.
    func addSession(
        _ directory: URL,
        in destination: URL,
        rawMetadata: Data?,
        transcript: String?,
        transcriptInfo: SessionFileInfo? = nil
    ) throws {
        let layout = SessionArtifactLayout(directory: directory)
        state.withLock { state in
            state.directories[Self.key(destination), default: []].append(directory)
            if let rawMetadata { state.metadata[Self.key(layout.metadataURL)] = rawMetadata }
            if let transcript {
                state.transcripts[Self.key(layout.transcriptURL)] = transcript
                state.files[Self.key(layout.transcriptURL)] = transcriptInfo
                    ?? SessionFileInfo(byteCount: transcript.utf8.count, modifiedAt: nil)
            }
        }
    }

    /// Adds a plain directory with no ScribeKit artifacts in it.
    ///
    /// - Parameters:
    ///   - directory: The directory.
    ///   - destination: The save folder it sits in.
    func addDirectory(_ directory: URL, in destination: URL) {
        state.withLock { $0.directories[Self.key(destination), default: []].append(directory) }
    }

    /// Adds a file beside a transcript, such as a retained recording.
    ///
    /// - Parameters:
    ///   - info: The file's size and modification date.
    ///   - url: Where it is.
    func addFile(_ info: SessionFileInfo, at url: URL) {
        state.withLock { $0.files[Self.key(url)] = info }
    }

    /// Makes listing the save folder fail, as an unreachable volume would.
    /// Plants the raw bytes of a session's review sidecar.
    ///
    /// Bytes rather than a value so a test can plant a damaged sidecar, which
    /// is what a folder actually holds when one goes wrong.
    ///
    /// - Parameters:
    ///   - data: The sidecar's contents.
    ///   - directory: The session directory it belongs to.
    func addReview(_ data: Data, to directory: URL) {
        state.withLock {
            $0.review[Self.key(SessionArtifactLayout(directory: directory).reviewURL)] = data
        }
    }

    func failListing() { state.withLock { $0.listingFails = true } }

    /// Makes one session record present but impossible to read.
    ///
    /// - Parameter url: The record's location.
    func makeMetadataUnreadable(at url: URL) {
        state.withLock { _ = $0.unreadableMetadata.insert(Self.key(url)) }
    }

    /// Makes one transcript present but impossible to read.
    ///
    /// - Parameter url: The transcript's location.
    func makeTranscriptUnreadable(at url: URL) {
        state.withLock { _ = $0.unreadableTranscripts.insert(Self.key(url)) }
    }

    // MARK: - Observation

    /// How many transcripts have been read, so a test can prove a load reads
    /// each one once and a search reads none.
    var readCount: Int { state.withLock { $0.reads } }

    /// The raw bytes currently stored for a session, so a test can prove a
    /// damaged record was left exactly as it was.
    ///
    /// - Parameter directory: The session directory.
    /// - Returns: The bytes, or `nil` when nothing is stored.
    func storedBytes(in directory: URL) -> Data? {
        state.withLock { $0.metadata[Self.key(SessionArtifactLayout(directory: directory).metadataURL)] }
    }

    // MARK: - HistoryStoring

    func sessionDirectories(in destination: URL) throws -> [URL] {
        try state.withLock { state in
            if state.listingFails { throw HistoryError.destinationUnavailable }
            return (state.directories[Self.key(destination)] ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
    }

    func metadataData(at url: URL) throws -> Data? {
        try state.withLock { state in
            guard let data = state.metadata[Self.key(url)] else { return nil }
            if state.unreadableMetadata.contains(Self.key(url)) { throw HistoryError.metadataUnreadable }
            return data
        }
    }

    func reviewData(at url: URL) -> Data? {
        state.withLock { $0.review[Self.key(url)] }
    }

    func fileInfo(at url: URL) -> SessionFileInfo? {
        state.withLock { $0.files[Self.key(url)] }
    }

    func readTranscript(at url: URL) throws -> String {
        try state.withLock { state in
            if state.unreadableTranscripts.contains(Self.key(url)) {
                throw HistoryError.transcriptUnreadable
            }
            guard let text = state.transcripts[Self.key(url)] else {
                throw HistoryError.transcriptMissing
            }
            state.reads += 1
            return text
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
