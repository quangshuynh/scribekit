//
//  DerivedSessionStoreTests.swift
//  ScribeKitTests
//

import CryptoKit
import Foundation
import Testing
@testable import ScribeKit

@Suite("Derived session state on the filesystem")
struct DerivedSessionStoreTests {

    private let store = FileManagerDerivedSessionStore()
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    /// One session directory holding every source artifact a meeting writes.
    ///
    /// - Parameter body: The work, given the layout and the session identity.
    /// - Returns: Whatever `body` returns.
    private func withSession<T>(_ body: (SessionArtifactLayout, UUID) async throws -> T) async throws -> T {
        let root = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: "ScribeKitDerived-\(UUID().uuidString)", directoryHint: .isDirectory)
        let layout = SessionArtifactLayout(destination: root, directoryName: "meeting")
        try FileManager.default.createDirectory(at: layout.metadataDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionID = UUID()
        try Data("# Meeting\n\nsome recognised words\n".utf8).write(to: layout.transcriptURL)
        try Data(repeating: 7, count: 1_024).write(to: layout.audioURL(for: .raw)!)
        try SessionRecoveryMetadata(
            sessionID: sessionID,
            title: "Meeting",
            startedAt: date,
            sourceNames: ["QuickTime Player"],
            localeIdentifier: "en-US",
            audioRetention: .raw,
            audioPath: "audio.caf",
            status: .completed,
            endedAt: date.addingTimeInterval(60)
        ).encoded().write(to: layout.metadataURL)
        try SessionReviewMetadata(
            sessionID: sessionID,
            recognizerConfidenceAvailable: true,
            candidates: [
                TranscriptReviewCandidate(
                    spanIndex: 0,
                    startTime: 0,
                    endTime: 4,
                    confidence: 0.2,
                    reasons: [.lowConfidence]
                )
            ]
        ).encoded().write(to: layout.reviewURL)

        return try await body(layout, sessionID)
    }

    /// The SHA-256 and modification date of every source artifact, so a write
    /// to the derived sidecar can be proved to have touched none of them.
    ///
    /// - Parameter layout: The session's layout.
    /// - Returns: One fingerprint per source file.
    private func sourceFingerprints(_ layout: SessionArtifactLayout) throws -> [String: String] {
        let urls = [layout.transcriptURL, layout.audioURL(for: .raw)!, layout.metadataURL, layout.reviewURL]
        return try urls.reduce(into: [:]) { digests, url in
            let digest = SHA256.hash(data: try Data(contentsOf: url))
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate?.timeIntervalSince1970 ?? 0
            digests[url.lastPathComponent] =
                digest.map { String(format: "%02x", $0) }.joined() + "@\(modified)"
        }
    }

    // MARK: - Reading

    @Test("A meeting with no sidecar has no derived state")
    func absentSidecar() async throws {
        try await withSession { layout, sessionID in
            let state = try store.readDerivedState(from: layout, sessionID: sessionID)
            #expect(state == nil)
        }
    }

    @Test("A written record reads back exactly")
    func roundTrip() async throws {
        try await withSession { layout, sessionID in
            let written = try store.writeDerivedState(
                DerivedSessionState(sessionID: sessionID, notes: "line one\nline two\n", reviewedSpanIndexes: [0]),
                to: layout,
                expectedRevision: nil,
                at: date
            )

            let read = try store.readDerivedState(from: layout, sessionID: sessionID)
            #expect(read == written)
            #expect(read?.notes == "line one\nline two\n")
            #expect(read?.reviewedSpanIndexes == [0])
            #expect(read?.updatedAt == date)
        }
    }

