//
//  HistoryIntegrationTests.swift
//  ScribeKitTests
//

import CryptoKit
import Foundation
import Testing
@testable import ScribeKit

/// History against the real filesystem, in a temporary folder.
///
/// The doubles elsewhere prove the policy; these prove that the policy meets
/// an actual disk — that a folder of real session directories lists and
/// searches, and that listing, searching and refreshing it change not one byte
/// of anything. Every transcript here is synthetic text written by the test.
@Suite("History on the filesystem")
struct HistoryIntegrationTests {

    /// Runs work in a save folder of its own, removed afterwards.
    ///
    /// - Parameter body: The work, given the folder.
    /// - Returns: Whatever `body` returns.
    private func withSaveFolder<T>(_ body: (URL) async throws -> T) async throws -> T {
        let root = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: "ScribeKitHistory-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        return try await body(root)
    }

    /// A service reading a real folder, with the sandbox calls stubbed out
    /// because a temporary directory carries no security scope.
    private func makeService() -> HistoryService {
        HistoryService(store: FileManagerHistoryStore(), access: FakeSecurityScopedAccess())
    }

    /// Writes one complete session directory.
    ///
    /// - Parameters:
    ///   - name: The directory's name.
    ///   - destination: The save folder.
    ///   - title: The meeting's title.
    ///   - texts: The recognised spans.
    ///   - status: The status to record.
    ///   - retention: What the record says was kept of the audio.
    ///   - writesRecord: Whether to write `.scribekit/session.json` at all.
    ///   - review: Raw bytes to write as `.scribekit/review.json`, or `nil`
    ///     for a session with no review information at all.
    ///   - started: When the meeting began.
    /// - Returns: The session directory.
    @discardableResult
    private func writeSession(
        _ name: String,
        in destination: URL,
        title: String,
        texts: [String],
        status: SessionRecoveryStatus = .completed,
        retention: AudioRetentionMode = .none,
        writesRecord: Bool = true,
        review: Data? = nil,
        started: Date = TranscriptFixture.startedAt
    ) throws -> URL {
        let layout = SessionArtifactLayout(destination: destination, directoryName: name)
        try FileManager.default.createDirectory(at: layout.directory, withIntermediateDirectories: true)

        var formatter = TranscriptMarkdownFormatter(startedAt: started, timeZone: TranscriptFixture.zone)
        var markdown = formatter.header(title: title, sourceNames: ["QuickTime Player"], localeIdentifier: "en-US")
        for (index, text) in texts.enumerated() {
            markdown += formatter.finalSegment(TranscriptSegment(
                text: text,
                startTime: Double(index) * 20,
                endTime: Double(index) * 20 + 4,
                state: .final,
                localeIdentifier: "en-US"
            ))
        }
        markdown += formatter.footer(endedAt: started.addingTimeInterval(120))
        try Data(markdown.utf8).write(to: layout.transcriptURL)

        if let audioURL = layout.audioURL(for: retention) {
            try Data(repeating: 7, count: 2_048).write(to: audioURL)
        }

        if writesRecord {
            try FileManager.default.createDirectory(at: layout.metadataDirectory, withIntermediateDirectories: true)
            let record = SessionRecoveryMetadata(
                sessionID: UUID(),
                title: title,
                startedAt: started,
                sourceNames: ["QuickTime Player"],
                localeIdentifier: "en-US",
                audioRetention: retention == .none ? nil : retention,
                audioPath: layout.audioURL(for: retention)?.lastPathComponent,
                status: status,
                endedAt: status == .completed ? started.addingTimeInterval(120) : nil
            )
            try record.encoded().write(to: layout.metadataURL)
        }

        if let review {
            try FileManager.default.createDirectory(at: layout.metadataDirectory, withIntermediateDirectories: true)
            try review.write(to: layout.reviewURL)
        }
        return layout.directory
    }

