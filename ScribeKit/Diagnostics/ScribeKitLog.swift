//
//  ScribeKitLog.swift
//  ScribeKit
//

import Foundation
import OSLog

/// ScribeKit's unified-logging surface: one subsystem, one category per
/// concern, and nothing else.
///
/// Logging is local. `Logger` writes to the macOS unified log on the user's own
/// Mac; nothing here leaves the machine, and ScribeKit adds no logging
/// framework of its own on top of it.
///
/// The categories are concerns rather than types. A category per file would
/// make `log stream` a list of class names instead of a description of what a
/// meeting did, and the useful question during a support conversation is which
/// subsystem stopped, not which object printed.
///
/// What may be interpolated into these loggers is decided by
/// ``DiagnosticSafety``: counts, states, durations and stable identifiers are
/// public because a log nobody can read helps nobody, and recognised speech,
/// meeting titles, notes and user-chosen paths are not written at all — not
/// even as `.private`, which is a redaction setting rather than permission to
/// record what was said.
nonisolated enum ScribeKitLog {

    /// The subsystem every ScribeKit logger shares, matching the application's
    /// identifier so `log` and Console can filter on one predicate.
    static let subsystem = Bundle.main.bundleIdentifier ?? "ScribeKit"

    /// Meeting-wide transitions: start, active, pause, resume, stop, and the
    /// ending a meeting was recorded as.
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")

    /// Source discovery and the ScreenCaptureKit stream.
    static let capture = Logger(subsystem: subsystem, category: "capture")

    /// The on-device recogniser: runs, automatic restarts and terminal
    /// failures.
    static let recognition = Logger(subsystem: subsystem, category: "recognition")

    /// The canonical transcript and the session record.
    static let persistence = Logger(subsystem: subsystem, category: "persistence")

    /// Retained audio.
    static let audio = Logger(subsystem: subsystem, category: "audio")

    /// Unfinished-session discovery and the records it reads.
    static let recovery = Logger(subsystem: subsystem, category: "recovery")

    /// Reading past meetings back.
    static let history = Logger(subsystem: subsystem, category: "history")

    /// The diagnostic report itself: assembled, written, or refused.
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
}
