//
//  SoakValidationTests.swift
//  SoakValidation
//

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ScribeKit

/// The soak runs themselves: hours of real-time capture, invoked deliberately.
///
/// Every test here is disabled unless ``SoakConfiguration/enableKey`` is set,
/// so an ordinary `xcodebuild test` runs none of them and the shipping
/// application cannot reach them at all. `Tools/SoakValidation/run-soak.sh` is
/// the intended entry point; the README beside it says how.
@Suite("Soak validation", .serialized)
struct SoakValidationTests {

    /// The configuration the process was launched with, if any.
    static var configuration: SoakConfiguration? {
        SoakConfiguration.resolve(
            SoakRunFile.environment(
                processEnvironment: ProcessInfo.processInfo.environment,
                contents: try? String(contentsOf: SoakRunFile.url, encoding: .utf8)
            ),
            defaultOutput: FileManager.default.temporaryDirectory
                .appending(path: "scribekit-soak", directoryHint: .isDirectory)
        )
    }

    /// Whether any soak may run in this process.
    static var isEnabled: Bool { configuration != nil }

    /// One continuous real-time meeting, ended with a normal Stop.
    ///
    /// This is the external confirmation of the Interval 16 fix: a run that
    /// crosses the historical 20–26 minute failure band by a wide margin and
    /// finalises normally, against the real stream, the real recogniser and
    /// both durable writers.
    @Test("Continuous capture, then a normal stop", .enabled(if: SoakValidationTests.isEnabled), .timeLimit(.minutes(180)))
    @MainActor
    func sustainedCapture() async throws {
        let configuration = try #require(Self.configuration)
        let session = try await SoakSession.make(configuration: configuration)
        Self.announce(session)

        try await session.start(title: "Soak validation")
        await session.observe(
            on: SoakSampleSchedule(
                interval: configuration.sampleSeconds,
                duration: configuration.duration
            ),
            label: "capturing"
        )

        let captured = session.runtime.capturedDuration
        await session.stop()
        try session.writeReport(named: "soak-observations.json")

        #expect(session.runtime.status == .completed)
        #expect(!session.runtime.isRunning)

        let report = try #require(session.verify(capturedSeconds: captured))
        for line in report.lines { print(line) }
        #expect(report.passed)
    }

    /// The same meeting with the window visible, hidden and closed.
    ///
    /// The window here is the real ``ScribeKitRootView`` over the runtime under
    /// measurement, so what changes between phases is exactly ScribeKit's own
    /// presentation work: capture, recognition, retention and transcript
    /// writing are identical throughout, and the meeting is never restarted.
    @Test("Window visible, hidden and closed", .enabled(if: SoakValidationTests.isEnabled), .timeLimit(.minutes(60)))
    @MainActor
    func presentationCost() async throws {
        let configuration = try #require(Self.configuration)
        let session = try await SoakSession.make(configuration: configuration)
        Self.announce(session)

        let phase = SoakSampleSchedule(
            interval: configuration.sampleSeconds,
            duration: configuration.duration / 3
        )

        try await session.start(title: "Presentation cost")

        var window: NSWindow? = Self.makeWindow(for: session.runtime)
        window?.makeKeyAndOrderFront(nil)
        await session.observe(on: phase, label: "visible")

        window?.orderOut(nil)
        await session.observe(on: phase, label: "hidden")

        window?.close()
        window = nil
        await session.observe(on: phase, label: "closed")

        // Closing the window is a presentation act and nothing else.
        #expect(session.runtime.isRunning)
        let beforeReopen = session.runtime.transcript.finalizedSegments.count
        let reopened = Self.makeWindow(for: session.runtime)
        reopened.makeKeyAndOrderFront(nil)
        session.observe(label: "reopened")
        #expect(session.runtime.transcript.finalizedSegments.count >= beforeReopen)
        reopened.close()

        let captured = session.runtime.capturedDuration
        await session.stop()
        try session.writeReport(named: "presentation-observations.json")

        let report = try #require(session.verify(capturedSeconds: captured))
        for line in report.lines { print(line) }
        #expect(report.passed)
    }

    /// Active, paused and resumed, with both artifacts watched across the pause.
    @Test("Pause holds the artifacts still", .enabled(if: SoakValidationTests.isEnabled), .timeLimit(.minutes(60)))
    @MainActor
    func pausedBaseline() async throws {
        let configuration = try #require(Self.configuration)
        let session = try await SoakSession.make(configuration: configuration)
        Self.announce(session)

        let phase = SoakSampleSchedule(
            interval: configuration.sampleSeconds,
            duration: configuration.duration / 3
        )

        try await session.start(title: "Pause baseline")
        await session.observe(on: phase, label: "active")

        let elapsedAtPause = session.runtime.elapsed.elapsed
        await session.runtime.pause()
        let atPause = session.observe(label: "paused")
        await session.observe(on: phase, label: "paused")
        let afterPause = try #require(session.observations.last)

        #expect(afterPause.transcriptBytes == atPause.transcriptBytes)
        #expect(afterPause.recordingBytes == atPause.recordingBytes)
        #expect(afterPause.capturedSeconds == atPause.capturedSeconds)
        #expect(session.runtime.elapsed.elapsed > elapsedAtPause)

        await session.runtime.resume()
        await session.observe(on: phase, label: "resumed")
        let resumed = try #require(session.observations.last)
        #expect((resumed.capturedSeconds) > afterPause.capturedSeconds)

        let captured = session.runtime.capturedDuration
        await session.stop()
        try session.writeReport(named: "pause-observations.json")

        let report = try #require(session.verify(capturedSeconds: captured))
        for line in report.lines { print(line) }
        #expect(report.passed)
    }

    /// A window over the runtime under measurement, outside SwiftUI's scenes.
    ///
    /// The application's own window observes the application's own runtime,
    /// which is idle here; this one observes the meeting being measured, which
    /// is the thing whose presentation cost is in question.
    @MainActor
    private static func makeWindow(for runtime: MeetingRuntime) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Soak validation"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ScribeKitRootView(runtime: runtime))
        return window
    }

    @MainActor
    private static func announce(_ session: SoakSession) {
        print("""

            ScribeKit soak validation
              source      \(session.source?.displayName ?? "-") (\(session.source?.id ?? "-"))
              retention   \(session.configuration.retention.rawValue)
              minutes     \(session.configuration.minutes)
              sample      every \(Int(session.configuration.sampleSeconds))s
              output      \(session.destination.path(percentEncoded: false))
              provenance  REAL capture cadence, format and timing; SYNTHETIC sample values

            """)
    }
}