    /// The SHA-256 of every regular file under a folder, keyed by path.
    ///
    /// - Parameter root: The folder to fingerprint.
    /// - Returns: One digest per file.
    private func fingerprints(of root: URL) throws -> [String: String] {
        var digests: [String: String] = [:]
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: []
        )
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { continue }
            let digest = SHA256.hash(data: try Data(contentsOf: url))
            let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            digests[url.path(percentEncoded: false)] =
                digest.map { String(format: "%02x", $0) }.joined() + "@\(modified)"
        }
        return digests
    }

    // MARK: - Discovery

    @Test("A folder of real sessions lists with the right metadata and paths")
    func realFolderLists() async throws {
        try await withSaveFolder { destination in
            try writeSession(
                "2026-08-29-closures-walkthrough",
                in: destination,
                title: "Closures Walkthrough",
                texts: ["A closure captures the variables it refers to."],
                retention: .compressed
            )
            try writeSession(
                "2026-08-29-standup",
                in: destination,
                title: "Standup",
                texts: ["Nothing to report."],
                started: TranscriptFixture.startedAt.addingTimeInterval(3_600)
            )

            let report = try await makeService().load(destination)

            #expect(report.sessions.map(\.title) == ["Standup", "Closures Walkthrough"])
            #expect(report.problems.isEmpty)
            let closures = try #require(report.sessions.last)
            #expect(closures.status == .completed)
            #expect(closures.audio?.format == .compressed)
            #expect(closures.audio?.file.byteCount == 2_048)
            #expect(closures.transcript.byteCount > 0)
            #expect(FileManager.default.fileExists(atPath: closures.transcriptURL.path(percentEncoded: false)))
        }
    }

    @Test("A real transcript with no record is found, and arbitrary Markdown is not")
    func legacyTranscriptOnDisk() async throws {
        try await withSaveFolder { destination in
            try writeSession(
                "2026-08-29-before-records",
                in: destination,
                title: "Before Records Existed",
                texts: ["Written by an earlier ScribeKit."],
                writesRecord: false
            )
            let notes = destination.appending(path: "notes", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
            try Data("# Shopping List\n\n- Milk\n".utf8).write(
                to: notes.appending(path: "transcript.md", directoryHint: .notDirectory)
            )

            let report = try await makeService().load(destination)

            #expect(report.sessions.map(\.title) == ["Before Records Existed"])
            #expect(report.sessions.first?.status == .unrecorded)
            #expect(report.sessions.first?.startedAt == nil)
            #expect(report.problems.isEmpty)
        }
    }

    @Test("A meeting still being written is listed as in progress and read safely")
    func inProgressSessionIsListed() async throws {
        try await withSaveFolder { destination in
            try writeSession(
                "2026-08-29-running",
                in: destination,
                title: "Running Now",
                texts: ["Speech that has already reached the file."],
                status: .inProgress
            )

            let report = try await makeService().load(destination)
            let found = try #require(report.sessions.first)

            #expect(found.status == .inProgress)
            #expect(found.endedAt == nil)
            #expect(report.documents.first?.spans.map(\.text)
                    == ["Speech that has already reached the file."])
        }
    }

    // MARK: - Immutability

    @Test("Loading, searching and refreshing leave every artifact byte-identical")
    func historyChangesNothing() async throws {
        try await withSaveFolder { destination in
            try writeSession(
                "2026-08-29-closures-walkthrough",
                in: destination,
                title: "Closures Walkthrough",
                texts: ["A closure captures the variables it refers to.", "Escaping closures outlive the call."],
                retention: .raw,
                review: try SessionReviewMetadata(
                    sessionID: UUID(),
                    recognizerConfidenceAvailable: true,
                    candidates: [TranscriptReviewCandidate(
                        spanIndex: 1, startTime: 20, endTime: 24, confidence: 0.2, reasons: [.lowConfidence]
                    )]
                ).encoded()
            )
            try writeSession(
                "2026-08-29-legacy",
                in: destination,
                title: "Legacy Meeting",
                texts: ["No record beside this one."],
                writesRecord: false
            )
            let damaged = destination.appending(path: "2026-08-29-damaged", directoryHint: .isDirectory)
            let damagedLayout = SessionArtifactLayout(directory: damaged)
            try FileManager.default.createDirectory(
                at: damagedLayout.metadataDirectory,
                withIntermediateDirectories: true
            )
            try Data("{ not json".utf8).write(to: damagedLayout.metadataURL)
            try Data("# Damaged\n".utf8).write(to: damagedLayout.transcriptURL)

            let before = try fingerprints(of: destination)
            #expect(before.count == 7)

            let service = makeService()
            let first = try await service.load(destination)
            _ = TranscriptSearch.results(for: "closure", in: first.documents)
            _ = TranscriptSearch.results(for: "", in: first.documents)
            _ = TranscriptSearch.results(for: "Legacy", in: first.documents)
            let second = try await service.load(destination)
            _ = TranscriptSearch.results(for: "outlive", in: second.documents)

            #expect(first == second)
            #expect(first.problems.map(\.error) == [.metadataMalformed])
            #expect(try fingerprints(of: destination) == before)
        }
    }

    // MARK: - Review

    @Test("A meeting's review sidecar is read back and points at the words the transcript has")
    func reviewSidecarIsReadBack() async throws {
        try await withSaveFolder { destination in
            try writeSession(
                "2026-08-29-closures-walkthrough",
                in: destination,
                title: "Closures Walkthrough",
                texts: ["A closure captures the variables it refers to.", "Escaping closures outlive the call."],
                retention: .raw,
                review: try SessionReviewMetadata(
                    sessionID: UUID(),
                    recognizerConfidenceAvailable: true,
                    candidates: [
                        TranscriptReviewCandidate(
                            spanIndex: 1, startTime: 20, endTime: 24, confidence: 0.2, reasons: [.lowConfidence]
                        ),
                        TranscriptReviewCandidate(
                            spanIndex: 47, startTime: 900, endTime: 902, confidence: 0.1, reasons: [.lowConfidence]
                        )
                    ]
                ).encoded()
            )

            let document = try #require(try await makeService().load(destination).documents.first)
            let candidates = document.reviewCandidates

            // The candidate naming a span the transcript does not have is
            // dropped rather than shown against the wrong words.
            #expect(candidates.count == 1)
            #expect(candidates[0].candidate.spanIndex == 1)
            #expect(candidates[0].span.text == "Escaping closures outlive the call.")
            #expect(candidates[0].candidate.startTime == 20)
            #expect(document.review?.recognizerConfidenceAvailable == true)
        }
    }

    @Test("A session with no review sidecar, or a damaged one, is listed and searched normally", arguments: [
        nil, Data("{ not json".utf8), Data(#"{"schemaVersion":99}"#.utf8)
    ] as [Data?])
    func reviewMetadataIsNeverLoadBearing(sidecar: Data?) async throws {
        try await withSaveFolder { destination in
            try writeSession(
                "2026-08-29-closures-walkthrough",
                in: destination,
                title: "Closures Walkthrough",
                texts: ["A closure captures the variables it refers to."],
                review: sidecar
            )

            let report = try await makeService().load(destination)
            let document = try #require(report.documents.first)

            #expect(report.problems.isEmpty)
            #expect(document.session.title == "Closures Walkthrough")
            #expect(document.review == nil)
            #expect(document.reviewCandidates.isEmpty)
            #expect(TranscriptSearch.results(for: "closure", in: report.documents).count == 1)
        }
    }

    @Test("A load creates no file of its own in the save folder")
    func historyWritesNoIndex() async throws {
        try await withSaveFolder { destination in
            try writeSession(
                "2026-08-29-one",
                in: destination,
                title: "One",
                texts: ["Something."]
            )
            let before = Set(try FileManager.default.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent))

            _ = try await makeService().load(destination)

            let after = Set(try FileManager.default.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent))
            #expect(after == before)
        }
    }

    // MARK: - Scale

    @Test("A folder of many meetings loads and searches in memory")
    func manyMeetingsLoadAndSearch() async throws {
        try await withSaveFolder { destination in
            let sessionCount = 120
            for index in 0..<sessionCount {
                var texts = (0..<20).map { "Paragraph \($0) of meeting \(index), spoken aloud and recognised." }
                if index == 77 { texts.append("The distinctive phrase only meeting seventy-seven contains.") }
                try writeSession(
                    String(format: "2026-08-29-meeting-%03d", index),
                    in: destination,
                    title: "Meeting \(index)",
                    texts: texts,
                    started: TranscriptFixture.startedAt.addingTimeInterval(Double(index) * 3_600)
                )
            }

            let start = ContinuousClock.now
            let report = try await makeService().load(destination)
            let loadDuration = ContinuousClock.now - start

            #expect(report.sessions.count == sessionCount)
            #expect(report.problems.isEmpty)
            #expect(loadDuration < .seconds(10))

            let searchStart = ContinuousClock.now
            let results = TranscriptSearch.results(for: "seventy-seven", in: report.documents)
            let searchDuration = ContinuousClock.now - searchStart

            #expect(results.map(\.session.title) == ["Meeting 77"])
            #expect(results.first?.excerpt?.text.contains("seventy-seven") == true)
            #expect(searchDuration < .seconds(2))
            #expect(TranscriptSearch.results(for: "", in: report.documents).count == sessionCount)
            #expect(TranscriptSearch.results(for: "spoken aloud", in: report.documents).count == sessionCount)
        }
    }
}
