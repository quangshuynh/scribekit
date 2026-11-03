//
//  TranscriptExport.swift
//  ScribeKit
//

import Foundation
import OSLog

/// Why a transcript could not be exported.
///
/// Every case leaves the meeting exactly as it was. None quotes the
/// transcript, and none names a folder path, so a message can be shown or
/// logged without carrying anything the user said.
nonisolated enum TranscriptExportError: Error, Equatable, Sendable, LocalizedError {

    /// The meeting is still open, so its transcript is still growing and a
    /// copy would be a moment's prefix presented as the meeting.
    case meetingNotFinished

    /// The save folder could not be opened to read the transcript.
    case folderUnavailable

    /// The transcript is not where History found it.
    case transcriptMissing

    /// The transcript is there and could not be read.
    case transcriptUnreadable

    /// The destination is not a file location a copy can be written to.
    case invalidDestination

    /// The destination is the meeting's own transcript.
    case destinationIsTranscript

    /// The destination is inside a ScribeKit meeting folder, where a copy
    /// would add to or replace the meeting's own files.
    case destinationInsideMeeting

    /// The copy could not be written. Nothing was left at the destination.
    case writeFailed

    /// The copy was written and did not match the transcript, so it was
    /// removed.
    case verificationFailed

    /// The copy was written and could not be read back to confirm it, so it
    /// was left where the user put it.
    case couldNotConfirm
}

nonisolated extension TranscriptExportError {

    /// A message for the History screen that says what happened, what was
    /// left behind, and that the meeting is unchanged.
    var errorDescription: String? {
        switch self {
        case .meetingNotFinished:
            "This meeting is still open, so its transcript is still being written. Export it once it has finished."
        case .folderUnavailable:
            "ScribeKit could not open the save folder, so the transcript was not exported."
        case .transcriptMissing:
            "The transcript is no longer where History found it. It may have been moved, renamed or deleted. "
            + "Refresh History and try again."
        case .transcriptUnreadable:
            "The transcript could not be read, so it was not exported. It has been left exactly as it is."
        case .invalidDestination:
            "That location cannot hold a copy of the transcript. Choose a file name in a folder."
        case .destinationIsTranscript:
            "That is the meeting's own transcript. Choose another location; ScribeKit never replaces the original."
        case .destinationInsideMeeting:
            "That location is inside a ScribeKit meeting folder. Choose a location outside it, so the meeting's "
            + "own files stay as ScribeKit wrote them."
        case .writeFailed:
            "The copy could not be written to that location, and nothing was left there."
        case .verificationFailed:
            "The copy did not match the transcript when it was read back, so it was removed. Try again, or "
            + "choose another location."
        case .couldNotConfirm:
            "A copy was written but could not be read back to confirm it matches. Check it before relying on it."
        }
    }
}

/// A transcript copy that was written and confirmed.
nonisolated struct TranscriptExportResult: Equatable, Sendable {

    /// Where the copy is.
    let destination: URL

    /// How many bytes it holds, the same number the transcript held.
    let byteCount: Int

    /// Whether the transcript that was copied matched its seal.
    let integrity: TranscriptIntegrity
}

/// The filesystem operations an export needs, and nothing else.
///
/// The read side reaches the transcript and nothing beside it; the write side
/// reaches only the location the user picked in a save panel. Neither can
/// address a session record, a sidecar or a recording, so an export has no
/// path to any of them.
nonisolated protocol TranscriptExportFiling: Sendable {

    /// Reads a transcript's bytes, exactly as they are on disk.
    ///
    /// - Parameter url: The transcript.
    /// - Returns: Its bytes.
    /// - Throws: ``TranscriptExportError/transcriptMissing`` when it is not
    ///   there, or ``TranscriptExportError/transcriptUnreadable`` when it
    ///   cannot be read.
    func readTranscript(at url: URL) throws -> Data

    /// Whether a directory is a ScribeKit meeting folder: one holding a
    /// transcript or ScribeKit's own metadata directory.
    ///
    /// - Parameter url: The directory.
    /// - Returns: `true` when it is one.
    func isMeetingDirectory(_ url: URL) -> Bool

    /// Writes a copy in one atomic step, so a destination never holds part of
    /// a transcript.
    ///
    /// - Parameters:
    ///   - data: The bytes to write.
    ///   - url: The location the user picked.
    /// - Throws: The system error when the copy cannot be written.
    func writeCopy(_ data: Data, to url: URL) throws

    /// Reads a written copy back.
    ///
    /// - Parameter url: The copy.
    /// - Returns: Its bytes.
    /// - Throws: The system error when it cannot be read.
    func readCopy(at url: URL) throws -> Data

    /// Removes a copy that was written and found not to match.
    ///
    /// - Parameter url: The copy.
    /// - Throws: The system error when it cannot be removed.
    func removeCopy(at url: URL) throws
}

