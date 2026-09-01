//
//  DerivedSessionModelTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@MainActor
@Suite("Notes and reviewed state on the History screen")
struct DerivedSessionModelTests {

    private let directory = URL(filePath: "/tmp/ScribeKitDerivedModel/meeting", directoryHint: .isDirectory)

    private var layout: SessionArtifactLayout { SessionArtifactLayout(directory: directory) }

    /// A meeting as History found it, with whatever identity a test needs.
    ///
    /// - Parameter sessionID: The recorded identity, or `nil` for a session
    ///   with no record at all.
    /// - Returns: The session.
    private func session(sessionID: UUID?) -> HistorySession {
        HistorySession(
            directory: directory,
            sessionID: sessionID,
            title: "Weekly sync",
            status: sessionID == nil ? .unrecorded : .completed,
            startedAt: nil,
            endedAt: nil,
            sourceNames: [],
            localeIdentifier: nil,
            transcriptURL: layout.transcriptURL,
            transcript: SessionFileInfo(byteCount: 10, modifiedAt: nil),
            audioRetention: nil,
            audio: nil
        )
    }

    /// A model reading and writing one in-memory sidecar.
    ///
    /// - Parameter store: The sidecar.
    /// - Returns: The model.
    private func makeModel(_ store: FakeDerivedSessionStore) -> DerivedSessionModel {
        DerivedSessionModel(service: DerivedSessionService(store: store, access: FakeSecurityScopedAccess()))
    }

    // MARK: - Notes

    @Test("A meeting with no sidecar opens with empty notes and nothing marked")
    func absentSidecar() async {
        let store = FakeDerivedSessionStore()
        let model = makeModel(store)

        await model.load(session(sessionID: UUID()), destination: nil)

        #expect(model.state == .ready)
        #expect(model.notesDraft.isEmpty)
        #expect(!model.hasUnsavedNotes)
        #expect(model.statusDescription == "No notes yet.")
        #expect(store.writeCount == 0)
    }

    @Test("Notes are unsaved until they are saved, and then read back exactly")
    func notesSaveAndReload() async {
        let store = FakeDerivedSessionStore()
        let sessionID = UUID()
        let model = makeModel(store)
        let text = "# Follow-ups\n\n- *ask* about the budget\n- second line\n"

        await model.load(session(sessionID: sessionID), destination: nil)
        model.notesDraft = text
        #expect(model.hasUnsavedNotes)
        #expect(model.statusDescription == "Unsaved changes.")
        #expect(store.writeCount == 0)

        await model.saveNotes()
        #expect(!model.hasUnsavedNotes)
        #expect(model.failureMessage == nil)

        let reopened = makeModel(store)
        await reopened.load(session(sessionID: sessionID), destination: nil)
        #expect(reopened.notesDraft == text)
    }

    @Test("A failed save keeps the user's text and says so")
    func failedSaveKeepsText() async {
        let store = FakeDerivedSessionStore()
        let model = makeModel(store)

        await model.load(session(sessionID: UUID()), destination: nil)
        model.notesDraft = "typed but not saved"
        store.failWrites()
        await model.saveNotes()

        #expect(model.notesDraft == "typed but not saved")
        #expect(model.hasUnsavedNotes)
        #expect(model.saved == nil)
        #expect(model.failureMessage != nil)
        #expect(store.storedBytes(for: layout) == nil)
    }

    // MARK: - Reviewed state

    @Test("Marking a passage reviewed persists it and unmarking undoes it")
    func markReviewedAndUnreviewed() async {
        let store = FakeDerivedSessionStore()
        let sessionID = UUID()
        let model = makeModel(store)

        await model.load(session(sessionID: sessionID), destination: nil)
        await model.setReviewed(true, spanIndex: 3)
        #expect(model.isReviewed(spanIndex: 3))

        let reopened = makeModel(store)
        await reopened.load(session(sessionID: sessionID), destination: nil)
        #expect(reopened.isReviewed(spanIndex: 3))

        await reopened.setReviewed(false, spanIndex: 3)
        #expect(!reopened.isReviewed(spanIndex: 3))

        let again = makeModel(store)
        await again.load(session(sessionID: sessionID), destination: nil)
        #expect(!again.isReviewed(spanIndex: 3))
    }

    @Test("A mark lands on the passage it names and on no other")
    func markResolvesToOneCandidate() async {
        let store = FakeDerivedSessionStore()
        let model = makeModel(store)

        await model.load(session(sessionID: UUID()), destination: nil)
        await model.setReviewed(true, spanIndex: 2)

        #expect(model.isReviewed(spanIndex: 2))
        #expect(!model.isReviewed(spanIndex: 1))
        #expect(!model.isReviewed(spanIndex: 3))
        #expect(model.reviewedCount(among: [1, 2, 3]) == 1)
    }

