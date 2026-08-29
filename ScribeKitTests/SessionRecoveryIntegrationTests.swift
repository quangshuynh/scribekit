//
//  SessionRecoveryIntegrationTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// Recovery against the real filesystem, in a temporary folder.
///
/// The doubles elsewhere prove the policy; these prove that the policy meets
/// an actual disk — that a session left open really is recognisable
/// afterwards, and that reading it back changes not one byte of the
/// transcript. Every transcript here is synthetic text written by the test.
@Suite("Session recovery on the filesystem")
struct SessionRecoveryIntegrationTests {

    private let zone = TimeZone(identifier: "America/New_York")!

    /// 31 August 2026, 11:00:00 in ``zone``.
    private var startedAt: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 11, minute: 0))!
    }

    /// Runs work in a save folder of its own, removed afterwards.
    ///
    /// - Parameter body: The work, given the folder.
    /// - Returns: Whatever `body` returns.
    private func withSaveFolder<T>(_ body: (URL) async throws -> T) async throws -> T {
        let root = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: "ScribeKitRecovery-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        return try await body(root)
    }

    /// A meeting written into a save folder.
    ///
    /// - Parameter destination: The save folder.
    /// - Returns: The session description.
    private func session(in destination: URL) -> MeetingSession {
        MeetingSession(
            title: "Closures Walkthrough",
            createdAt: startedAt,
            selectedSources: [.application(bundleIdentifier: "com.example.Player", displayName: "QuickTime Player")],
            destination: destination
        )
    }

    /// A finalised span.
    ///
    /// - Parameters:
    ///   - text: The recognised text.
    ///   - start: Seconds from the start of the run.
    ///   - state: Whether the recogniser finalised it.
    /// - Returns: The segment.
    private func segment(
        _ text: String,
        start: Double,
        state: TranscriptSegment.RecognitionState = .final
    ) -> TranscriptSegment {
        TranscriptSegment(text: text, startTime: start, endTime: start + 2, state: state, localeIdentifier: "en-US")
    }

    /// A writer over the real filesystem, with sandbox access faked because a
    /// temporary folder carries no security scope.
    private func makeWriter() -> MarkdownTranscriptStore {
        MarkdownTranscriptStore(access: FakeSecurityScopedAccess(), timeZone: zone)
    }

    /// A recovery service over the real filesystem, as a fresh launch builds
    /// one: no shared state with the writer above.
    private func makeService() -> SessionRecoveryService {
        SessionRecoveryService(access: FakeSecurityScopedAccess(), timeZone: zone)
    }

    /// Writes a meeting and leaves it open, as a process that was killed does.
    ///
    /// - Parameter destination: The save folder.
    /// - Returns: Where the session's artifacts live.
    @discardableResult
    private func writeInterruptedMeeting(in destination: URL) async throws -> SessionArtifactLayout {
        let writer = makeWriter()
        let layout = try await writer.startSession(
            session(in: destination),
            localeIdentifier: "en-US",
            startedAt: startedAt
        )
        try await writer.appendFinalSegment(segment("Today we are learning about closures.", start: 0))
        try await writer.appendFinalSegment(segment("A closure captures the values around it.", start: 12))
        await #expect(throws: TranscriptPersistenceError.self) {
            try await writer.appendFinalSegment(
                segment("Next we will discuss", start: 24, state: .partial)
            )
        }
        try await writer.appendFinalSegment(segment("Escaping closures outlive the call.", start: 26))
        return layout
    }

    /// The transcript's bytes.
    ///
    /// - Parameter layout: Where the session's artifacts live.
    /// - Returns: The file's contents.
    private func transcriptBytes(_ layout: SessionArtifactLayout) throws -> Data {
        try Data(contentsOf: layout.transcriptURL)
    }

    // MARK: - Crash-like interruption

    @Test("A meeting that never finished is found again, with its durable text intact")
    func interruptedMeetingIsFoundWithItsText() async throws {
        try await withSaveFolder { destination in
            let layout = try await writeInterruptedMeeting(in: destination)
            let bytes = try transcriptBytes(layout)

            let report = try await makeService().scan(destination)

            let candidate = try #require(report.candidates.first)
            #expect(report.candidates.count == 1)
            #expect(candidate.metadata.title == "Closures Walkthrough")
            #expect(candidate.metadata.status == .inProgress)
            #expect(candidate.layout.directory == layout.directory)
            #expect(candidate.transcript.byteCount == bytes.count)
            #expect(candidate.transcript.modifiedAt != nil)

            let text = String(decoding: bytes, as: UTF8.self)
            #expect(text.contains("Today we are learning about closures."))
            #expect(text.contains("A closure captures the values around it."))
            #expect(text.contains("Escaping closures outlive the call."))
            #expect(!text.contains("**Ended:**"))
        }
    }

    @Test("A partial hypothesis is not resurrected as transcript text by recovery")
    func partialsAreNeverRecovered() async throws {
        try await withSaveFolder { destination in
            let layout = try await writeInterruptedMeeting(in: destination)
            let service = makeService()
            let candidate = try #require(try await service.scan(destination).candidates.first)

            _ = try await service.recordInterruption(for: candidate)

            let text = try String(decoding: transcriptBytes(layout), as: UTF8.self)
            #expect(!text.contains("Next we will discuss"))
        }
    }

    @Test("Looking for an unfinished meeting does not change one byte of its transcript")
    func inspectionPreservesTheTranscriptExactly() async throws {
        try await withSaveFolder { destination in
            let layout = try await writeInterruptedMeeting(in: destination)
            let transcriptBefore = try transcriptBytes(layout)
            let recordBefore = try Data(contentsOf: layout.metadataURL)
            let service = makeService()

            _ = try await service.scan(destination)
            _ = try await service.scan(destination)

            #expect(try transcriptBytes(layout) == transcriptBefore)
            #expect(try Data(contentsOf: layout.metadataURL) == recordBefore)
        }
    }

    // MARK: - Recording the interruption

    @Test("Recording an interruption only appends, and only once")
    func recoveryAppendsOnceAndPreservesWhatWasThere() async throws {
        try await withSaveFolder { destination in
            let layout = try await writeInterruptedMeeting(in: destination)
            let before = try transcriptBytes(layout)
            let service = makeService()
            let candidate = try #require(try await service.scan(destination).candidates.first)

            _ = try await service.recordInterruption(for: candidate)
            let afterFirst = try transcriptBytes(layout)
            _ = try? await service.recordInterruption(for: candidate)

            #expect(afterFirst.starts(with: before))
            #expect(try transcriptBytes(layout) == afterFirst)
            let added = String(decoding: afterFirst.dropFirst(before.count), as: UTF8.self)
            #expect(added.contains("> **Session interrupted.**"))
            #expect(added.ranges(of: "Session interrupted.").count == 1)
        }
    }

    @Test("A recovered transcript is still the Markdown document it was")
    func recoveredTranscriptIsStillValidMarkdown() async throws {
        try await withSaveFolder { destination in
            let layout = try await writeInterruptedMeeting(in: destination)
            let service = makeService()
            let candidate = try #require(try await service.scan(destination).candidates.first)

            _ = try await service.recordInterruption(for: candidate)

            let text = try String(decoding: transcriptBytes(layout), as: UTF8.self)
            #expect(text.hasPrefix("# Closures Walkthrough\n\n"))
            #expect(text.contains("## Transcript\n\n"))
            #expect(text.hasSuffix("\n\n"))
            #expect(text.ranges(of: "# Closures Walkthrough").count == 1)
        }
    }

    @Test("A meeting recorded as interrupted is not offered again")
    func recordedInterruptionsAreNotOfferedAgain() async throws {
        try await withSaveFolder { destination in
            let layout = try await writeInterruptedMeeting(in: destination)
            let service = makeService()
            let candidate = try #require(try await service.scan(destination).candidates.first)

            _ = try await service.recordInterruption(for: candidate)

            #expect(try await service.scan(destination).isEmpty)
            let record = try SessionRecoveryMetadata.decoded(from: Data(contentsOf: layout.metadataURL))
            #expect(record.status == .interrupted)
            #expect(record.interruptedAt != nil)
        }
    }

    // MARK: - Sessions that ended properly

    @Test("A meeting stopped normally is not offered as unfinished afterwards")
    func completedMeetingIsNotOffered() async throws {
        try await withSaveFolder { destination in
            let writer = makeWriter()
            let layout = try await writer.startSession(
                session(in: destination),
                localeIdentifier: "en-US",
                startedAt: startedAt
            )
            try await writer.appendFinalSegment(segment("A finished meeting.", start: 0))
            try await writer.finishSession(endedAt: startedAt.addingTimeInterval(64))

            let report = try await makeService().scan(destination)

            #expect(report.isEmpty)
            let record = try SessionRecoveryMetadata.decoded(from: Data(contentsOf: layout.metadataURL))
            #expect(record.status == .completed)
            #expect(record.endedAt == startedAt.addingTimeInterval(64))
            #expect(try String(decoding: transcriptBytes(layout), as: UTF8.self).contains("**Ended:**"))
        }
    }

    @Test("The session record lives in a hidden folder beside the transcript")
    func recordSitsWhereTheLayoutSaysItDoes() async throws {
        try await withSaveFolder { destination in
            let layout = try await writeInterruptedMeeting(in: destination)

            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(
                atPath: layout.metadataDirectory.path(percentEncoded: false),
                isDirectory: &isDirectory
            ))
            #expect(isDirectory.boolValue)
            #expect(layout.metadataDirectory.lastPathComponent == ".scribekit")
            #expect(layout.metadataURL.lastPathComponent == "session.json")
            #expect(try FileManager.default.contentsOfDirectory(
                atPath: layout.directory.path(percentEncoded: false)
            ).sorted() == [".scribekit", "transcript.md"])
        }
    }

    // MARK: - Damage on a real disk

    @Test("A record damaged on disk is reported and neither repaired nor removed")
    func damagedRecordOnDiskIsLeftAlone() async throws {
        try await withSaveFolder { destination in
            let layout = try await writeInterruptedMeeting(in: destination)
            let transcriptBefore = try transcriptBytes(layout)
            let damaged = Data(#"{"schemaVersion": 1, "title": "#.utf8)
            try damaged.write(to: layout.metadataURL)

            let report = try await makeService().scan(destination)

            #expect(report.candidates.isEmpty)
            #expect(report.problems.map(\.error) == [.metadataMalformed])
            #expect(try Data(contentsOf: layout.metadataURL) == damaged)
            #expect(try transcriptBytes(layout) == transcriptBefore)
        }
    }

    @Test("A record naming a transcript that has been deleted is reported as inconsistent")
    func missingTranscriptOnDiskIsReported() async throws {
        try await withSaveFolder { destination in
            let layout = try await writeInterruptedMeeting(in: destination)
            try FileManager.default.removeItem(at: layout.transcriptURL)

            let report = try await makeService().scan(destination)

            #expect(report.candidates.isEmpty)
            #expect(report.problems.map(\.error) == [.transcriptMissing])
            #expect(!FileManager.default.fileExists(atPath: layout.transcriptURL.path(percentEncoded: false)))
        }
    }

    @Test("A folder that is not there is reported rather than replaced with another")
    func missingDestinationIsReported() async throws {
        try await withSaveFolder { destination in
            let absent = destination.appending(path: "not-a-folder", directoryHint: .isDirectory)

            await #expect(throws: SessionRecoveryError.destinationUnavailable) {
                try await makeService().scan(absent)
            }
        }
    }

    @Test("Folders in the save location that ScribeKit did not write are left out of it")
    func unrelatedFoldersAreIgnored() async throws {
        try await withSaveFolder { destination in
            try FileManager.default.createDirectory(
                at: destination.appending(path: "Holiday Photos", directoryHint: .isDirectory),
                withIntermediateDirectories: false
            )
            try Data("not a session".utf8).write(
                to: destination.appending(path: "notes.txt", directoryHint: .notDirectory)
            )
            try await writeInterruptedMeeting(in: destination)

            let report = try await makeService().scan(destination)

            #expect(report.candidates.count == 1)
            #expect(report.problems.isEmpty)
        }
    }
}