/// Export file operations as `FileManager` and `Data` provide them.
nonisolated struct FileManagerTranscriptExportFiles: TranscriptExportFiling {

    /// Creates the system-backed operations.
    init() {}

    func readTranscript(at url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw TranscriptExportError.transcriptMissing
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw TranscriptExportError.transcriptUnreadable
        }
    }

    func isMeetingDirectory(_ url: URL) -> Bool {
        let layout = SessionArtifactLayout(directory: url)
        return FileManager.default.fileExists(atPath: layout.transcriptURL.path(percentEncoded: false))
            || FileManager.default.fileExists(atPath: layout.metadataDirectory.path(percentEncoded: false))
    }

    func writeCopy(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }

    func readCopy(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func removeCopy(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

/// Copies a meeting's canonical transcript to a location the user chose.
///
/// The copy is the file, byte for byte: nothing is decoded, normalised,
/// re-encoded, summarised or annotated on the way, so Markdown, Unicode,
/// line endings and timestamps arrive exactly as `transcript.md` holds them.
/// The transcript is only read, and the meeting folder gains nothing: a
/// destination inside a meeting folder, or the transcript itself, is refused
/// before anything is written.
///
/// The write is atomic and the copy is read back and compared with the bytes
/// that were read, so a destination holds either the whole transcript or —
/// after a failure — whatever it held before. A copy that does not match is
/// removed rather than left to be mistaken for the transcript.
///
/// The integrity verdict is taken from the same read the copy is made from, so
/// a transcript that changed after History listed it is described as it is
/// now. A changed transcript is still exported: the user's file is theirs to
/// copy, and the verdict travels with the result so the screen can say so.
///
/// Everything is local. Nothing is uploaded, nothing is shared with another
/// service, and nothing about the transcript but its length is logged.
actor TranscriptExporter {

    private let files: any TranscriptExportFiling
    private let access: any SecurityScopedResourceAccessing

    /// Creates an exporter.
    ///
    /// - Parameters:
    ///   - files: How the transcript is read and the copy written. The system
    ///     by default; tests substitute a double that can fail on demand.
    ///   - access: How security-scoped access to the save folder is started
    ///     and stopped.
    init(
        files: any TranscriptExportFiling = FileManagerTranscriptExportFiles(),
        access: any SecurityScopedResourceAccessing = SystemSecurityScopedResourceAccess()
    ) {
        self.files = files
        self.access = access
    }

    /// The name a copy is offered under: the meeting folder's own name, which
    /// is already a date and a title slug, as a Markdown file.
    ///
    /// - Parameter session: The meeting.
    /// - Returns: A filename.
    nonisolated static func suggestedFilename(for session: HistorySession) -> String {
        let name = session.directory.lastPathComponent
        return (name.isEmpty ? "transcript" : name) + ".md"
    }

    /// Exports one meeting's transcript.
    ///
    /// - Parameters:
    ///   - session: The meeting, as History listed it.
    ///   - saveFolder: The save folder it was found in, whose security-scoped
    ///     access is held for exactly the length of the read.
    ///   - destination: Where the user asked for the copy.
    /// - Returns: The confirmed copy.
    /// - Throws: ``TranscriptExportError`` describing why nothing, or nothing
    ///   trustworthy, was written.
    func export(
        _ session: HistorySession,
        from saveFolder: URL?,
        to destination: URL
    ) throws -> TranscriptExportResult {
        guard session.status != .inProgress else { throw TranscriptExportError.meetingNotFinished }

        let data = try withFolderAccess(saveFolder) { () throws -> Data in
            try Self.validate(
                destination: destination,
                for: session,
                saveFolder: saveFolder,
                isMeetingDirectory: { files.isMeetingDirectory($0) }
            )
            return try files.readTranscript(at: session.transcriptURL)
        }
        let integrity = session.integrity(of: TranscriptSeal.sealing(data))

        do {
            try withFolderAccess(saveFolder) { try files.writeCopy(data, to: destination) }
        } catch {
            ScribeKitLog.history.error("Transcript export not written")
            throw TranscriptExportError.writeFailed
        }

        let copy: Data
        do {
            copy = try withFolderAccess(saveFolder) { try files.readCopy(at: destination) }
        } catch {
            ScribeKitLog.history.error("Transcript export written but not confirmed")
            throw TranscriptExportError.couldNotConfirm
        }
        guard copy == data else {
            try? withFolderAccess(saveFolder) { try files.removeCopy(at: destination) }
            ScribeKitLog.history.error("Transcript export did not match and was removed")
            throw TranscriptExportError.verificationFailed
        }

        ScribeKitLog.history.info("Transcript exported: \(data.count, privacy: .public) bytes")
        return TranscriptExportResult(destination: destination, byteCount: data.count, integrity: integrity)
    }

    /// Refuses a destination that would overwrite the transcript or add to a
    /// meeting folder.
    ///
    /// Paths are compared after symbolic links are resolved, so a link to the
    /// meeting folder is the meeting folder. A destination directly in the
    /// save folder is allowed — History lists folders, not files, so a copy
    /// there is not mistaken for a meeting — and one in any meeting folder
    /// below it is not.
    ///
    /// - Parameters:
    ///   - destination: Where the user asked for the copy.
    ///   - session: The meeting being exported.
    ///   - saveFolder: The save folder, when known.
    ///   - isMeetingDirectory: Whether a directory is a ScribeKit meeting
    ///     folder.
    /// - Throws: ``TranscriptExportError/invalidDestination``,
    ///   ``TranscriptExportError/destinationIsTranscript`` or
    ///   ``TranscriptExportError/destinationInsideMeeting``.
    nonisolated static func validate(
        destination: URL,
        for session: HistorySession,
        saveFolder: URL?,
        isMeetingDirectory: (URL) -> Bool
    ) throws {
        guard destination.isFileURL, !destination.hasDirectoryPath,
              !destination.lastPathComponent.isEmpty, destination.lastPathComponent != "/"
        else { throw TranscriptExportError.invalidDestination }

        let target = resolved(destination)
        if target == resolved(session.transcriptURL) {
            throw TranscriptExportError.destinationIsTranscript
        }
        if isInside(target, resolved(session.directory)) {
            throw TranscriptExportError.destinationInsideMeeting
        }
        guard let saveFolder else { return }
        let folder = resolved(saveFolder)
        // Anything deeper than the save folder's own level sits in one of its
        // subfolders; refuse it when that subfolder is a meeting.
        guard isInside(target, folder), target.count > folder.count + 1 else { return }
        let subfolder = URL(filePath: NSString.path(withComponents: Array(target.prefix(folder.count + 1))),
                            directoryHint: .isDirectory)
        if isMeetingDirectory(subfolder) {
            throw TranscriptExportError.destinationInsideMeeting
        }
    }

    /// A location's path components with symbolic links resolved.
    ///
    /// A location that exists is resolved whole. One that does not yet — a
    /// destination about to be written — keeps its last component and has
    /// its parent resolved, so it is compared by where it will be written.
    ///
    /// - Parameter url: The location.
    /// - Returns: Its components.
    private nonisolated static func resolved(_ url: URL) -> [String] {
        let standard = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: standard.path(percentEncoded: false)) {
            return standard.resolvingSymlinksInPath().pathComponents
        }
        let parent = standard.deletingLastPathComponent().resolvingSymlinksInPath()
        return parent.appending(path: standard.lastPathComponent).standardizedFileURL.pathComponents
    }

    /// Whether one path lies strictly below another.
    ///
    /// - Parameters:
    ///   - path: The candidate's components.
    ///   - folder: The folder's components.
    /// - Returns: `true` when `path` is inside `folder`.
    private nonisolated static func isInside(_ path: [String], _ folder: [String]) -> Bool {
        path.count > folder.count && Array(path.prefix(folder.count)) == folder
    }

    /// Runs work with security-scoped access to the save folder held open for
    /// exactly the length of that work.
    ///
    /// - Parameters:
    ///   - folder: The save folder, or `nil` to run the work without access.
    ///   - body: The work.
    /// - Returns: Whatever `body` returns.
    /// - Throws: ``TranscriptExportError/folderUnavailable`` when macOS
    ///   refuses access, or whatever `body` throws.
    private func withFolderAccess<T>(_ folder: URL?, perform body: () throws -> T) throws -> T {
        guard let folder else { return try body() }
        do {
            return try SecurityScopedAccess.withAccess(to: folder, using: access) { _ in try body() }
        } catch is SaveLocationError {
            throw TranscriptExportError.folderUnavailable
        }
    }
}
