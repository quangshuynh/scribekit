//
//  SoakSupportTests.swift
//  SoakValidation
//

import Foundation
import Testing
@testable import ScribeKit

/// The parts of the soak harness that decide something, tested the way
/// production logic is.
///
/// The runs themselves are not tested — a CPU percentage is an observation,
/// not a contract. What is tested is everything that would silently invalidate
/// one: the gate that keeps a soak from starting by accident, the schedule
/// that decides when to observe, and the rules that judge the artifacts a run
/// leaves behind.
@Suite("Soak harness support")
struct SoakSupportTests {

    private static let output = URL(filePath: "/tmp/scribekit-soak-default", directoryHint: .isDirectory)

    @Test("An empty environment starts no soak")
    func gateIsClosedByDefault() {
        #expect(SoakConfiguration.resolve([:], defaultOutput: Self.output) == nil)
    }

    @Test("Only an affirmative flag opens the gate", arguments: [
        ("1", true), ("true", true), ("TRUE", true), ("yes", true),
        ("0", false), ("false", false), ("", false), ("maybe", false)
    ])
    func gateAcceptsOnlyAffirmatives(value: String, opens: Bool) {
        let resolved = SoakConfiguration.resolve(
            [SoakConfiguration.enableKey: value],
            defaultOutput: Self.output
        )
        #expect((resolved != nil) == opens)
    }

