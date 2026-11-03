//
//  TranscriptExportIntegrationTests.swift
//  ScribeKitTests
//

import CryptoKit
import Foundation
import Testing
@testable import ScribeKit

/// A remembered save folder, without a bookmark or the sandbox.
private nonisolated final class FixedSaveLocation: SaveLocationPersisting, @unchecked Sendable {
    let folder: URL?
    init(_ folder: URL?) { self.folder = folder }
    func save(_ url: URL) throws {}
    func restore() throws -> URL? { folder }
    func clear() throws {}
}

/// A sealer that cannot read anything, as a volume that went away between
/// closing a transcript and reading it back would.
private nonisolated struct FailingSealer: TranscriptSealing {
    func seal(transcriptAt url: URL) throws -> TranscriptSeal { throw CocoaError(.fileReadUnknown) }
}

/// Sealing at Stop, integrity in History, and export, against a real
/// filesystem in a temporary folder.
///
/// Every transcript is synthetic text written by the test. No test reaches
/// the network or any location outside its own temporary folders.
@Suite("Transcript sealing, integrity and export on the filesystem")
struct TranscriptExportIntegrationTests {

    private let zone = TranscriptFixture.zone

    // MARK: - Helpers

    /// Runs work with a save folder and a separate export folder, both removed
    /// afterwards.
    private func withFolders<T>(_ body: (_ saveFolder: URL, _ exports: URL) async throws -> T) async throws -> T {
        let root = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: "ScribeKitExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        let saveFolder = root.appending(path: "Meetings", directoryHint: .isDirectory)
        let exports = root.appending(path: "Exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        defer {
            // Restore permissions a test may have removed, so cleanup succeeds.
            if let enumerator = FileManager.default.enumerator(atPath: root.path(percentEncoded: false)) {
                while let path = enumerator.nextObject() as? String {
                    try? FileManager.default.setAttributes(
                        [.posixPermissions: 0o755],
                        ofItemAtPath: root.appending(path: path).path(percentEncoded: false)
                    )
                }
            }
            try? FileManager.default.removeItem(at: root)
        }
        return try await body(saveFolder, exports)
    }

    private func meeting(in destination: URL, title: String = "Closures Walkthrough") -> MeetingSession {
        MeetingSession(
            title: title,
            createdAt: TranscriptFixture.startedAt,
            selectedSources: [.application(bundleIdentifier: "com.example.Player", displayName: "QuickTime Player")],
            destination: destination
        )
    }

    private func segment(_ text: String, start: Double) -> TranscriptSegment {
        TranscriptSegment(text: text, startTime: start, endTime: start + 2, state: .final, localeIdentifier: "en-US")
    }

    /// Records a whole meeting through the real writer.
    @discardableResult
    private func recordMeeting(
        in destination: URL,
        texts: [String] = ["Today we are learning about closures.", "Naïve café — 東京 🚀, “quoted”."],
        outcome: SessionCompletionOutcome = .completed,
        sealer: any TranscriptSealing = FileTranscriptSealer(),
        title: String = "Closures Walkthrough"
    ) async throws -> SessionArtifactLayout {
        let writer = MarkdownTranscriptStore(sealer: sealer, access: FakeSecurityScopedAccess(), timeZone: zone)
        let layout = try await writer.startSession(
            meeting(in: destination, title: title),
            localeIdentifier: "en-US",
            startedAt: TranscriptFixture.startedAt
        )
        for (index, text) in texts.enumerated() {
            try await writer.appendFinalSegment(segment(text, start: Double(index) * 12))
        }
        try await writer.finishSession(
            endedAt: TranscriptFixture.startedAt.addingTimeInterval(90),
            outcome: outcome,
            capturedDuration: 90
        )
        return layout
    }

    private func record(_ layout: SessionArtifactLayout) throws -> SessionRecoveryMetadata {
        try SessionRecoveryMetadata.decoded(from: Data(contentsOf: layout.metadataURL))
    }

    private func load(_ destination: URL) async throws -> HistoryReport {
        try await HistoryService(store: FileManagerHistoryStore(), access: FakeSecurityScopedAccess()).load(destination)
    }

    private func exporter(_ access: FakeSecurityScopedAccess = FakeSecurityScopedAccess()) -> TranscriptExporter {
        TranscriptExporter(files: FileManagerTranscriptExportFiles(), access: access)
    }

