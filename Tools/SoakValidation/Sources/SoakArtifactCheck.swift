//
//  SoakArtifactCheck.swift
//  SoakValidation
//

import AVFoundation
import Foundation
@testable import ScribeKit

/// One thing a finished soak run is checked for, and whether it held.
nonisolated struct SoakArtifactCheck: Equatable, Sendable {
    /// What was checked, in the report's words.
    let name: String

    /// Whether it held.
    let passed: Bool

    /// What was actually found.
    let detail: String
}

/// What a finished soak left on disk, and whether it is usable.
///
/// The report separates reading the artifacts from judging them: the judging
/// is a value with no filesystem in it, so the rules — a transcript that
/// parses and has a footer, a session record that says completed, a recording
/// whose length is plausible against the captured duration — are testable
/// without a meeting.
nonisolated struct SoakArtifactReport: Equatable, Sendable {

    /// How far a recording's own length may sit from the captured duration
    /// before it stops being plausible: the encoder's last partial packet and
    /// the frames in flight at Stop, and nothing like a whole minute.
    static let recordingTolerance: Double = 2.0

    /// The checks, in the order they were made.
    let checks: [SoakArtifactCheck]

    /// Whether every check held.
    var passed: Bool { checks.allSatisfy(\.passed) }

    /// The report as lines for stdout.
    var lines: [String] {
        checks.map { "  [\($0.passed ? "ok" : "FAIL")] \($0.name): \($0.detail)" }
    }

    /// Judges one recording's length against what the meeting says it captured.
    ///
    /// - Parameters:
    ///   - recorded: Seconds the audio file itself reports.
    ///   - captured: Seconds the meeting says reached the pipeline.
    /// - Returns: Whether the difference is within ``recordingTolerance``.
    static func isPlausible(recorded: Double, captured: Double) -> Bool {
        abs(recorded - captured) <= recordingTolerance
    }

    /// Reads a finished session directory and judges it.
    ///
    /// - Parameters:
    ///   - directory: The session directory the run wrote.
    ///   - retention: What the meeting was asked to retain.
    ///   - capturedSeconds: Seconds of audio the meeting says it captured.
    /// - Returns: The report.
    static func inspect(
        directory: URL,
        retention: AudioRetentionMode,
        capturedSeconds: Double
    ) -> SoakArtifactReport {
        var checks: [SoakArtifactCheck] = []
        let layout = SessionArtifactLayout(
            destination: directory.deletingLastPathComponent(),
            directoryName: directory.lastPathComponent
        )

        let transcriptText = try? String(contentsOf: layout.transcriptURL, encoding: .utf8)
        if let transcriptText {
            let document = TranscriptDocument.parse(transcriptText)
            checks.append(
                SoakArtifactCheck(
                    name: "transcript parses",
                    passed: !document.spans.isEmpty,
                    detail: "\(document.spans.count) spans, \(transcriptText.utf8.count) B"
                )
            )
            checks.append(
                SoakArtifactCheck(
                    name: "transcript footer",
                    passed: transcriptText.contains("**Ended:**") && transcriptText.contains("**Duration:**"),
                    detail: transcriptText.contains("**Ended:**") ? "present" : "missing"
                )
            )
        } else {
            checks.append(
                SoakArtifactCheck(name: "transcript parses", passed: false, detail: "unreadable")
            )
        }

        if let data = try? Data(contentsOf: layout.metadataURL),
           let metadata = try? SessionRecoveryMetadata.decoded(from: data) {
            checks.append(
                SoakArtifactCheck(
                    name: "session record",
                    passed: metadata.status == .completed,
                    detail: "status \(metadata.status.rawValue), ended "
                        + (metadata.endedAt.map(ISO8601DateFormatter().string(from:)) ?? "not recorded")
                )
            )
        } else {
            checks.append(
                SoakArtifactCheck(name: "session record", passed: false, detail: "unreadable")
            )
        }

        if retention.retainsAudio, let audioURL = layout.audioURL(for: retention) {
            if let file = try? AVAudioFile(forReading: audioURL) {
                let seconds = Double(file.length) / file.fileFormat.sampleRate
                let size = (try? Data(contentsOf: audioURL, options: .mappedIfSafe).count) ?? 0
                checks.append(
                    SoakArtifactCheck(
                        name: "recording opens",
                        passed: true,
                        detail: "\(size) B, " + String(format: "%.1f", seconds) + "s"
                    )
                )
                checks.append(
                    SoakArtifactCheck(
                        name: "recording duration plausible",
                        passed: isPlausible(recorded: seconds, captured: capturedSeconds),
                        detail: String(format: "%.1f", seconds) + "s against "
                            + String(format: "%.1f", capturedSeconds) + "s captured"
                    )
                )
            } else {
                checks.append(
                    SoakArtifactCheck(name: "recording opens", passed: false, detail: "unreadable")
                )
            }
        }

        if let data = try? Data(contentsOf: layout.reviewURL) {
            let valid = (try? JSONSerialization.jsonObject(with: data)) != nil
            checks.append(
                SoakArtifactCheck(
                    name: "review sidecar",
                    passed: valid,
                    detail: valid ? "\(data.count) B, valid JSON" : "invalid JSON"
                )
            )
        }

        let siblings = (try? FileManager.default.contentsOfDirectory(
            at: directory.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )) ?? []
        let sessions = siblings.filter(\.hasDirectoryPath)
        checks.append(
            SoakArtifactCheck(
                name: "one session directory",
                passed: sessions.count == 1,
                detail: "\(sessions.count) in the destination"
            )
        )

        return SoakArtifactReport(checks: checks)
    }
}
