//
//  TranscriptFileStoring.swift
//  ScribeKit
//

import Foundation
import Synchronization

/// The filesystem operations a transcript session needs, and nothing else.
///
/// Narrow on purpose: creating a directory, asking whether a name is taken,
/// and opening a file for appending is the whole of it. Keeping it this small
/// means the writer's ordering, naming and formatting can be tested against a
/// double that fails on demand, while the production implementation stays a
/// thin pass-through to `FileManager` with no logic of its own.
nonisolated protocol TranscriptFileStoring: Sendable {
    /// Reports whether anything already exists at a location.
    ///
    /// - Parameter url: The location to check.
    /// - Returns: `true` when a file or directory is there.
    func exists(at url: URL) -> Bool

    /// Creates one directory, failing if it is already there.
    ///
    /// Intermediate directories are not created: the parent is the folder the
    /// user chose, and a session that cannot find it should say so rather than
    /// invent a path.
    ///
    /// - Parameter url: Where to create the directory.
    /// - Throws: The system error when creation fails.
    func createDirectory(at url: URL) throws

    /// Creates an empty file and opens it for appending.
    ///
    /// - Parameter url: Where to create the file.
    /// - Returns: A handle that appends to it.
    /// - Throws: The system error when the file cannot be created or opened.
    func createFile(at url: URL) throws -> any TranscriptFileAppending
}

/// An open file a transcript is appended to.
///
/// Appending rather than rewriting is the point: a transcript grows for hours,
/// and rewriting it for each finalised sentence would make the cost of a
/// meeting grow with its length.
nonisolated protocol TranscriptFileAppending: Sendable {
    /// Adds text to the end of the file.
    ///
    /// - Parameter text: The text to append, encoded as UTF-8.
    /// - Throws: The system error when the write fails.
    func append(_ text: String) throws

    /// Asks the system to commit what has been written to the storage device.
    ///
    /// - Throws: The system error when the flush fails.
    func synchronize() throws

    /// Closes the file. Closing an already closed file does nothing.
    ///
    /// - Throws: The system error when closing fails.
    func close() throws
}

/// Transcript files as `FileManager` and `FileHandle` provide them.
nonisolated struct FileManagerTranscriptFileStore: TranscriptFileStoring {
    /// Creates the system-backed store.
    init() {}

    func exists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func createFile(at url: URL) throws -> any TranscriptFileAppending {
        guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileHandleTranscriptFile(handle: try FileHandle(forWritingTo: url))
    }
}

/// A transcript file backed by an open `FileHandle`.
///
/// The handle is held under a mutex because `FileHandle` is not `Sendable` and
/// the file outlives the call that created it. In practice the writer actor
/// serialises every call, so the lock is never contended; it is here so the
/// type is safe to hand across isolation without an unchecked claim.
nonisolated final class FileHandleTranscriptFile: TranscriptFileAppending {
    private let handle: Mutex<FileHandle?>

    /// Wraps an open handle.
    ///
    /// - Parameter handle: A handle opened for writing, positioned at the end
    ///   of an empty file.
    init(handle: FileHandle) {
        self.handle = Mutex(handle)
    }

    func append(_ text: String) throws {
        try handle.withLock { handle in
            guard let handle else { throw CocoaError(.fileWriteUnknown) }
            try handle.write(contentsOf: Data(text.utf8))
        }
    }

    func synchronize() throws {
        try handle.withLock { handle in
            try handle?.synchronize()
        }
    }

    func close() throws {
        try handle.withLock { handle in
            defer { handle = nil }
            try handle?.close()
        }
    }
}