    @Test("Defaults are an hour of compressed retention sampled every five minutes")
    func defaultsMatchTheDocumentedRun() throws {
        let resolved = try #require(
            SoakConfiguration.resolve(
                [SoakConfiguration.enableKey: "1"],
                defaultOutput: Self.output
            )
        )
        #expect(resolved.minutes == 60)
        #expect(resolved.retention == .compressed)
        #expect(resolved.sampleSeconds == 300)
        #expect(resolved.sourceBundleIdentifier == nil)
        #expect(resolved.output == Self.output)
        #expect(resolved.duration == 3_600)
    }

    @Test("Every key is read")
    func environmentOverridesEveryField() throws {
        let resolved = try #require(
            SoakConfiguration.resolve(
                [
                    SoakConfiguration.enableKey: "yes",
                    SoakConfiguration.minutesKey: "20",
                    SoakConfiguration.retentionKey: "raw",
                    SoakConfiguration.sampleSecondsKey: "60",
                    SoakConfiguration.sourceKey: "com.apple.TextEdit",
                    SoakConfiguration.outputKey: "/tmp/elsewhere"
                ],
                defaultOutput: Self.output
            )
        )
        #expect(resolved.minutes == 20)
        #expect(resolved.retention == .raw)
        #expect(resolved.sampleSeconds == 60)
        #expect(resolved.sourceBundleIdentifier == "com.apple.TextEdit")
        #expect(resolved.output.lastPathComponent == "elsewhere")
    }

    @Test("A run that could not measure anything is refused", arguments: [
        [SoakConfiguration.minutesKey: "0"],
        [SoakConfiguration.minutesKey: "-5"],
        [SoakConfiguration.sampleSecondsKey: "0"]
    ])
    func unusableValuesAreRefused(overrides: [String: String]) {
        var environment = [SoakConfiguration.enableKey: "1"]
        environment.merge(overrides) { _, new in new }
        #expect(SoakConfiguration.resolve(environment, defaultOutput: Self.output) == nil)
    }

    @Test("An hour is observed at the start, every five minutes, and at the end")
    func hourlyScheduleMatchesTheIntervalsAskedFor() {
        let schedule = SoakSampleSchedule(interval: 300, duration: 3_600)
        #expect(schedule.offsets.first == 0)
        #expect(schedule.offsets.last == 3_600)
        #expect(schedule.offsets.count == 13)
        for mark in [600.0, 1_200, 1_800, 2_700, 3_600] {
            #expect(schedule.offsets.contains(mark))
        }
    }

    @Test("The end is observed once, not twice")
    func scheduleDoesNotRepeatItsLastOffset() {
        let offsets = SoakSampleSchedule(interval: 300, duration: 900).offsets
        #expect(offsets == [0, 300, 600, 900])
    }

    @Test("A duration shorter than the interval still has two ends")
    func shortRunsKeepBothEndpoints() {
        #expect(SoakSampleSchedule(interval: 300, duration: 60).offsets == [0, 60])
        #expect(SoakSampleSchedule(interval: 0, duration: 60).offsets == [0, 60])
        #expect(SoakSampleSchedule(interval: 300, duration: 0).offsets == [0])
    }

    @Test("Waits are the gaps between offsets, and run out at the end")
    func waitsFollowTheSchedule() {
        let schedule = SoakSampleSchedule(interval: 300, duration: 700)
        #expect(schedule.secondsAfter(0) == 300)
        #expect(schedule.secondsAfter(300) == 300)
        #expect(schedule.secondsAfter(600) == 100)
        #expect(schedule.secondsAfter(700) == nil)
    }

    @Test("A recording is plausible when it is within a couple of seconds")
    func recordingPlausibility() {
        #expect(SoakArtifactReport.isPlausible(recorded: 3_600, captured: 3_600))
        #expect(SoakArtifactReport.isPlausible(recorded: 3_598.5, captured: 3_600))
        #expect(SoakArtifactReport.isPlausible(recorded: 3_601.2, captured: 3_600))
        #expect(!SoakArtifactReport.isPlausible(recorded: 3_540, captured: 3_600))
        #expect(!SoakArtifactReport.isPlausible(recorded: 0, captured: 3_600))
    }

    @Test("A report passes only when every check did")
    func reportPassesOnlyWhenEveryCheckDid() {
        let ok = SoakArtifactCheck(name: "a", passed: true, detail: "")
        let bad = SoakArtifactCheck(name: "b", passed: false, detail: "")
        #expect(SoakArtifactReport(checks: [ok, ok]).passed)
        #expect(!SoakArtifactReport(checks: [ok, bad]).passed)
        #expect(SoakArtifactReport(checks: [ok, bad]).lines.contains { $0.contains("FAIL") })
    }

    @Test("No run file leaves the process environment alone")
    func absentRunFileChangesNothing() {
        let environment = ["A": "1"]
        #expect(SoakRunFile.environment(processEnvironment: environment, contents: nil) == environment)
    }

    @Test("The run file wins over the process environment")
    func runFileOverridesTheEnvironment() {
        let merged = SoakRunFile.environment(
            processEnvironment: [SoakConfiguration.enableKey: "0", "OTHER": "kept"],
            contents: "\(SoakConfiguration.enableKey)=1\n\(SoakConfiguration.minutesKey)=15"
        )
        #expect(merged[SoakConfiguration.enableKey] == "1")
        #expect(merged[SoakConfiguration.minutesKey] == "15")
        #expect(merged["OTHER"] == "kept")
    }

    @Test("The run file is key, equals, value, and forgiving about the rest")
    func runFileParsing() {
        let parsed = SoakRunFile.parse("""
            # a comment

              SPACED  =  value
            EMPTY=
            PATH_LIKE=/tmp/a=b
            nonsense
            =novalue
            """)
        #expect(parsed["SPACED"] == "value")
        #expect(parsed["EMPTY"] == "")
        #expect(parsed["PATH_LIKE"] == "/tmp/a=b")
        #expect(parsed["nonsense"] == nil)
        #expect(parsed.count == 3)
    }

    @Test("A run file that asks for nothing still starts nothing")
    func emptyRunFileKeepsTheGateClosed() {
        let merged = SoakRunFile.environment(processEnvironment: [:], contents: "# nothing\n")
        #expect(SoakConfiguration.resolve(merged, defaultOutput: Self.output) == nil)
    }

    @Test("Window CPU is the process's own seconds over the window")
    func windowCPUIsAFractionOfOneCore() {
        let first = SoakProcessSample(
            footprintBytes: 0, cpuSeconds: 10, threadCount: 1, thermalState: "nominal"
        )
        let second = SoakProcessSample(
            footprintBytes: 0, cpuSeconds: 40, threadCount: 1, thermalState: "nominal"
        )
        #expect(second.cpuFraction(since: first, over: 300) == 0.1)
        #expect(second.cpuFraction(since: nil, over: 300) == nil)
        #expect(second.cpuFraction(since: first, over: 0) == nil)
    }

    @Test("Speech substitution keeps the buffer the stream delivered")
    func substitutionPreservesCadenceAndFormat() {
        let format = CapturedAudioFormat(
            sampleRate: 48_000, channelCount: 2, bitsPerChannel: 32,
            isFloat: true, isInterleaved: false
        )
        let silent = CapturedPCMBuffer(
            format: format,
            frameCount: 960,
            presentationTime: 12.5,
            peakAmplitude: 0,
            samples: [Float](repeating: 0, count: 1_920)
        )
        let recorder = RecordingConsumer()
        let injector = SyntheticSpeechInjector(downstream: recorder, speech: [0.25, -0.5, 0.75])
        injector.consume(silent)

        let received = recorder.buffers.first
        #expect(received?.format == format)
        #expect(received?.frameCount == 960)
        #expect(received?.presentationTime == 12.5)
        #expect(received?.samples.count == 1_920)
        #expect(received?.peakAmplitude == 0.75)
        // Non-interleaved: both channels carry the same substituted frame.
        #expect(received?.samples[0] == received?.samples[960])
    }

    @Test("Substitution keeps cycling through the loop across buffers")
    func substitutionAdvancesThroughTheLoop() {
        let format = CapturedAudioFormat(
            sampleRate: 48_000, channelCount: 1, bitsPerChannel: 32,
            isFloat: true, isInterleaved: false
        )
        let buffer = CapturedPCMBuffer(
            format: format, frameCount: 2, presentationTime: nil,
            peakAmplitude: 0, samples: [0, 0]
        )
        let recorder = RecordingConsumer()
        let injector = SyntheticSpeechInjector(downstream: recorder, speech: [0.1, 0.2, 0.3, 0.4])
        injector.consume(buffer)
        injector.consume(buffer)
        #expect(recorder.buffers.map(\.samples) == [[0.1, 0.2], [0.3, 0.4]])
    }
}

/// Keeps what it was given, so a substitution can be inspected.
private final class RecordingConsumer: AudioSampleConsuming, @unchecked Sendable {
    private(set) var buffers: [CapturedPCMBuffer] = []

    func consume(_ buffer: CapturedPCMBuffer) { buffers.append(buffer) }
}

