//
//  SoakObservation.swift
//  SoakValidation
//

import Foundation

/// One low-frequency reading of the process and of the meeting's artifacts.
///
/// Everything here is a number the harness already had or could read in a
/// microsecond: nothing is derived from a trace, and nothing is sampled often
/// enough to become part of the workload it describes.
nonisolated struct SoakObservation: Codable, Equatable, Sendable {

    /// What the run was doing when the observation was taken.
    let label: String

    /// Seconds of wall clock since the run started.
    let elapsedSeconds: TimeInterval

    /// Seconds of audio the pipeline says it has captured.
    let capturedSeconds: Double

    /// Resident footprint in bytes, as `phys_footprint` reports it.
    let footprintBytes: UInt64

    /// Process CPU seconds consumed since launch.
    let cpuSeconds: Double

    /// Process CPU over the window since the previous observation, as a
    /// fraction of one core. `nil` for the first observation of a run.
    let windowCPUFraction: Double?

    /// Live threads in the process.
    let threadCount: Int

    /// The system's thermal pressure, as a word.
    let thermalState: String

    /// Bytes in `transcript.md`, when it exists yet.
    let transcriptBytes: Int?

    /// Bytes in the retained recording, when the meeting keeps one.
    let recordingBytes: Int?

    /// What the runtime says it is doing.
    let status: String

    /// Buffers capture has delivered.
    let bufferCount: Int

    /// Buffers that arrived and could not be read.
    let unreadableBufferCount: Int

    /// A fixed-width line for the run's stdout log.
    var line: String {
        let cpu = windowCPUFraction.map { String(format: "%6.2f%%", $0 * 100) } ?? "     --"
        let rss = String(format: "%6.1f MB", Double(footprintBytes) / 1_048_576)
        let transcript = transcriptBytes.map { String($0) } ?? "-"
        let recording = recordingBytes.map { String($0) } ?? "-"
        return String(
            format: "%@  wall %7.1fs  media %7.1fs  cpu %@  rss %@  thr %3d  %@  md %10@  audio %12@  %@  buffers %d/%d",
            label.padding(toLength: 12, withPad: " ", startingAt: 0),
            elapsedSeconds,
            capturedSeconds,
            cpu,
            rss,
            threadCount,
            thermalState.padding(toLength: 8, withPad: " ", startingAt: 0),
            transcript as NSString,
            recording as NSString,
            status.padding(toLength: 14, withPad: " ", startingAt: 0),
            bufferCount,
            unreadableBufferCount
        )
    }
}

/// The counters a soak reads out of the running process.
nonisolated struct SoakProcessSample: Equatable, Sendable {
    /// Resident footprint in bytes.
    let footprintBytes: UInt64

    /// CPU seconds consumed by the process since launch.
    let cpuSeconds: Double

    /// Live threads.
    let threadCount: Int

    /// Thermal pressure as a word.
    let thermalState: String

    /// CPU over a window, as a fraction of one core.
    ///
    /// - Parameters:
    ///   - previous: The sample the window opened with, or `nil` for the first.
    ///   - seconds: Wall seconds the window spanned.
    /// - Returns: The fraction, or `nil` when there is no window to divide by.
    func cpuFraction(since previous: SoakProcessSample?, over seconds: TimeInterval) -> Double? {
        guard let previous, seconds > 0 else { return nil }
        return (cpuSeconds - previous.cpuSeconds) / seconds
    }
}