    @Test("A mark for a passage the review record no longer has attaches to nothing")
    func staleMarkIsOrphanedSafely() async throws {
        let store = FakeDerivedSessionStore()
        let sessionID = UUID()
        store.plant(
            try DerivedSessionState(sessionID: sessionID, reviewedSpanIndexes: [9]).encoded(),
            for: layout
        )
        let model = makeModel(store)

        await model.load(session(sessionID: sessionID), destination: nil)

        #expect(model.reviewedCount(among: [0, 1, 2]) == 0)
        #expect(!model.isReviewed(spanIndex: 0))
        #expect(model.saved?.reviewedSpanIndexes == [9])

        await model.setReviewed(true, spanIndex: 1)
        #expect(model.saved?.reviewedSpanIndexes == [1, 9])
    }

    // MARK: - Refusals

    @Test("A damaged, newer or foreign sidecar is refused and left alone")
    func refusedSidecarsAreNotOverwritten() async throws {
        let sessionID = UUID()
        let planted: [Data] = [
            Data("{ not json".utf8),
            try DerivedSessionState(schemaVersion: 99, sessionID: sessionID).encoded(),
            try DerivedSessionState(sessionID: UUID(), notes: "another meeting").encoded()
        ]

        for bytes in planted {
            let store = FakeDerivedSessionStore()
            store.plant(bytes, for: layout)
            let model = makeModel(store)

            await model.load(session(sessionID: sessionID), destination: nil)

            #expect(!model.isEditable)
            #expect(model.state != .ready)
            model.notesDraft = "should not reach the disk"
            await model.saveNotes()
            await model.setReviewed(true, spanIndex: 0)

            #expect(store.writeCount == 0)
            #expect(store.storedBytes(for: layout) == bytes)
        }
    }

    @Test("A meeting with no session record has nothing to attach notes to")
    func legacySessionIsUnsupported() async {
        let store = FakeDerivedSessionStore()
        let model = makeModel(store)

        await model.load(session(sessionID: nil), destination: nil)

        #expect(!model.isEditable)
        #expect(model.state != .ready)
        await model.saveNotes()
        #expect(store.writeCount == 0)
    }

    @Test("A save that would land on a version the editor never saw is refused")
    func staleWriteIsReported() async throws {
        let store = FakeDerivedSessionStore()
        let sessionID = UUID()
        let model = makeModel(store)

        await model.load(session(sessionID: sessionID), destination: nil)
        model.notesDraft = "mine"

        let elsewhere = makeModel(store)
        await elsewhere.load(session(sessionID: sessionID), destination: nil)
        await elsewhere.setReviewed(true, spanIndex: 0)

        await model.saveNotes()

        #expect(model.failureMessage != nil)
        #expect(model.notesDraft == "mine")
        #expect(model.hasUnsavedNotes)
        let reopened = makeModel(store)
        await reopened.load(session(sessionID: sessionID), destination: nil)
        #expect(reopened.notesDraft.isEmpty)
        #expect(reopened.isReviewed(spanIndex: 0))
    }

    @Test("Selecting another meeting reloads the notes rather than carrying them over")
    func selectionReloads() async {
        let store = FakeDerivedSessionStore()
        let model = makeModel(store)

        await model.load(session(sessionID: UUID()), destination: nil)
        model.notesDraft = "unsaved"
        model.clear()

        #expect(model.state == .idle)
        #expect(model.notesDraft.isEmpty)
        #expect(store.writeCount == 0)
    }

    @Test("Re-reading the same meeting keeps text the user has not saved")
    func reloadCarriesUnsavedDraft() async {
        let model = makeModel(FakeDerivedSessionStore())
        let meeting = session(sessionID: UUID())

        await model.load(meeting, destination: nil)
        model.notesDraft = "Half a thought about the rollback owner."
        await model.load(meeting, destination: nil)

        #expect(model.notesDraft == "Half a thought about the rollback owner.")
        #expect(model.hasUnsavedNotes)
        #expect(model.state == .ready)
    }

    @Test("Re-reading a meeting whose sidecar changed shows what is on disk")
    func reloadPrefersChangedDisk() async throws {
        let store = FakeDerivedSessionStore()
        let model = makeModel(store)
        let id = UUID()
        let meeting = session(sessionID: id)

        await model.load(meeting, destination: nil)
        model.notesDraft = "A draft the editor never saved."

        let elsewhere = DerivedSessionState(sessionID: id, notes: "Written elsewhere.", reviewedSpanIndexes: [])
        store.plant(try elsewhere.encoded(), for: layout)

        await model.load(meeting, destination: nil)

        #expect(model.notesDraft == "Written elsewhere.")
        #expect(!model.hasUnsavedNotes)
    }

    @Test("Selecting a different meeting still discards an unsaved draft")
    func otherMeetingDiscardsDraft() async {
        let model = makeModel(FakeDerivedSessionStore())

        await model.load(session(sessionID: UUID()), destination: nil)
        model.notesDraft = "Notes about the first meeting."
        await model.load(session(sessionID: UUID()), destination: nil)

        #expect(model.notesDraft.isEmpty)
        #expect(!model.hasUnsavedNotes)
    }
}
