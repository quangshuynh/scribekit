//
//  SessionRecoveryStore.swift
//  ScribeKit
//

import Foundation

/// A reason a session record could not be written, found, read or acted on.
///
/// The cases exist so a damaged session is described rather than guessed at.
/// None of them is a licence to repair anything: a malformed record is
/// reported and left exactly as it is, because it may be the only evidence of
/// what happened to a meeting.
nonisolated enum SessionRecoveryError: Error, Equatable, Sendable {
    /// The save folder could not be opened or is no longer a directory, so
    /// nothing could be looked for in it.
    case destinationUnavailable

    /// The session directory named by a record is gone.
    case sessionDirectoryMissing

    /// The session directory holds no `session.json`.
    case metadataMissing

    /// `session.json` exists but could not be read from the filesystem.
    case metadataUnreadable

    /// `session.json` was read but is not a record this build can interpret.
    case metadataMalformed

    /// `session.json` announces a schema version this build does not know.
    case unsupportedSchemaVersion(Int)

    /// The record names a transcript that is not there.
    case transcriptMissing

    /// The transcript is there but could not be read.
    case transcriptUnreadable

    /// The record could not be written or replaced.
    case metadataWriteFailed

    /// The interruption note could not be appended to the transcript.
    case transcriptAnnotationFailed
}

extension SessionRecoveryError: LocalizedError {
    /// A message for the recovery section that says what ScribeKit found,
    /// without quoting a raw OS error code and without implying a repair it
    /// will not attempt.
    var errorDescription: String? {
        switch self {
        case .destinationUnavailable:
            "ScribeKit could not open the save folder, so it could not check for an unfinished meeting."
        case .sessionDirectoryMissing:
            "The meeting folder is no longer in the save location."
        case .metadataMissing:
            "This meeting folder has no ScribeKit session record."
        case .metadataUnreadable:
            "This meeting's session record could not be read."
        case .metadataMalformed:
            "This meeting's session record is damaged and was left untouched. Its transcript is unaffected."
        case let .unsupportedSchemaVersion(version):
            "This meeting's session record was written by a newer version of ScribeKit (format \(version)) and was left untouched."
        case .transcriptMissing:
            "This meeting's session record refers to a transcript that is not in the folder."
        case .transcriptUnreadable:
            "This meeting's transcript could not be read."
        case .metadataWriteFailed:
            "The session record could not be updated."
        case .transcriptAnnotationFailed:
            "The interruption note could not be added to the transcript."
        }
    }
}

/// What ScribeKit can tell about one of a session's files without opening it.
///
/// Recovery needs to know that the transcript is there and when it last grew,
/// and the same two facts about a retained recording; it needs the contents of
/// neither, and reading a multi-hour transcript or a gigabyte of audio at
/// launch to answer a question the file's own attributes answer would be work
/// for nothing.
nonisolated struct SessionFileInfo: Equatable, Sendable {
    /// The file's size in bytes.
    let byteCount: Int

    /// When the file was last written, as the filesystem records it.
    ///
    /// This is the closest honest answer to "when did the meeting last save
    /// something", and it is a measured fact rather than a time ScribeKit
    /// wrote down and hoped stayed true.
    let modifiedAt: Date?

    /// Creates the description.
    ///
    /// - Parameters:
    ///   - byteCount: The file's size in bytes.
    ///   - modifiedAt: When the file was last written.
    init(byteCount: Int, modifiedAt: Date?) {
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
    }
}