    @Test("A damaged sidecar is refused and never overwritten")
    func malformedSidecar() async throws {
        try await withSession { layout, sessionID in
            let damaged = Data("{ not json".utf8)
            try damaged.write(to: layout.derivedURL)

            #expect(throws: DerivedSessionError.malformed) {
                try store.readDerivedState(from: layout, sessionID: sessionID)
            }
            #expect(throws: DerivedSessionError.malformed) {
                try store.writeDerivedState(
                    DerivedSessionState(sessionID: sessionID, notes: "new"),
                    to: layout,
                    expectedRevision: nil,
                    at: date
                )
            }
            let onDisk = try Data(contentsOf: layout.derivedURL)
            #expect(onDisk == damaged)
        }
    }

    @Test("A newer schema is refused and never overwritten")
    func unsupportedSchema() async throws {
        try await withSession { layout, sessionID in
            let future = try DerivedSessionState(
                schemaVersion: 99,
                sessionID: sessionID,
                notes: "from a later ScribeKit"
            ).encoded()
            try future.write(to: layout.derivedURL)

            #expect(throws: DerivedSessionError.unsupportedSchemaVersion(99)) {
                try store.readDerivedState(from: layout, sessionID: sessionID)
            }
            #expect(throws: DerivedSessionError.unsupportedSchemaVersion(99)) {
                try store.writeDerivedState(
                    DerivedSessionState(sessionID: sessionID),
                    to: layout,
                    expectedRevision: nil,
                    at: date
                )
            }
            let onDisk = try Data(contentsOf: layout.derivedURL)
            #expect(onDisk == future)
        }
    }

    @Test("A sidecar naming another meeting is not attached to this one")
    func sessionMismatch() async throws {
        try await withSession { layout, sessionID in
            let foreign = try DerivedSessionState(sessionID: UUID(), notes: "someone else's").encoded()
            try foreign.write(to: layout.derivedURL)

            #expect(throws: DerivedSessionError.sessionMismatch) {
                try store.readDerivedState(from: layout, sessionID: sessionID)
            }
            let onDisk = try Data(contentsOf: layout.derivedURL)
            #expect(onDisk == foreign)
        }
    }

    // MARK: - Writing

    @Test("A save that would land on a version the caller never saw is refused")
    func staleWriteIsRefused() async throws {
        try await withSession { layout, sessionID in
            let first = try store.writeDerivedState(
                DerivedSessionState(sessionID: sessionID, notes: "first"),
                to: layout,
                expectedRevision: nil,
                at: date
            )
            let second = try store.writeDerivedState(
                DerivedSessionState(sessionID: sessionID, notes: "second"),
                to: layout,
                expectedRevision: first.revision,
                at: date
            )

            #expect(throws: DerivedSessionError.staleWrite) {
                try store.writeDerivedState(
                    DerivedSessionState(sessionID: sessionID, notes: "from the stale view"),
                    to: layout,
                    expectedRevision: first.revision,
                    at: date
                )
            }
            let onDisk = try store.readDerivedState(from: layout, sessionID: sessionID)
            #expect(onDisk == second)
        }
    }

    @Test("A first save is refused when a sidecar appeared after the load")
    func appearingSidecarIsRefused() async throws {
        try await withSession { layout, sessionID in
            try store.writeDerivedState(
                DerivedSessionState(sessionID: sessionID, notes: "written elsewhere"),
                to: layout,
                expectedRevision: nil,
                at: date
            )

            #expect(throws: DerivedSessionError.staleWrite) {
                try store.writeDerivedState(
                    DerivedSessionState(sessionID: sessionID, notes: "from a view that saw no file"),
                    to: layout,
                    expectedRevision: nil,
                    at: date
                )
            }
            let onDisk = try store.readDerivedState(from: layout, sessionID: sessionID)
            #expect(onDisk?.notes == "written elsewhere")
        }
    }

    @Test("A save replaces the file whole, leaving nothing partial behind")
    func writesAreAtomic() async throws {
        try await withSession { layout, sessionID in
            var state = try store.writeDerivedState(
                DerivedSessionState(sessionID: sessionID, notes: String(repeating: "long ", count: 4_000)),
                to: layout,
                expectedRevision: nil,
                at: date
            )
            state = try store.writeDerivedState(
                DerivedSessionState(sessionID: sessionID, revision: state.revision, notes: "short"),
                to: layout,
                expectedRevision: state.revision,
                at: date
            )

            let contents = try FileManager.default.contentsOfDirectory(
                at: layout.metadataDirectory,
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent).sorted()
            #expect(contents == ["derived.json", "review.json", "session.json"])
            let onDisk = try store.readDerivedState(from: layout, sessionID: sessionID)
            #expect(onDisk?.notes == "short")
        }
    }

    @Test("A failed save damages nothing and reports itself")
    func failedWriteLeavesEverythingAlone() async throws {
        try await withSession { layout, sessionID in
            try FileManager.default.removeItem(at: layout.reviewURL)
            try FileManager.default.removeItem(at: layout.metadataURL)
            try FileManager.default.removeItem(at: layout.metadataDirectory)
            try Data("not a directory".utf8).write(to: layout.metadataDirectory)
            let transcript = try Data(contentsOf: layout.transcriptURL)
            let audio = try Data(contentsOf: layout.audioURL(for: .raw)!)

            #expect(throws: DerivedSessionError.writeFailed) {
                try store.writeDerivedState(
                    DerivedSessionState(sessionID: sessionID, notes: "nowhere to go"),
                    to: layout,
                    expectedRevision: nil,
                    at: date
                )
            }
            let transcriptAfter = try Data(contentsOf: layout.transcriptURL)
            let audioAfter = try Data(contentsOf: layout.audioURL(for: .raw)!)
            #expect(transcriptAfter == transcript)
            #expect(audioAfter == audio)
        }
    }

    // MARK: - The source boundary

    @Test("Notes and reviewed marks leave every source artifact byte-identical")
    func sourceArtifactsAreUntouched() async throws {
        try await withSession { layout, sessionID in
            let before = try sourceFingerprints(layout)

            var state = try store.writeDerivedState(
                DerivedSessionState(sessionID: sessionID, notes: "# Notes\n\n- one\n"),
                to: layout,
                expectedRevision: nil,
                at: date
            )
            state = try store.writeDerivedState(
                state.settingReviewed(true, spanIndex: 0),
                to: layout,
                expectedRevision: state.revision,
                at: date
            )
            state = try store.writeDerivedState(
                state.settingReviewed(false, spanIndex: 0).settingNotes("# Notes\n\n- one\n- two\n"),
                to: layout,
                expectedRevision: state.revision,
                at: date
            )

            let after = try sourceFingerprints(layout)
            #expect(after == before)
            #expect(state.notes == "# Notes\n\n- one\n- two\n")
            #expect(state.reviewedSpanIndexes.isEmpty)
        }
    }

    @Test("The service opens and closes sandbox access around each call")
    func accessIsReleased() async throws {
        try await withSession { layout, sessionID in
            let access = FakeSecurityScopedAccess()
            let service = DerivedSessionService(store: store, access: access)
            let destination = layout.directory.deletingLastPathComponent()

            let saved = try await service.save(
                DerivedSessionState(sessionID: sessionID, notes: "typed"),
                in: layout.directory,
                destination: destination,
                expectedRevision: nil,
                at: date
            )
            _ = try await service.load(sessionID: sessionID, in: layout.directory, destination: destination)

            #expect(saved.notes == "typed")
            #expect(access.started == [destination, destination])
            #expect(access.isBalanced)
        }
    }
}
