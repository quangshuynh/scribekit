//
//  DiagnosticReport.swift
//  ScribeKit
//

import Foundation

/// A point-in-time description of what ScribeKit is doing, safe to hand to
/// somebody else.
///
/// This is not a log and not a journal. Nothing accumulates it, nothing writes
/// it in the background and nothing persists it: it is assembled from state
/// that already exists at the moment the user asks for it, encoded once, and
/// written where the user said. A meeting that has not run leaves most of it
/// empty, which is itself the answer to "did anything start?".
///
/// Every field here passed ``DiagnosticSafety``'s contract. There is no
/// transcript text, no partial hypothesis, no note, no review passage, no
/// meeting title, no application name, no window title, no absolute path and no
/// bookmark. What is left is counts, durations, states, versions and stable
/// identifiers — enough to say which subsystem stopped and in what condition,
/// and not enough to say what the meeting was about.
///
/// The structure is versioned from its first release so a reader can refuse a
/// report it does not understand rather than misreading one.
nonisolated struct DiagnosticReport: Codable, Equatable, Sendable {

    /// The layout version this build writes.
    static let currentSchemaVersion = 1

    /// The layout version of this report.
    let schemaVersion: Int

    /// When the report was assembled.
    let generatedAt: Date

    /// Which ScribeKit produced it.
    let application: Application

    /// Which macOS it ran on.
    let system: System

    /// What the meeting owner is doing right now.
    let runtime: Runtime

    /// Whether a meeting could be started, and what is stopping it. Absent
    /// when the setup screen has not been on screen in this launch, which is
    /// possible for a menu bar application and is not the same claim as
    /// "nothing is ready".
    let readiness: Readiness?

    /// Whether the user's chosen folder is usable, without saying where it is.
    /// Absent for the same reason ``readiness`` can be.
    let storage: Storage?

    /// What unfinished-session discovery last found.
    let recovery: Recovery

    /// The meeting that is running, or the one that most recently ended.
    let session: SessionSummary?

    /// How the last meeting ended, when one has.
    let lastOutcome: Outcome?

    /// Which ScribeKit wrote the report.
    struct Application: Codable, Equatable, Sendable {
        /// ScribeKit's own bundle identifier — the application being
        /// diagnosed, never a captured one.
        let bundleIdentifier: String

        /// The marketing version.
        let version: String

        /// The build number.
        let build: String
    }

    /// The Mac, in the two respects that change ScribeKit's behaviour.
    struct System: Codable, Equatable, Sendable {
        /// The operating system version, as major.minor.patch.
        let operatingSystemVersion: String

        /// The processor architecture ScribeKit is running as.
        let architecture: String
    }

    /// What the meeting owner is doing, one stable name per subsystem.
    struct Runtime: Codable, Equatable, Sendable {
        /// The one derived answer the window and the menu bar both read.
        let status: String

        /// Whether a meeting is holding resources.
        let isRunning: Bool

        /// The capture subsystem's state.
        let capture: String

        /// The recogniser's state.
        let recognition: String

        /// The canonical transcript's state.
        let transcript: String

        /// Retained audio's state.
        let audio: String

        /// The BCP-47 locale recognition is configured for.
        let recognitionLocaleIdentifier: String

        /// Whether an on-device model is installed and usable, and why not
        /// when it is not.
        let speechAvailability: String

        /// How many locales have a model installed.
        let installedRecognitionLocaleCount: Int
    }

    /// Whether a meeting can start.
    struct Readiness: Codable, Equatable, Sendable {
        /// Whether the Start button would be offered.
        let canStart: Bool

        /// The first unsatisfied prerequisite, when there is one.
        let blocker: String?

        /// Each prerequisite and its status, without the sentence shown beside
        /// it: those sentences quote folders and application names.
        let prerequisites: [Prerequisite]

        /// How many applications discovery found, once it has run.
        let discoveredSourceCount: Int?

        /// How many of them are selected.
        let selectedSourceCount: Int?

        /// How many remembered selections were no longer running. The names
        /// are deliberately not carried.
        let droppedSelectionCount: Int?

        /// One prerequisite's standing.
        struct Prerequisite: Codable, Equatable, Sendable {
            /// Which prerequisite.
            let name: String

            /// Its status.
            let status: String
        }
    }

    /// The save location, described without being named.
    struct Storage: Codable, Equatable, Sendable {
        /// Whether the user has picked a folder at all.
        let saveLocationChosen: Bool

        /// Whether ScribeKit currently holds usable access to it.
        let saveLocationResolved: Bool

        /// Whether the choice survived relaunch as a security-scoped bookmark.
        let saveLocationRemembered: Bool

        /// Whether an authoritative check found Screen & System Audio
        /// Recording access, or `nil` when nothing has asked yet.
        let captureAccessAvailable: Bool?
    }

    /// What the last scan for unfinished sessions found.
    struct Recovery: Codable, Equatable, Sendable {
        /// Whether a scan has run in this launch.
        let scanned: Bool

        /// How many sessions were found still recorded as in progress.
        let unfinishedSessionCount: Int

        /// How many session folders could not be described.
        let unreadableSessionCount: Int

        /// Why they could not be, as stable names, deduplicated and sorted.
        let problems: [String]

        /// The session record layout this build writes.
        let sessionMetadataSchemaVersion: Int

        /// The review sidecar layout this build writes.
        let reviewMetadataSchemaVersion: Int

        /// The derived-state sidecar layout this build writes.
        let derivedMetadataSchemaVersion: Int
    }

    /// Safe metadata about one meeting.
    ///
    /// Deliberately not here: the title, which is prose the user wrote; the
    /// session directory, which is a path through their home folder; the
    /// application names, which say who they were meeting; and every byte of
    /// what was said.
    struct SessionSummary: Codable, Equatable, Sendable {
        /// Whether this describes the meeting that is running or the last one
        /// to end.
        let phase: String

        /// How much audio the meeting keeps.
        let retentionMode: String

        /// The locale the run was started in.
        let recognitionLocaleIdentifier: String

        /// How many applications it captures.
        let selectedSourceCount: Int

        /// When it started.
        let startedAt: Date

        /// Wall-clock seconds since it started, which do not stop for a pause.
        let wallDurationSeconds: Double

        /// Captured media seconds, which do.
        let capturedDurationSeconds: Double

        /// How many times it was paused.
        let pauseCount: Int

        /// How many times the recogniser restarted itself.
        let recognitionRestartCount: Int

        /// How many finalised spans reached the transcript.
        let transcriptSpanCount: Int

        /// How many gaps were written into it.
        let gapCount: Int

        /// How much time those gaps account for.
        let untranscribedSeconds: Double

        /// Whether a recording file was opened.
        let recordingPresent: Bool

        /// The sample rate capture was asked for, when a meeting has started.
        let capturedSampleRate: Double?

        /// The channel count capture was asked for.
        let capturedChannelCount: Int?
    }

    /// How the last meeting ended.
    struct Outcome: Codable, Equatable, Sendable {
        /// The ending the user was shown, as a stable name rather than the
        /// paragraph explaining it.
        let category: String

        /// The support-facing failure category, absent for a meeting that
        /// finished normally.
        let diagnosticCategory: DiagnosticCategory?

        /// Whether capture ran at all before it ended.
        let capturedAudio: Bool
    }

    /// Encodes the report as the bytes that get written.
    ///
    /// Pretty-printed with sorted keys so two reports from the same state are
    /// byte-identical and a person can read one in any editor; ISO 8601 dates
    /// so a timestamp does not depend on the reader's locale; no escaped
    /// slashes, because the only slashes here are in identifiers.
    ///
    /// - Returns: UTF-8 JSON, newline-terminated.
    /// - Throws: An encoding error, which cannot arise from these types.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}