/// The filesystem operations session recovery needs, and nothing else.
///
/// Narrow for the same reason ``TranscriptFileStoring`` is: the policy above
/// it — what counts as an unfinished meeting, what order things are written
/// in, what is refused — is then testable against a double that fails on
/// demand, while the production implementation stays a pass-through to
/// `FileManager` with no decisions of its own.
///
/// Nothing here starts or stops security-scoped access. The caller owns that,
/// so a scan and a write cannot each open a claim that the other forgets to
/// balance.
nonisolated protocol SessionRecoveryStoring: Sendable {

    /// Lists the immediate subdirectories of the user's save folder.
    ///
    /// One level, never a recursive walk: a session directory is a direct
    /// child of the folder the user chose, and nothing else in the user's
    /// filesystem is ScribeKit's to enumerate.
    ///
    /// - Parameter destination: The folder the user chose.
    /// - Returns: The subdirectories, in a stable order.
    /// - Throws: ``SessionRecoveryError/destinationUnavailable`` when the
    ///   folder cannot be listed.
    func sessionDirectories(in destination: URL) throws -> [URL]

    /// Reads a session's record.
    ///
    /// - Parameter layout: Where the session's artifacts live.
    /// - Returns: The record.
    /// - Throws: ``SessionRecoveryError`` describing a missing, unreadable,
    ///   damaged or unsupported record.
    func loadMetadata(from layout: SessionArtifactLayout) throws -> SessionRecoveryMetadata

    /// Writes a session's record, replacing any previous one atomically.
    ///
    /// The metadata directory is created if it is not there. A partially
    /// written record must never become the normal state after a crash, so the
    /// replacement is all-or-nothing.
    ///
    /// - Parameters:
    ///   - metadata: The record to write.
    ///   - layout: Where the session's artifacts live.
    /// - Throws: ``SessionRecoveryError/metadataWriteFailed`` when the record
    ///   cannot be written.
    func writeMetadata(_ metadata: SessionRecoveryMetadata, to layout: SessionArtifactLayout) throws

    /// Describes a transcript without reading its text.
    ///
    /// - Parameter url: The transcript's location.
    /// - Returns: Its size and modification date.
    /// - Throws: ``SessionRecoveryError/transcriptMissing`` when it is not
    ///   there, or ``SessionRecoveryError/transcriptUnreadable`` when it
    ///   cannot be examined.
    func transcriptInfo(at url: URL) throws -> SessionFileInfo

    /// Describes a retained audio file without opening it.
    ///
    /// Absence is an answer rather than a failure: a meeting killed before its
    /// first captured buffer has a record that names an audio file and no file
    /// beside it, and that is a fact about the meeting, not a damaged session.
    /// Nothing here decodes the recording or claims it will play.
    ///
    /// - Parameter url: The recording's location.
    /// - Returns: Its size and modification date, or `nil` when it is not
    ///   there or cannot be examined.
    func audioInfo(at url: URL) -> SessionFileInfo?

    /// Appends text to the end of an existing transcript.
    ///
    /// Appending is the only modification recovery makes to a transcript, and
    /// it happens once, at the user's request. Nothing already in the file is
    /// read, rewritten or reordered.
    ///
    /// - Parameters:
    ///   - text: The Markdown to append.
    ///   - url: The transcript's location.
    /// - Throws: ``SessionRecoveryError/transcriptAnnotationFailed`` when the
    ///   append does not reach the file.
    func appendToTranscript(_ text: String, at url: URL) throws
}

/// Session records as `FileManager` and `FileHandle` provide them.
nonisolated struct FileManagerSessionRecoveryStore: SessionRecoveryStoring {

    /// Creates the system-backed store.
    init() {}

    func sessionDirectories(in destination: URL) throws -> [URL] {
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        } catch {
            throw SessionRecoveryError.destinationUnavailable
        }
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func loadMetadata(from layout: SessionArtifactLayout) throws -> SessionRecoveryMetadata {
        let url = layout.metadataURL
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw SessionRecoveryError.metadataMissing
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SessionRecoveryError.metadataUnreadable
        }
        return try SessionRecoveryMetadata.decoded(from: data)
    }

    func writeMetadata(_ metadata: SessionRecoveryMetadata, to layout: SessionArtifactLayout) throws {
        let data = try metadata.encoded()
        do {
            try FileManager.default.createDirectory(
                at: layout.metadataDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: layout.metadataURL, options: [.atomic])
        } catch {
            throw SessionRecoveryError.metadataWriteFailed
        }
    }

    func transcriptInfo(at url: URL) throws -> SessionFileInfo {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw SessionRecoveryError.transcriptMissing
        }
        guard let info = Self.fileInfo(at: url) else {
            throw SessionRecoveryError.transcriptUnreadable
        }
        return info
    }

    func audioInfo(at url: URL) -> SessionFileInfo? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return Self.fileInfo(at: url)
    }

    /// Reads a file's size and modification date from the filesystem.
    ///
    /// - Parameter url: The file to describe.
    /// - Returns: Its size and modification date, or `nil` when it cannot be
    ///   examined.
    private static func fileInfo(at url: URL) -> SessionFileInfo? {
        guard FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize
        else { return nil }
        return SessionFileInfo(byteCount: size, modifiedAt: values.contentModificationDate)
    }

    func appendToTranscript(_ text: String, at url: URL) throws {
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.synchronize()
        } catch {
            throw SessionRecoveryError.transcriptAnnotationFailed
        }
    }
}
