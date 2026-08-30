//
//  DerivedSessionStateTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@Suite("Derived session state")
struct DerivedSessionStateTests {

    private let sessionID = UUID(uuidString: "1B4E28BA-2FA1-11D2-883F-0016D3CCA427")!

    @Test("A record survives an encode and decode round trip")
    func roundTrip() throws {
        let state = DerivedSessionState(
            sessionID: sessionID,
            notes: "# Follow-ups\n\n- ask about the *budget*\n- second line\n",
            reviewedSpanIndexes: [4, 1],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let decoded = try DerivedSessionState.decoded(from: try state.encoded())

        #expect(decoded == state)
        #expect(decoded.notes == state.notes)
        #expect(decoded.revision == state.revision)
    }

    @Test("Reviewed indexes are stored sorted and deduplicated")
    func indexesAreCanonical() throws {
        let state = DerivedSessionState(sessionID: sessionID, reviewedSpanIndexes: [7, 2, 7, 0])

        #expect(state.reviewedSpanIndexes == [0, 2, 7])
    }

    @Test("The same state always serialises to the same bytes")
    func serializationIsDeterministic() throws {
        let revision = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let first = DerivedSessionState(
            sessionID: sessionID,
            revision: revision,
            notes: "note",
            reviewedSpanIndexes: [3, 1],
            updatedAt: updatedAt
        )
        let second = DerivedSessionState(
            sessionID: sessionID,
            revision: revision,
            notes: "note",
            reviewedSpanIndexes: [1, 3, 1],
            updatedAt: updatedAt
        )

        #expect(try first.encoded() == second.encoded())
    }

    @Test("An unknown schema version is refused rather than misread")
    func unknownSchemaIsRefused() throws {
        let future = DerivedSessionState(schemaVersion: 99, sessionID: sessionID, notes: "later")
        let data = try future.encoded()

        #expect(throws: DerivedSessionError.unsupportedSchemaVersion(99)) {
            try DerivedSessionState.decoded(from: data)
        }
    }

    @Test(
        "Bytes that are not a record are refused",
        arguments: ["", "{", "not json at all", #"{"schemaVersion":1}"#]
    )
    func malformedIsRefused(text: String) throws {
        #expect(throws: DerivedSessionError.malformed) {
            try DerivedSessionState.decoded(from: Data(text.utf8))
        }
    }

    @Test("Marking and unmarking a candidate changes only that candidate")
    func reviewedMarksAreIndependent() {
        let state = DerivedSessionState(sessionID: sessionID, reviewedSpanIndexes: [2])

        let marked = state.settingReviewed(true, spanIndex: 5)
        #expect(marked.reviewedSpanIndexes == [2, 5])

        let unmarked = marked.settingReviewed(false, spanIndex: 2)
        #expect(unmarked.reviewedSpanIndexes == [5])
        #expect(unmarked.isReviewed(spanIndex: 5))
        #expect(!unmarked.isReviewed(spanIndex: 2))
    }

    @Test("Notes are stored exactly as they were typed")
    func notesAreVerbatim() {
        let text = "  leading spaces\n\n\ttab\n- [ ] not a checklist\n"
        let state = DerivedSessionState(sessionID: sessionID).settingNotes(text)

        #expect(state.notes == text)
    }

    @Test("Preparing a write mints a new revision and keeps the user's state")
    func preparedForWriteRevisesTheToken() {
        let state = DerivedSessionState(sessionID: sessionID, notes: "n", reviewedSpanIndexes: [1])
        let date = Date(timeIntervalSince1970: 42)

        let written = state.preparedForWrite(at: date)

        #expect(written.revision != state.revision)
        #expect(written.notes == "n")
        #expect(written.reviewedSpanIndexes == [1])
        #expect(written.updatedAt == date)
        #expect(written.sessionID == sessionID)
    }
}
