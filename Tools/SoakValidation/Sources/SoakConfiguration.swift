//
//  SoakConfiguration.swift
//  SoakValidation
//

import Foundation
@testable import ScribeKit

/// What one real-time soak run should do, read from the environment.
///
/// The configuration is a value with no I/O in it, so the rules that decide
/// whether a soak runs at all — and for how long, against which source, into
/// which disposable folder — are testable without starting one. Resolution
/// fails closed: a normal `xcodebuild test` sets none of these keys, so
/// ``resolve(_:defaultOutput:)`` returns `nil` and every soak entry point is
/// skipped. Nothing here can be reached by launching ScribeKit.
nonisolated struct SoakConfiguration: Equatable, Sendable {

    /// Set to `1`, `true` or `yes` to allow a soak to run at all.
    static let enableKey = "SCRIBEKIT_SOAK"

    /// How many minutes of continuous capture the run should reach.
    static let minutesKey = "SCRIBEKIT_SOAK_MINUTES"

    /// The bundle identifier of the application to capture. Absent means the
    /// harness picks the first application discovery offers.
    static let sourceKey = "SCRIBEKIT_SOAK_SOURCE"

    /// `none`, `raw` or `compressed`.
    static let retentionKey = "SCRIBEKIT_SOAK_RETENTION"

    /// A disposable directory for the run's session artifacts and report.
    static let outputKey = "SCRIBEKIT_SOAK_OUTPUT"

    /// Seconds between observations. Low frequency on purpose.
    static let sampleSecondsKey = "SCRIBEKIT_SOAK_SAMPLE_SECONDS"

    /// The shortest run the harness will accept, in minutes.
    static let minimumMinutes = 1

    /// The default gap between observations, in seconds.
    static let defaultSampleSeconds: TimeInterval = 300

    /// Minutes of capture to reach before a normal Stop.
    let minutes: Int

    /// The application to capture, or `nil` to take whatever is discovered.
    let sourceBundleIdentifier: String?

    /// What the meeting retains.
    let retention: AudioRetentionMode

    /// The disposable directory the run writes into.
    let output: URL

    /// Seconds between observations.
    let sampleSeconds: TimeInterval

    /// How long the run should capture for.
    var duration: TimeInterval { TimeInterval(minutes) * 60 }

    /// Reads a configuration from a process environment.
    ///
    /// - Parameters:
    ///   - environment: The environment to read, normally the process's own.
    ///   - defaultOutput: Where to write when ``outputKey`` is unset.
    /// - Returns: The configuration, or `nil` when the enable key is absent or
    ///   not affirmative, or when a value that is present cannot be used.
    static func resolve(
        _ environment: [String: String],
        defaultOutput: URL
    ) -> SoakConfiguration? {
        guard let flag = environment[enableKey]?.lowercased(),
              ["1", "true", "yes"].contains(flag) else { return nil }

        let minutes = environment[minutesKey].flatMap(Int.init) ?? 60
        guard minutes >= minimumMinutes else { return nil }

        let retention = environment[retentionKey]
            .flatMap { AudioRetentionMode(rawValue: $0.lowercased()) } ?? .compressed

        let sampleSeconds = environment[sampleSecondsKey]
            .flatMap(TimeInterval.init) ?? defaultSampleSeconds
        guard sampleSeconds > 0 else { return nil }

        let source = environment[sourceKey].flatMap { value in
            value.trimmingCharacters(in: .whitespaces).isEmpty ? nil : value
        }

        let output = environment[outputKey].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? defaultOutput

        return SoakConfiguration(
            minutes: minutes,
            sourceBundleIdentifier: source,
            retention: retention,
            output: output,
            sampleSeconds: sampleSeconds
        )
    }
}

/// The file a developer drops beside the sandboxed process to ask for a soak.
///
/// `xcodebuild` does not carry its own environment into a Release-configured
/// test host, so the environment alone cannot request a run. A file inside the
/// application's sandbox container can: `run-soak.sh` writes one, the harness
/// reads it, and the script removes it when the run ends. It is the same gate
/// by other means — a soak still requires a deliberate act outside the
/// application, the file never exists during ordinary use, and nothing in the
/// shipping app reads it.
nonisolated enum SoakRunFile {

    /// The file's name inside the process's home directory, which under App
    /// Sandbox is the application's own container.
    static let name = ".scribekit-soak-run"

    /// Where the harness looks for it.
    static var url: URL {
        URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory).appending(path: name)
    }

    /// Reads `KEY=VALUE` lines into a dictionary.
    ///
    /// Blank lines and lines beginning with `#` are ignored, a value may
    /// contain `=`, and surrounding whitespace is trimmed. A malformed line is
    /// skipped rather than failing the file, because the configuration it
    /// produces is validated afterwards anyway.
    ///
    /// - Parameter text: The file's contents.
    /// - Returns: The keys and values it declared.
    static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            result[key] = value
        }
        return result
    }

    /// The environment a soak should be resolved against.
    ///
    /// - Parameters:
    ///   - processEnvironment: The process's own environment.
    ///   - contents: The run file's contents, when one exists.
    /// - Returns: The process environment with the file's keys applied over it.
    static func environment(
        processEnvironment: [String: String],
        contents: String?
    ) -> [String: String] {
        guard let contents else { return processEnvironment }
        var merged = processEnvironment
        merged.merge(parse(contents)) { _, fromFile in fromFile }
        return merged
    }
}
