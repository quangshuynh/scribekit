//
//  AudioRetentionMode.swift
//  ScribeKit
//

import Foundation

/// How much captured audio a session keeps on disk once it ends.
///
/// Retention is opt-in: the default mode keeps no audio at all, so a session
/// produces only its transcript unless the user asks for more.
enum AudioRetentionMode: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    /// Keep no audio file; only the transcript is written.
    case none

    /// Keep lossless audio, at the cost of significantly more disk space.
    case raw

    /// Keep lossy compressed audio as a smaller reviewable record.
    case compressed

    var id: String { rawValue }

    /// The mode used when the user has not chosen one.
    nonisolated static let `default`: AudioRetentionMode = .none

    /// A short, user-facing label suitable for menus and pickers.
    var displayName: String {
        switch self {
        case .none: "No Audio File"
        case .raw: "Raw (Lossless)"
        case .compressed: "Compressed"
        }
    }

    /// Whether the mode causes captured audio to be written to disk.
    var retainsAudio: Bool { self != .none }
}
