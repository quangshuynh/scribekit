//
//  DiagnosticExportTests.swift
//  ScribeKitTests
//

import Foundation
import Synchronization
import Testing
@testable import ScribeKit

/// Writing a report where the user asked, and saying so honestly when that
/// could not be done.
@MainActor
struct DiagnosticExportTests {

    /// A report with no meeting in it, which is all these tests need: they are
    /// about the writing, not the contents.
    private func report(at date: Date = Date(timeIntervalSinceReferenceDate: 0)) -> DiagnosticReport {
        DiagnosticReport.make(runtime: ReliabilityHarness().runtime, setup: nil, generatedAt: date)
    }

    @Test("A report is written where it was asked for, and is readable JSON")
    func writesToExplicitDestination() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "scribekit-diagnostics-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "report.json")

        let bytes = try DiagnosticReportWriter().write(report(), to: url)
        let data = try Data(contentsOf: url)
        #expect(data.count == bytes)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DiagnosticReport.self, from: data)
        #expect(decoded.schemaVersion == DiagnosticReport.currentSchemaVersion)
    }

    @Test("A write that fails is reported as a failure, not as a short report")
    func writeFailureIsReported() throws {
        struct Refused: Error {}
        let writer = DiagnosticReportWriter(store: { _, _ in throw Refused() })
        #expect(throws: DiagnosticReportWriteError.writeFailed) {
            try writer.write(report(), to: URL(filePath: "/tmp/unused.json"))
        }
    }

    @Test("A failed write leaves an existing report exactly as it was")
    func failedWriteLeavesTheOldFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "scribekit-diagnostics-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "report.json")
        try Data("previous".utf8).write(to: url)

        struct Refused: Error {}
        let writer = DiagnosticReportWriter(store: { _, _ in throw Refused() })
        #expect(throws: DiagnosticReportWriteError.self) { try writer.write(report(), to: url) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "previous")
    }

    @Test("The suggested filename carries nothing the user wrote")
    func filenameIsNeutral() {
        let name = DiagnosticReportWriter.filename(
            for: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(name.hasPrefix("ScribeKit-Diagnostics-"))
        #expect(name.hasSuffix(".json"))
        #expect(!name.contains(":"))
        #expect(!name.contains("/"))
    }

    @Test("Nothing is written until the user picks a destination")
    func cancellingWritesNothing() throws {
        let wrote = Mutex(false)
        let diagnostics = MeetingDiagnostics(
            runtime: ReliabilityHarness().runtime,
            writer: DiagnosticReportWriter(store: { _, _ in wrote.withLock { $0 = true } }),
            chooseDestination: { _, _ in nil },
            announceFailure: { _ in Issue.record("a cancelled export announced a failure") }
        )
        #expect(diagnostics.export() == nil)
        #expect(wrote.withLock { $0 } == false)
    }

    @Test("An export writes one report to the chosen destination")
    func exportWritesOnce() throws {
        let destination = URL(filePath: "/tmp/scribekit-export-test.json")
        let written = Mutex<[URL]>([])
        let diagnostics = MeetingDiagnostics(
            runtime: ReliabilityHarness().runtime,
            writer: DiagnosticReportWriter(store: { _, url in written.withLock { $0.append(url) } }),
            chooseDestination: { _, _ in destination },
            announceFailure: { _ in Issue.record("a successful export announced a failure") }
        )
        #expect(diagnostics.export() == destination)
        #expect(written.withLock { $0 } == [destination])
    }

    @Test("A failed export tells the user and claims no file")
    func failedExportIsAnnounced() throws {
        struct Refused: Error {}
        var announced: [String] = []
        let diagnostics = MeetingDiagnostics(
            runtime: ReliabilityHarness().runtime,
            writer: DiagnosticReportWriter(store: { _, _ in throw Refused() }),
            chooseDestination: { _, _ in URL(filePath: "/tmp/scribekit-export-test.json") },
            announceFailure: { announced.append($0) }
        )
        #expect(diagnostics.export() == nil)
        #expect(announced.count == 1)
    }

    @Test("The save panel says what a report holds and what it does not")
    func privacyMessageIsSpecific() {
        let message = MeetingDiagnostics.privacyMessage
        #expect(message.contains("does not contain transcript text"))
        #expect(message.contains("location you choose"))
        #expect(message.contains("does not"))
        // The claim ScribeKit must not make: a macOS version and a recognition
        // locale are still facts about somebody's Mac.
        #expect(!message.lowercased().contains("no personal information"))
    }

    @Test("Exporting a report does not touch a running meeting's artifacts")
    func exportingChangesNothing() async throws {
        let harness = ReliabilityHarness()
        await harness.start(retention: .compressed)
        harness.deliver(seconds: 1, count: 4)
        harness.emitFinal("hello")
        _ = await harness.wait { harness.runtime.transcriptSpanCount == 1 }

        let before = harness.persistence.entries.count
        let diagnostics = MeetingDiagnostics(
            runtime: harness.runtime,
            writer: DiagnosticReportWriter(store: { _, _ in }),
            chooseDestination: { _, _ in URL(filePath: "/tmp/scribekit-export-test.json") }
        )
        _ = diagnostics.export()

        #expect(harness.persistence.entries.count == before)
        #expect(harness.runtime.status == .transcribing)
        #expect(harness.audio.isOpen)
    }
}
