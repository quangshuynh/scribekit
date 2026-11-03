//
//  TranscriptExportTests.swift
//  ScribeKitTests
//

import Foundation
import Synchronization
import Testing
@testable import ScribeKit

/// Export file operations in memory, able to fail or corrupt on demand, so the
/// exporter's refusal and confirmation paths are testable without arranging a
/// failing disk.
private nonisolated final class FakeExportFiles: TranscriptExportFiling, @unchecked Sendable {

    private struct State {
        var transcripts: [String: Data] = [:]
        var meetingDirectories: Set<String> = []
        var copies: [String: Data] = [:]
        var writeFails = false
        var corruptsCopies = false
        var readBackFails = false
        var removals: [String] = []
    }

    private let state = Mutex(State())

    func addTranscript(_ data: Data, at url: URL) {
        state.withLock { $0.transcripts[url.path(percentEncoded: false)] = data }
    }

    func failWrites() { state.withLock { $0.writeFails = true } }
    func corruptCopies() { state.withLock { $0.corruptsCopies = true } }
    func failReadBack() { state.withLock { $0.readBackFails = true } }

    func copy(at url: URL) -> Data? { state.withLock { $0.copies[url.path(percentEncoded: false)] } }
    var removals: [String] { state.withLock { $0.removals } }
    var transcriptBytes: [String: Data] { state.withLock { $0.transcripts } }

    func readTranscript(at url: URL) throws -> Data {
        guard let data = state.withLock({ $0.transcripts[url.path(percentEncoded: false)] }) else {
            throw TranscriptExportError.transcriptMissing
        }
        return data
    }

    func isMeetingDirectory(_ url: URL) -> Bool {
        state.withLock { $0.meetingDirectories.contains(url.standardizedFileURL.path(percentEncoded: false)) }
    }

    func writeCopy(_ data: Data, to url: URL) throws {
        try state.withLock { state in
            if state.writeFails { throw CocoaError(.fileWriteOutOfSpace) }
            state.copies[url.path(percentEncoded: false)] = state.corruptsCopies ? data.dropLast() : data
        }
    }

    func readCopy(at url: URL) throws -> Data {
        try state.withLock { state in
            if state.readBackFails { throw CocoaError(.fileReadNoPermission) }
            guard let data = state.copies[url.path(percentEncoded: false)] else { throw CocoaError(.fileNoSuchFile) }
            return data
        }
    }

    func removeCopy(at url: URL) throws {
        state.withLock { state in
            state.copies[url.path(percentEncoded: false)] = nil
            state.removals.append(url.path(percentEncoded: false))
        }
    }
}

/// A remembered save folder, without a bookmark or the sandbox.
private nonisolated final class ExportSaveLocation: SaveLocationPersisting, @unchecked Sendable {
    let folder: URL
    init(_ folder: URL) { self.folder = folder }
    func save(_ url: URL) throws {}
    func restore() throws -> URL? { folder }
    func clear() throws {}
}

@Suite("Transcript export")
struct TranscriptExportTests {

    private let saveFolder = URL(filePath: "/Users/example/Meetings", directoryHint: .isDirectory)
    private let target = URL(filePath: "/Users/example/Desktop/copy.md")
    private let bytes = Data(TranscriptIntegrityTests.unicodeMarkdown.utf8)

    private func session(
        _ name: String = "2026-08-29-closures-walkthrough",
        status: HistorySessionStatus = .completed,
        seal: TranscriptSeal? = nil
    ) -> HistorySession {
        let directory = saveFolder.appending(path: name, directoryHint: .isDirectory)
        return HistorySession(
            directory: directory,
            sessionID: UUID(),
            title: "Closures Walkthrough",
            status: status,
            startedAt: TranscriptFixture.startedAt,
            endedAt: status == .inProgress ? nil : TranscriptFixture.startedAt.addingTimeInterval(60),
            sourceNames: ["QuickTime Player"],
            localeIdentifier: "en-US",
            transcriptURL: SessionArtifactLayout(directory: directory).transcriptURL,
            transcript: SessionFileInfo(byteCount: bytes.count, modifiedAt: nil),
            audioRetention: nil,
            audio: nil,
            transcriptSeal: seal
        )
    }

    private func exporter(_ files: FakeExportFiles) -> TranscriptExporter {
        TranscriptExporter(files: files, access: FakeSecurityScopedAccess())
    }