    /// The SHA-256 and modification date of every regular file under a
    /// folder, keyed by path, so a test can prove nothing changed and nothing
    /// was added.
    private func fingerprints(of root: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]
        )
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { continue }
            let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            result[url.path(percentEncoded: false)] =
                digest + "@\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }
        return result
    }

    /// Writes a session directory by hand, as an earlier version or the user
    /// would have left it.
    @discardableResult
    private func writeSession(
        _ name: String,
        in destination: URL,
        transcript: Data,
        status: SessionRecoveryStatus = .completed,
        seal: TranscriptSeal?,
        writesRecord: Bool = true
    ) throws -> SessionArtifactLayout {
        let layout = SessionArtifactLayout(destination: destination, directoryName: name)
        try FileManager.default.createDirectory(at: layout.directory, withIntermediateDirectories: true)
        try transcript.write(to: layout.transcriptURL)
        if writesRecord {
            try FileManager.default.createDirectory(at: layout.metadataDirectory, withIntermediateDirectories: true)
            try SessionRecoveryMetadata(
                sessionID: UUID(),
                title: "Synthetic Meeting",
                startedAt: TranscriptFixture.startedAt,
                sourceNames: ["QuickTime Player"],
                localeIdentifier: "en-US",
                status: status,
                endedAt: status == .inProgress ? nil : TranscriptFixture.startedAt.addingTimeInterval(60),
                transcriptSeal: seal
            ).encoded().write(to: layout.metadataURL)
        }
        return layout
    }

    // MARK: - Sealing at Stop

    @Test("A meeting closed normally records the seal of exactly the bytes on disk")
    func stopSealsTheClosedTranscript() async throws {
        try await withFolders { saveFolder, _ in
            let layout = try await recordMeeting(in: saveFolder)

            let stored = try record(layout)
            #expect(stored.status == .completed)
            #expect(stored.transcriptSeal == TranscriptSeal.sealing(try Data(contentsOf: layout.transcriptURL)))
            // The seal is metadata: the Markdown carries no checksum, and the
            // folder holds nothing new.
            #expect(!(try String(contentsOf: layout.transcriptURL, encoding: .utf8)).contains("sha256"))
            #expect(try FileManager.default.contentsOfDirectory(atPath: layout.directory.path(percentEncoded: false))
                .sorted() == [".scribekit", "transcript.md"])
        }
    }

    @Test("A meeting whose capture ended by itself is sealed as the file it closed")
    func interruptedByCaptureIsSealed() async throws {
        try await withFolders { saveFolder, _ in
            let layout = try await recordMeeting(in: saveFolder, outcome: .interrupted)
            let stored = try record(layout)
            #expect(stored.status == .interrupted)
            #expect(stored.transcriptSeal == TranscriptSeal.sealing(try Data(contentsOf: layout.transcriptURL)))
            #expect(try await load(saveFolder).sessions.first?.integrity == .verified)
        }
    }

    @Test("A transcript that cannot be read back still records the completion, without a seal")
    func sealFailureNeverFailsAMeeting() async throws {
        try await withFolders { saveFolder, _ in
            let layout = try await recordMeeting(in: saveFolder, sealer: FailingSealer())
            let stored = try record(layout)
            #expect(stored.status == .completed)
            #expect(stored.transcriptSeal == nil)
            #expect(try await load(saveFolder).sessions.first?.integrity == .unverified(.notRecorded))
        }
    }

    // MARK: - Integrity in History

    @Test("History verifies an untouched transcript and reports a modified or truncated one as changed")
    func historyDistinguishesVerifiedAndChanged() async throws {
        try await withFolders { saveFolder, _ in
            let untouched = try await recordMeeting(in: saveFolder, title: "Untouched")
            let edited = try await recordMeeting(in: saveFolder, title: "Edited")
            let truncated = try await recordMeeting(in: saveFolder, title: "Truncated")

            let editedBytes = try Data(contentsOf: edited.transcriptURL)
            let addition = Data("\nA line added outside ScribeKit.\n".utf8)
            try (editedBytes + addition).write(to: edited.transcriptURL)
            let truncatedBytes = try Data(contentsOf: truncated.transcriptURL)
            try truncatedBytes.prefix(truncatedBytes.count / 2).write(to: truncated.transcriptURL)
            let recordsBefore = try [edited, truncated].map { try Data(contentsOf: $0.metadataURL) }

            let report = try await load(saveFolder)
            let byTitle = Dictionary(uniqueKeysWithValues: report.sessions.map { ($0.title, $0) })

            #expect(byTitle["Untouched"]?.integrity == .verified)
            #expect(byTitle["Edited"]?.integrity == .changed(
                expectedByteCount: editedBytes.count,
                observedByteCount: editedBytes.count + addition.count
            ))
            #expect(byTitle["Truncated"]?.integrity == .changed(
                expectedByteCount: truncatedBytes.count,
                observedByteCount: truncatedBytes.count / 2
            ))
            // A changed transcript is still listed and searched, and neither it
            // nor its seal was rewritten to agree.
            #expect(report.problems.isEmpty)
            #expect(TranscriptSearch.results(for: "closures", in: TranscriptSearchIndex(report.documents)).count >= 2)
            #expect(try [edited, truncated].map { try Data(contentsOf: $0.metadataURL) } == recordsBefore)
            #expect(try Data(contentsOf: truncated.transcriptURL).count == truncatedBytes.count / 2)
            _ = untouched
        }
    }

    @Test("Meetings from before seals existed, or with no record at all, are unverified and fully usable")
    func legacyMeetingsAreUnverifiedNotCorrupt() async throws {
        try await withFolders { saveFolder, _ in
            let text = TranscriptFixture.transcript(texts: ["A closure captures the variables it refers to."])
            // A record as v0.1.0 and v0.2.0 wrote it, with no seal, and a
            // transcript from before session records existed at all.
            try writeSession("2026-08-29-recorded", in: saveFolder, transcript: Data(text.utf8), seal: nil)
            try writeSession("2026-08-29-unrecorded", in: saveFolder, transcript: Data(text.utf8), seal: nil,
                             writesRecord: false)

            let report = try await load(saveFolder)

            #expect(report.problems.isEmpty)
            let verdicts = Dictionary(uniqueKeysWithValues: report.sessions.map {
                ($0.directory.lastPathComponent, $0.integrity)
            })
            #expect(verdicts["2026-08-29-recorded"] == .unverified(.notRecorded))
            #expect(verdicts["2026-08-29-unrecorded"] == .unverified(.noRecord))
            #expect(report.sessions.allSatisfy { !$0.integrity.isWarning })
            #expect(report.documents.allSatisfy { !$0.spans.isEmpty })
        }
    }

    @Test("A meeting killed mid-write is unverified, and stays so after recovery appends its notice")
    func interruptedWriteAndRecovery() async throws {
        try await withFolders { saveFolder, _ in
            // A writer that is never finished is what a killed process leaves.
            let writer = MarkdownTranscriptStore(access: FakeSecurityScopedAccess(), timeZone: zone)
            let layout = try await writer.startSession(
                meeting(in: saveFolder), localeIdentifier: "en-US", startedAt: TranscriptFixture.startedAt
            )
            try await writer.appendFinalSegment(segment("Escaping closures outlive the call.", start: 0))

            #expect(try record(layout).transcriptSeal == nil)
            #expect(try await load(saveFolder).sessions.first?.integrity == .unverified(.stillOpen))

            let recovery = SessionRecoveryService(access: FakeSecurityScopedAccess(), timeZone: zone)
            let candidate = try #require(try await recovery.scan(saveFolder).candidates.first)
            _ = try await recovery.recordInterruption(for: candidate)

            let recovered = try #require(try await load(saveFolder).sessions.first)
            #expect(recovered.status == .interrupted)
            #expect(recovered.integrity == .unverified(.interruptedBeforeSealing))
            #expect(try record(layout).transcriptSeal == nil)
        }
    }

    @Test("Verifying History leaves every artifact byte-identical and adds no file")
    func verificationChangesNothing() async throws {
        try await withFolders { saveFolder, _ in
            try await recordMeeting(in: saveFolder, title: "Sealed")
            let edited = try await recordMeeting(in: saveFolder, title: "Edited")
            try Data("# Replaced\n".utf8).write(to: edited.transcriptURL)
            let before = try fingerprints(of: saveFolder)

            _ = try await load(saveFolder)
            _ = try await load(saveFolder)

            #expect(try fingerprints(of: saveFolder) == before)
        }
    }

    // MARK: - Export

    @Test("Exporting an unchanged transcript writes its exact bytes and changes nothing in the meeting")
    func exportIsByteForByte() async throws {
        try await withFolders { saveFolder, exports in
            try await recordMeeting(in: saveFolder)
            let session = try #require(try await load(saveFolder).sessions.first)
            let before = try fingerprints(of: saveFolder)
            let target = exports.appending(path: "copy.md")

            let result = try await exporter().export(session, from: saveFolder, to: target)

            let original = try Data(contentsOf: session.transcriptURL)
            #expect(try Data(contentsOf: target) == original)
            #expect(result.byteCount == original.count)
            #expect(result.integrity == .verified)
            #expect(result.destination == target)
            #expect(try fingerprints(of: saveFolder) == before)
        }
    }

    @Test("Unicode, CRLF and multiline Markdown survive export unchanged")
    func exportPreservesUnicodeAndLineEndings() async throws {
        try await withFolders { saveFolder, exports in
            let bytes = Data(TranscriptIntegrityTests.unicodeMarkdown.utf8)
            try writeSession("2026-08-29-unicode", in: saveFolder, transcript: bytes, seal: .sealing(bytes))
            let session = try #require(try await load(saveFolder).sessions.first)
            #expect(session.integrity == .verified)

            let target = exports.appending(path: "Réunion 東京.md")
            let result = try await exporter().export(session, from: saveFolder, to: target)

            #expect(try Data(contentsOf: target) == bytes)
            #expect(result.integrity == .verified)
        }
    }

    @Test("Repeated exports produce identical copies, and re-exporting to the same file replaces it whole")
    func repeatedExportsAreIdentical() async throws {
        try await withFolders { saveFolder, exports in
            try await recordMeeting(in: saveFolder)
            let session = try #require(try await load(saveFolder).sessions.first)
            let exporter = exporter()
            let first = exports.appending(path: "first.md")
            let second = exports.appending(path: "second.md")
            try Data(String(repeating: "stale ", count: 10_000).utf8).write(to: second)

            _ = try await exporter.export(session, from: saveFolder, to: first)
            _ = try await exporter.export(session, from: saveFolder, to: second)
            _ = try await exporter.export(session, from: saveFolder, to: first)

            let original = try Data(contentsOf: session.transcriptURL)
            #expect(try Data(contentsOf: first) == original)
            #expect(try Data(contentsOf: second) == original)
        }
    }

    @Test("A changed transcript is still exported as it is now, and says so")
    func changedTranscriptExportsWithItsVerdict() async throws {
        try await withFolders { saveFolder, exports in
            let layout = try await recordMeeting(in: saveFolder)
            let edited = Data("# Edited outside ScribeKit\n".utf8)
            try edited.write(to: layout.transcriptURL)
            let session = try #require(try await load(saveFolder).sessions.first)

            let result = try await exporter().export(session, from: saveFolder, to: exports.appending(path: "x.md"))

            #expect(try Data(contentsOf: exports.appending(path: "x.md")) == edited)
            if case .changed = result.integrity {} else { Issue.record("Expected a changed verdict") }
            #expect(try Data(contentsOf: layout.transcriptURL) == edited)
        }
    }

    @Test("A transcript changed after History listed it is described as it is at export")
    func verdictIsTakenAtExport() async throws {
        try await withFolders { saveFolder, exports in
            let layout = try await recordMeeting(in: saveFolder)
            let session = try #require(try await load(saveFolder).sessions.first)
            #expect(session.integrity == .verified)
            try Data("# Replaced after listing\n".utf8).write(to: layout.transcriptURL)

            let result = try await exporter().export(session, from: saveFolder, to: exports.appending(path: "y.md"))

            if case .changed = result.integrity {} else { Issue.record("Expected a changed verdict") }
        }
    }

    @Test("A legacy transcript exports and is reported as unverified")
    func legacyTranscriptExports() async throws {
        try await withFolders { saveFolder, exports in
            let text = Data(TranscriptFixture.transcript(texts: ["Nothing to report."]).utf8)
            try writeSession("2026-08-29-legacy", in: saveFolder, transcript: text, seal: nil, writesRecord: false)
            let session = try #require(try await load(saveFolder).sessions.first)

            let result = try await exporter().export(session, from: saveFolder, to: exports.appending(path: "l.md"))

            #expect(result.integrity == .unverified(.noRecord))
            #expect(try Data(contentsOf: exports.appending(path: "l.md")) == text)
        }
    }

    @Test("A transcript moved or deleted after listing is reported missing, and nothing is written")
    func missingTranscriptIsReported() async throws {
        try await withFolders { saveFolder, exports in
            let layout = try await recordMeeting(in: saveFolder)
            let session = try #require(try await load(saveFolder).sessions.first)
            try FileManager.default.moveItem(
                at: layout.directory,
                to: saveFolder.appending(path: "moved-elsewhere", directoryHint: .isDirectory)
            )
            let target = exports.appending(path: "copy.md")

            await #expect(throws: TranscriptExportError.transcriptMissing) {
                try await exporter().export(session, from: saveFolder, to: target)
            }
            #expect(!FileManager.default.fileExists(atPath: target.path(percentEncoded: false)))
        }
    }

    @Test("An unreadable transcript is reported, left as it is, and nothing is written")
    func unreadableTranscriptIsReported() async throws {
        try await withFolders { saveFolder, exports in
            let layout = try await recordMeeting(in: saveFolder)
            let session = try #require(try await load(saveFolder).sessions.first)
            let path = layout.transcriptURL.path(percentEncoded: false)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
            // A process that can read the file anyway (running as root) cannot
            // exercise this path; say so rather than pass vacuously.
            guard !FileManager.default.isReadableFile(atPath: path) else {
                Issue.record("This test needs a process that file permissions apply to")
                return
            }
            let target = exports.appending(path: "copy.md")

            await #expect(throws: TranscriptExportError.transcriptUnreadable) {
                try await exporter().export(session, from: saveFolder, to: target)
            }
            #expect(!FileManager.default.fileExists(atPath: target.path(percentEncoded: false)))
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
            #expect(try record(layout).transcriptSeal == .sealing(try Data(contentsOf: layout.transcriptURL)))
        }
    }

    @Test("The transcript itself, or anywhere inside a meeting folder, is refused before anything is written")
    func destinationsThatWouldTouchAMeetingAreRefused() async throws {
        try await withFolders { saveFolder, _ in
            let layout = try await recordMeeting(in: saveFolder)
            let other = try await recordMeeting(in: saveFolder, title: "Another Meeting")
            let name = layout.directory.lastPathComponent
            let sessions = try await load(saveFolder).sessions
            let session = try #require(sessions.first { $0.directory.lastPathComponent == name })
            let before = try fingerprints(of: saveFolder)
            let exporter = exporter()

            await #expect(throws: TranscriptExportError.destinationIsTranscript) {
                try await exporter.export(session, from: saveFolder, to: layout.transcriptURL)
            }
            for target in [
                layout.directory.appending(path: "transcript copy.md"),
                layout.metadataDirectory.appending(path: "session.json"),
                other.transcriptURL,
                other.directory.appending(path: "notes.md")
            ] {
                await #expect(throws: TranscriptExportError.destinationInsideMeeting) {
                    try await exporter.export(session, from: saveFolder, to: target)
                }
            }
            #expect(try fingerprints(of: saveFolder) == before)
        }
    }

    @Test("A path to the transcript through a symbolic link is still the transcript")
    func symbolicLinksAreResolved() async throws {
        try await withFolders { saveFolder, exports in
            let layout = try await recordMeeting(in: saveFolder)
            let session = try #require(try await load(saveFolder).sessions.first)
            let link = exports.appending(path: "link", directoryHint: .isDirectory)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: layout.directory)

            await #expect(throws: TranscriptExportError.destinationIsTranscript) {
                try await exporter().export(session, from: saveFolder, to: link.appending(path: "transcript.md"))
            }
            await #expect(throws: TranscriptExportError.destinationInsideMeeting) {
                try await exporter().export(session, from: saveFolder, to: link.appending(path: "copy.md"))
            }
        }
    }

    @Test("A copy beside the meetings in the save folder itself is allowed and lists as nothing")
    func saveFolderRootIsAllowed() async throws {
        try await withFolders { saveFolder, _ in
            try await recordMeeting(in: saveFolder)
            let session = try #require(try await load(saveFolder).sessions.first)
            let target = saveFolder.appending(path: "copy.md")

            _ = try await exporter().export(session, from: saveFolder, to: target)

            #expect(try Data(contentsOf: target) == Data(contentsOf: session.transcriptURL))
            #expect(try await load(saveFolder).sessions.count == 1)
        }
    }

    @Test("A destination that is a folder, or in a folder that does not exist, fails without a partial file")
    func invalidDestinationsFail() async throws {
        try await withFolders { saveFolder, exports in
            try await recordMeeting(in: saveFolder)
            let session = try #require(try await load(saveFolder).sessions.first)

            await #expect(throws: TranscriptExportError.invalidDestination) {
                try await exporter().export(session, from: saveFolder, to: exports)
            }
            await #expect(throws: TranscriptExportError.invalidDestination) {
                try await exporter().export(session, from: saveFolder, to: URL(string: "https://example.com/t.md")!)
            }
            let nowhere = exports.appending(path: "missing-folder/copy.md")
            await #expect(throws: TranscriptExportError.writeFailed) {
                try await exporter().export(session, from: saveFolder, to: nowhere)
            }
            #expect(!FileManager.default.fileExists(atPath: nowhere.path(percentEncoded: false)))
            #expect(try FileManager.default.contentsOfDirectory(atPath: exports.path(percentEncoded: false)).isEmpty)
        }
    }

    @Test("A meeting still being written is not exported")
    func inProgressIsNotExported() async throws {
        try await withFolders { saveFolder, exports in
            let bytes = Data(TranscriptFixture.transcript(texts: ["Still going."], includesFooter: false).utf8)
            try writeSession("2026-08-29-live", in: saveFolder, transcript: bytes, status: .inProgress, seal: nil)
            let session = try #require(try await load(saveFolder).sessions.first)
            let target = exports.appending(path: "copy.md")

            await #expect(throws: TranscriptExportError.meetingNotFinished) {
                try await exporter().export(session, from: saveFolder, to: target)
            }
            #expect(!FileManager.default.fileExists(atPath: target.path(percentEncoded: false)))
        }
    }

    @Test("Access to the save folder is held only for the export and always released")
    func accessIsBalanced() async throws {
        try await withFolders { saveFolder, exports in
            try await recordMeeting(in: saveFolder)
            let session = try #require(try await load(saveFolder).sessions.first)
            let access = FakeSecurityScopedAccess()

            _ = try await exporter(access).export(session, from: saveFolder, to: exports.appending(path: "a.md"))
            _ = try? await exporter(access).export(session, from: saveFolder, to: session.transcriptURL)

            #expect(!access.started.isEmpty)
            #expect(access.isBalanced)

            let refused = FakeSecurityScopedAccess(isGranted: false)
            await #expect(throws: TranscriptExportError.folderUnavailable) {
                try await exporter(refused).export(session, from: saveFolder, to: exports.appending(path: "b.md"))
            }
            #expect(!FileManager.default.fileExists(atPath: exports.appending(path: "b.md").path(percentEncoded: false)))
        }
    }

    @Test("Export from the History screen writes the copy and reports it, end to end")
    @MainActor
    func historyScreenExportsEndToEnd() async throws {
        try await withFolders { saveFolder, exports in
            try await recordMeeting(in: saveFolder)
            let target = exports.appending(path: "from-history.md")
            var offered: (name: String, message: String)?
            let model = HistoryModel(
                service: HistoryService(store: FileManagerHistoryStore(), access: FakeSecurityScopedAccess()),
                saveLocation: FixedSaveLocation(saveFolder),
                exporter: TranscriptExporter(access: FakeSecurityScopedAccess()),
                chooseExportDestination: { name, message in
                    offered = (name, message)
                    return target
                }
            )
            await model.load()
            let session = try #require(model.documents.first?.session)
            await model.selectSession(session.id)
            let before = try fingerprints(of: saveFolder)

            await model.exportTranscript(of: session)

            #expect(offered?.name == session.directory.lastPathComponent + ".md")
            #expect(offered?.message.contains("nothing is uploaded") == true)
            guard case let .exported(id, result) = model.exportFeedback(for: session.id) else {
                Issue.record("Expected an exported state, got \(model.exportState)")
                return
            }
            #expect(id == session.id)
            #expect(result.integrity == .verified)
            #expect(try Data(contentsOf: target) == Data(contentsOf: session.transcriptURL))
            #expect(try fingerprints(of: saveFolder) == before)
        }
    }
}
