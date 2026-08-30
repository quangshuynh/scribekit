//
//  SessionArtifactLayout.swift
//  ScribeKit
//

import Foundation

/// Where a session's artifacts will be written, relative to the folder the
/// user chose.
///
/// The layout keeps the user-owned Markdown transcript at the top of the
/// session directory and ScribeKit's own bookkeeping in a hidden
/// subdirectory, so a session stays readable with nothing but a text editor
/// and never depends on a proprietary database:
///
/// ```
/// <session-directory>/
///   transcript.md
///   .scribekit/
///     session.json
///     review.json
/// ```
///
/// This is URL arithmetic only. It creates nothing, writes nothing, and makes
/// no claim that any of these files exist yet.
nonisolated struct SessionArtifactLayout: Equatable, Sendable {
    /// Name of the transcript file inside a session directory.
    static let transcriptFileName = "transcript.md"

    /// Name of the hidden directory holding ScribeKit's own metadata.
    static let metadataDirectoryName = ".scribekit"

    /// Name of the session metadata file inside ``metadataDirectory``.
    static let metadataFileName = "session.json"

    /// Name of the review sidecar inside ``metadataDirectory``.
    static let reviewFileName = "review.json"

    /// The session's own directory.
    let directory: URL

    /// Describes the layout for a session directory.
    ///
    /// - Parameter directory: The session's directory.
    init(directory: URL) {
        self.directory = directory
    }

    /// Describes the layout for a session inside the user's save location.
    ///
    /// - Parameters:
    ///   - destination: The folder the user chose for meeting artifacts.
    ///   - directoryName: The session directory name, from
    ///     ``SessionDirectoryName``.
    init(destination: URL, directoryName: String) {
        self.init(directory: destination.appending(path: directoryName, directoryHint: .isDirectory))
    }

    /// The raw Markdown transcript, owned by the user.
    var transcriptURL: URL {
        directory.appending(path: Self.transcriptFileName, directoryHint: .notDirectory)
    }

    /// The hidden directory holding ScribeKit's metadata.
    var metadataDirectory: URL {
        directory.appending(path: Self.metadataDirectoryName, directoryHint: .isDirectory)
    }

    /// The session metadata file. Losing it must never make the transcript
    /// unusable.
    var metadataURL: URL {
        metadataDirectory.appending(path: Self.metadataFileName, directoryHint: .notDirectory)
    }

    /// The review sidecar. It is optional bookkeeping: a session without one
    /// simply has no review information, exactly like one recorded before the
    /// file existed.
    var reviewURL: URL {
        metadataDirectory.appending(path: Self.reviewFileName, directoryHint: .notDirectory)
    }

    /// The audio file a retention mode would use.
    ///
    /// - Parameter mode: The session's retention choice.
    /// - Returns: Where audio would be written, or `nil` when the mode keeps
    ///   no audio. No audio capture exists yet; this only fixes the naming.
    func audioURL(for mode: AudioRetentionMode) -> URL? {
        switch mode {
        case .none: nil
        case .raw: directory.appending(path: "audio.caf", directoryHint: .notDirectory)
        case .compressed: directory.appending(path: "audio.m4a", directoryHint: .notDirectory)
        }
    }
}