    @Test("A copy is the transcript's bytes, and the verdict comes from those bytes")
    func copyIsExact() async throws {
        let files = FakeExportFiles()
        let sealed = session(seal: .sealing(bytes))
        files.addTranscript(bytes, at: sealed.transcriptURL)

        let result = try await exporter(files).export(sealed, from: saveFolder, to: target)

        #expect(files.copy(at: target) == bytes)
        #expect(result == TranscriptExportResult(destination: target, byteCount: bytes.count, integrity: .verified))
        #expect(files.transcriptBytes == [sealed.transcriptURL.path(percentEncoded: false): bytes])
    }

    @Test("A copy that does not read back identically is removed and reported")
    func mismatchedCopyIsRemoved() async throws {
        let files = FakeExportFiles()
        let unsealed = session()
        files.addTranscript(bytes, at: unsealed.transcriptURL)
        files.corruptCopies()

        await #expect(throws: TranscriptExportError.verificationFailed) {
            try await exporter(files).export(unsealed, from: saveFolder, to: target)
        }
        #expect(files.copy(at: target) == nil)
        #expect(files.removals == [target.path(percentEncoded: false)])
    }

    @Test("A copy that cannot be read back is reported as unconfirmed and left where the user put it")
    func unconfirmedCopyIsLeft() async throws {
        let files = FakeExportFiles()
        let unsealed = session()
        files.addTranscript(bytes, at: unsealed.transcriptURL)
        files.failReadBack()

        await #expect(throws: TranscriptExportError.couldNotConfirm) {
            try await exporter(files).export(unsealed, from: saveFolder, to: target)
        }
        #expect(files.removals.isEmpty)
    }

    @Test("A failed write is reported as one and leaves no copy")
    func failedWriteLeavesNothing() async throws {
        let files = FakeExportFiles()
        let unsealed = session()
        files.addTranscript(bytes, at: unsealed.transcriptURL)
        files.failWrites()

        await #expect(throws: TranscriptExportError.writeFailed) {
            try await exporter(files).export(unsealed, from: saveFolder, to: target)
        }
        #expect(files.copy(at: target) == nil)
    }

    @Test("Destinations are refused by where they are, not by their name")
    func destinationValidation() throws {
        let meeting = session()
        let validate = { (url: URL) in
            try TranscriptExporter.validate(destination: url, for: meeting, saveFolder: saveFolder) { _ in true }
        }

        #expect(throws: TranscriptExportError.destinationIsTranscript) { try validate(meeting.transcriptURL) }
        #expect(throws: TranscriptExportError.destinationIsTranscript) {
            try validate(meeting.directory.appending(path: "./sub/../transcript.md"))
        }
        #expect(throws: TranscriptExportError.destinationInsideMeeting) {
            try validate(meeting.directory.appending(path: "copy.md"))
        }
        #expect(throws: TranscriptExportError.destinationInsideMeeting) {
            try validate(saveFolder.appending(path: "another-meeting/transcript.md"))
        }
        #expect(throws: TranscriptExportError.invalidDestination) {
            try validate(URL(filePath: "/Users/example/Desktop/", directoryHint: .isDirectory))
        }
        // Beside the meetings, and anywhere outside the save folder, is fine;
        // so is a folder under the save folder that is not a meeting.
        try validate(saveFolder.appending(path: "transcript.md"))
        try validate(URL(filePath: "/Users/example/Desktop/transcript.md"))
        try TranscriptExporter.validate(
            destination: saveFolder.appending(path: "Exports/copy.md"),
            for: meeting,
            saveFolder: saveFolder
        ) { _ in false }
    }

    @Test("The offered name is the meeting folder's own, as Markdown")
    func suggestedName() {
        #expect(TranscriptExporter.suggestedFilename(for: session("2026-08-29-standup-2")) == "2026-08-29-standup-2.md")
    }

    // MARK: - History screen

    /// A History model over an in-memory folder holding one meeting, with an
    /// exporter over in-memory files and a save panel that answers `target`.
    @MainActor
    private func makeModel(
        status: SessionRecoveryStatus = .completed,
        answer: URL?
    ) throws -> (HistoryModel, FakeExportFiles, () -> Int) {
        let store = FakeHistoryStore()
        let directory = saveFolder.appending(path: "2026-08-29-closures-walkthrough", directoryHint: .isDirectory)
        let text = TranscriptFixture.transcript(texts: ["A closure captures the variables it refers to."])
        try store.addSession(
            directory,
            in: saveFolder,
            metadata: SessionRecoveryMetadata(
                sessionID: UUID(),
                title: "Closures Walkthrough",
                startedAt: TranscriptFixture.startedAt,
                sourceNames: ["QuickTime Player"],
                localeIdentifier: "en-US",
                status: status,
                endedAt: status == .inProgress ? nil : TranscriptFixture.startedAt.addingTimeInterval(60),
                transcriptSeal: .sealing(Data(text.utf8))
            ),
            transcript: text
        )
        let other = saveFolder.appending(path: "2026-08-30-standup", directoryHint: .isDirectory)
        try store.addSession(other, in: saveFolder, metadata: nil,
                             transcript: TranscriptFixture.transcript(title: "Standup", texts: ["Nothing."]))
        let files = FakeExportFiles()
        files.addTranscript(Data(text.utf8), at: SessionArtifactLayout(directory: directory).transcriptURL)
        var panels = 0
        let model = HistoryModel(
            service: HistoryService(store: store, access: FakeSecurityScopedAccess()),
            saveLocation: ExportSaveLocation(saveFolder),
            exporter: TranscriptExporter(files: files, access: FakeSecurityScopedAccess()),
            chooseExportDestination: { _, _ in
                panels += 1
                return answer
            }
        )
        return (model, files, { panels })
    }

    @Test("Cancelling the save panel writes nothing and says nothing")
    @MainActor
    func cancelWritesNothing() async throws {
        let (model, files, _) = try makeModel(answer: nil)
        await model.load()
        let session = try #require(model.documents.first { $0.session.status == .completed }?.session)

        await model.exportTranscript(of: session)

        #expect(model.exportState == .idle)
        #expect(files.copy(at: target) == nil)
    }

    @Test("A verified export is reported against its meeting, and cleared when another is selected")
    @MainActor
    func successIsReportedAndScoped() async throws {
        let (model, files, _) = try makeModel(answer: target)
        await model.load()
        let session = try #require(model.documents.first { $0.session.status == .completed }?.session)
        let other = try #require(model.documents.first { $0.session.isLegacy }?.session)
        await model.selectSession(session.id)
        #expect(session.integrity == .verified)

        await model.exportTranscript(of: session)

        guard case let .exported(_, result) = model.exportFeedback(for: session.id) else {
            Issue.record("Expected an exported state, got \(model.exportState)")
            return
        }
        #expect(result.integrity == .verified)
        #expect(files.copy(at: target) != nil)
        #expect(model.exportFeedback(for: other.id) == .idle)
        #expect(HistorySessionDetailView.exportSuccessMessage(for: result).contains("copy.md"))
        #expect(HistorySessionDetailView.exportAnnouncement(for: model.exportState)?.hasPrefix("Transcript exported") == true)

        // A reload keeps the same meeting's feedback; choosing another drops it.
        await model.load()
        #expect(model.exportFeedback(for: session.id) != .idle)
        await model.selectSession(other.id)
        #expect(model.exportState == .idle)
    }

    @Test("A failed export is reported with a message that names no path and quotes no transcript")
    @MainActor
    func failureIsReported() async throws {
        let (model, files, _) = try makeModel(answer: target)
        files.failWrites()
        await model.load()
        let session = try #require(model.documents.first { $0.session.status == .completed }?.session)

        await model.exportTranscript(of: session)

        guard case let .failed(_, message) = model.exportFeedback(for: session.id) else {
            Issue.record("Expected a failed state, got \(model.exportState)")
            return
        }
        #expect(message == TranscriptExportError.writeFailed.errorDescription)
        #expect(!message.contains("/Users"))
        #expect(!message.contains("closure"))

        model.dismissExportFeedback()
        #expect(model.exportState == .idle)
    }

    @Test("A meeting still being written offers no export and opens no panel")
    @MainActor
    func inProgressOffersNoExport() async throws {
        let (model, files, panels) = try makeModel(status: .inProgress, answer: target)
        await model.load()
        let session = try #require(model.documents.first { $0.session.status == .inProgress }?.session)

        #expect(!model.canExport(session))
        await model.exportTranscript(of: session)

        #expect(panels() == 0)
        #expect(files.copy(at: target) == nil)
        #expect(model.exportState == .idle)
    }

    @Test("The save panel warns before exporting a changed transcript, and only then")
    @MainActor
    func panelMessageWarnsOnlyWhenChanged() {
        let changed = session(seal: .sealing(Data("other".utf8)))
            .verified(against: TranscriptReading(text: "x", observed: .sealing(Data("x".utf8))))
        #expect(HistoryModel.exportMessage(for: changed).hasPrefix("This transcript has changed"))
        #expect(!HistoryModel.exportMessage(for: session()).contains("changed"))
        #expect(HistoryModel.exportMessage(for: session()).contains("nothing is uploaded"))
    }
}
