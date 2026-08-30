//
//  HistoryStore.swift
//  ScribeKit
//

import Foundation

/// A reason a session directory could not be turned into a history entry.
///
/// Every case describes something history found and left exactly as it was.
/// None of them is a licence to repair, rewrite or remove anything.
nonisolated enum HistoryError: Error, Equatable, Sendable {
    /// The save folder could not be opened or listed.
    case destinationUnavailable

    /// No save folder is remembered, so there is nothing to look in.
    case noDestination

    /// `session.json` is there but could not be read from the filesystem.
    case metadataUnreadable

    /// `session.json` was read but is not a record this build can interpret.
    case metadataMalformed

    /// `session.json` announces a schema version this build does not know.
    case unsupportedSchemaVersion(Int)

    /// The record names a transcript that is not in the folder.
    case transcriptMissing

    /// The transcript is there but could not be read.
    case transcriptUnreadable
}

extension HistoryError: LocalizedError {
    /// A message for the History screen that says what ScribeKit found,
    /// without quoting a raw OS error code and without implying a repair.
    var errorDescription: String? {
        switch self {
        case .destinationUnavailable:
            "ScribeKit could not open the save folder, so it could not list past meetings."
        case .noDestination:
            "No save folder is chosen yet, so there are no meetings to list."
        case .metadataUnreadable:
            "This meeting's session record could not be read, so it is listed only by its folder name."
        case .metadataMalformed:
            "This meeting's session record is damaged and was left untouched. Its transcript is unaffected."
        case let .unsupportedSchemaVersion(version):
            "This meeting's session record was written by a newer version of ScribeKit (format \(version)) "
            + "and was left untouched."
        case .transcriptMissing:
            "This meeting's session record refers to a transcript that is not in the folder."
        case .transcriptUnreadable:
            "This meeting's transcript could not be read."
        }
    }
}

/// The filesystem operations history needs, and nothing else.
///
/// The boundary is read-only by construction. There is no method here that
/// creates, replaces, appends to or deletes anything, so "opening History
/// leaves every artifact byte-identical" is a property of the type system
/// rather than a rule someone has to remember. Recovery keeps its own
/// ``SessionRecoveryStoring``, which does have a write side, because recording
/// an interruption is a thing recovery legitimately does and history never
/// does.
///
/// Nothing here starts or stops security-scoped access; ``HistoryService``
/// owns that, so a scan cannot open a claim that something else has to close.
nonisolated protocol HistoryStoring: Sendable {

    /// Lists the immediate subdirectories of the user's save folder.
    ///
    /// One level, never a recursive walk: a session directory is a direct
    /// child of the folder the user chose, and nothing else in the user's
    /// filesystem is ScribeKit's to enumerate.
    ///
    /// - Parameter destination: The folder the user chose.
    /// - Returns: The subdirectories, in a stable order.
    /// - Throws: ``HistoryError/destinationUnavailable`` when the folder
    ///   cannot be listed.
    func sessionDirectories(in destination: URL) throws -> [URL]

    /// Reads the bytes of a session record.
    ///
    /// Absence is an answer rather than a failure: a directory with no record
    /// may still be a transcript ScribeKit wrote before records existed.
    ///
    /// - Parameter url: The record's location.
    /// - Returns: Its bytes, or `nil` when there is no record there.
    /// - Throws: ``HistoryError/metadataUnreadable`` when a record is present
    ///   but cannot be read.
    func metadataData(at url: URL) throws -> Data?

    /// Reads the bytes of a session's review sidecar.
    ///
    /// Absence and failure are the same answer, deliberately: review metadata
    /// is optional, and a session without readable review information is
    /// simply a session with none. Nothing about it stops the meeting from
    /// being listed, opened or searched.
    ///
    /// - Parameter url: The sidecar's location.
    /// - Returns: Its bytes, or `nil` when there is none or it cannot be read.
    func reviewData(at url: URL) -> Data?

    /// Describes a file without opening it.
    ///
    /// - Parameter url: The file's location.
    /// - Returns: Its size and modification date, or `nil` when it is not
    ///   there or cannot be examined.
    func fileInfo(at url: URL) -> SessionFileInfo?

    /// Reads a transcript's text.
    ///
    /// Reading is safe while a meeting is being written: the transcript writer
    /// only ever appends, takes no lock, and never rewrites what is already in
    /// the file, so a read during a meeting sees a prefix of the finished
    /// document rather than a torn one.
    ///
    /// - Parameter url: The transcript's location.
    /// - Returns: Its contents.
    /// - Throws: ``HistoryError/transcriptMissing`` when it is not there, or
    ///   ``HistoryError/transcriptUnreadable`` when it cannot be read or
    ///   decoded.
    func readTranscript(at url: URL) throws -> String
}

/// Session artifacts as `FileManager` provides them, for reading only.
nonisolated struct FileManagerHistoryStore: HistoryStoring {

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
            throw HistoryError.destinationUnavailable
        }
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func metadataData(at url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw HistoryError.metadataUnreadable
        }
    }

    func reviewData(at url: URL) -> Data? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try? Data(contentsOf: url)
    }

    func fileInfo(at url: URL) -> SessionFileInfo? {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path),
              FileManager.default.isReadableFile(atPath: path),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize
        else { return nil }
        return SessionFileInfo(byteCount: size, modifiedAt: values.contentModificationDate)
    }

    func readTranscript(at url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw HistoryError.transcriptMissing
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw HistoryError.transcriptUnreadable
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw HistoryError.transcriptUnreadable
        }
        return text
    }
}
