//
//  DerivedSessionState.swift
//  ScribeKit
//

import Foundation

/// A reason derived session state could not be read or written.
///
/// Every case describes something ScribeKit found and left exactly as it was.
/// None of them permits repairing, rewriting or removing a file, and none of
/// them can touch a source artifact: derived state lives in its own sidecar,
/// so a failure here costs the user's notes and nothing else.
nonisolated enum DerivedSessionError: Error, Equatable, Sendable {
    /// The sidecar is there but could not be read from the filesystem.
    case unreadable

    /// The sidecar is there but is not a record this build can interpret.
    case malformed

    /// The sidecar announces a schema version this build does not know.
    case unsupportedSchemaVersion(Int)

    /// The sidecar belongs to a different session than the one being opened.
    case sessionMismatch

    /// The sidecar changed on disk between being loaded and being saved.
    case staleWrite

    /// The sidecar could not be written.
    case writeFailed
}

extension DerivedSessionError: LocalizedError {
    /// A message for the History screen that says what ScribeKit found and
    /// what it refused to do about it.
    var errorDescription: String? {
        switch self {
        case .unreadable:
            "This meeting's notes and review state could not be read. Nothing was changed."
        case .malformed:
            "This meeting's notes and review state are damaged and were left untouched. "
            + "ScribeKit will not overwrite them."
        case let .unsupportedSchemaVersion(version):
            "This meeting's notes and review state were written by a newer version of ScribeKit "
            + "(format \(version)) and were left untouched. ScribeKit will not overwrite them."
        case .sessionMismatch:
            "The notes file in this folder names a different meeting, so ScribeKit did not attach it "
            + "to this one."
        case .staleWrite:
            "This meeting's notes changed elsewhere since they were opened. Nothing was overwritten — "
            + "reopen the meeting to see the saved version."
        case .writeFailed:
            "ScribeKit could not save these notes. Your text is still here, and the transcript, "
            + "recording and session record were not touched."
        }
    }
}

/// What the user, rather than the recogniser, has decided about a meeting.
///
/// This is the first artifact ScribeKit writes on the user's behalf after a
/// meeting has closed, and it is deliberately the only one. `transcript.md`,
/// the retained recording, `session.json` and `review.json` are source
/// material: they record what was captured and what the recogniser observed,
/// and nothing here rewrites, annotates or reorders any of them. Notes and a
/// reviewed mark are the user's own state about that material, so they live in
/// their own sidecar and losing it costs exactly those two things.
///
/// It duplicates nothing. Review candidates, their confidence, their reasons,
/// the transcript's words and the meeting's sources all stay in the artifacts
/// that own them; this record names a candidate by the span index
/// `review.json` already uses and holds the user's disposition alone.
///
/// The record is versioned from its first release, and ``schemaVersion`` is
/// read on its own before anything else is interpreted, so a file written by a
/// later ScribeKit is refused rather than misread as this one.
nonisolated struct DerivedSessionState: Codable, Equatable, Sendable {

    /// The schema version this build writes and is able to read.
    static let currentSchemaVersion = 1

    /// The version of the record's layout.
    let schemaVersion: Int

    /// The session's stable identity, matching ``MeetingSession/id`` and the
    /// identity `session.json` and `review.json` carry.
    ///
    /// Checked on load. A sidecar naming another meeting is refused rather
    /// than attached to the meeting whose folder it happens to be in.
    let sessionID: UUID

    /// Which write of this file the record is.
    ///
    /// Regenerated on every save and compared against what is on disk before
    /// the next one, so a save that would land on top of a version the editor
    /// never saw is refused. A filesystem modification date would not do:
    /// two writes inside the same second can carry the same date, and a token
    /// written into the record cannot.
    let revision: UUID

    /// The user's own notes about the meeting, as they typed them.
    ///
    /// Markdown source held verbatim: ScribeKit does not render it, reflow it,
    /// trim it or transform it in any way, and nothing generates it.
    let notes: String

    /// The review candidates the user has marked as dealt with, named by the
    /// span index `review.json` gives them.
    ///
    /// Sorted and free of duplicates, so the same state always serialises to
    /// the same bytes. An index that no longer names a candidate resolves to
    /// nothing and is left in the file rather than dropped: a sidecar that has
    /// outlived a review record is not a licence to discard what the user
    /// marked.
    let reviewedSpanIndexes: [Int]

    /// When ScribeKit last wrote the record, for the interface to show.
    let updatedAt: Date?

    /// Creates a record.
    ///
    /// - Parameters:
    ///   - schemaVersion: The layout version. Defaults to
    ///     ``currentSchemaVersion``; a test passes another to prove an unknown
    ///     version is refused.
    ///   - sessionID: The session's stable identity.
    ///   - revision: Which write of the file this is. A fresh token by
    ///     default.
    ///   - notes: The user's own notes, verbatim.
    ///   - reviewedSpanIndexes: Span indexes the user has marked reviewed.
    ///     Sorted and deduplicated here.
    ///   - updatedAt: When the record was written.
    init(
        schemaVersion: Int = DerivedSessionState.currentSchemaVersion,
        sessionID: UUID,
        revision: UUID = UUID(),
        notes: String = "",
        reviewedSpanIndexes: [Int] = [],
        updatedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.revision = revision
        self.notes = notes
        self.reviewedSpanIndexes = Set(reviewedSpanIndexes).sorted()
        self.updatedAt = updatedAt
    }

    /// Whether the user has put nothing into this meeting yet.
    var isEmpty: Bool { notes.isEmpty && reviewedSpanIndexes.isEmpty }

    /// Whether a review candidate has been marked as dealt with.
    ///
    /// - Parameter spanIndex: The candidate's span index.
    /// - Returns: Whether the user marked it reviewed.
    func isReviewed(spanIndex: Int) -> Bool { reviewedSpanIndexes.contains(spanIndex) }

    /// The same state with a candidate marked reviewed or unreviewed.
    ///
    /// - Parameters:
    ///   - reviewed: The disposition to record.
    ///   - spanIndex: The candidate's span index.
    /// - Returns: The updated state, carrying the same revision until it is
    ///   written.
    func settingReviewed(_ reviewed: Bool, spanIndex: Int) -> DerivedSessionState {
        var indexes = Set(reviewedSpanIndexes)
        if reviewed { indexes.insert(spanIndex) } else { indexes.remove(spanIndex) }
        return with(notes: notes, reviewedSpanIndexes: indexes.sorted())
    }

    /// The same state carrying different notes.
    ///
    /// - Parameter notes: The user's text, verbatim.
    /// - Returns: The updated state.
    func settingNotes(_ notes: String) -> DerivedSessionState {
        with(notes: notes, reviewedSpanIndexes: reviewedSpanIndexes)
    }

    /// The state as it will be written: a new revision token and a fresh
    /// timestamp, so the next save can tell whether it is landing on this one.
    ///
    /// - Parameter date: The moment of the write.
    /// - Returns: The record to encode.
    func preparedForWrite(at date: Date) -> DerivedSessionState {
        DerivedSessionState(
            sessionID: sessionID,
            revision: UUID(),
            notes: notes,
            reviewedSpanIndexes: reviewedSpanIndexes,
            updatedAt: date
        )
    }

    /// Copies the record with new user state and everything else unchanged.
    ///
    /// - Parameters:
    ///   - notes: The user's text.
    ///   - reviewedSpanIndexes: Span indexes marked reviewed.
    /// - Returns: The updated record.
    private func with(notes: String, reviewedSpanIndexes: [Int]) -> DerivedSessionState {
        DerivedSessionState(
            schemaVersion: schemaVersion,
            sessionID: sessionID,
            revision: revision,
            notes: notes,
            reviewedSpanIndexes: reviewedSpanIndexes,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Encoding

nonisolated extension DerivedSessionState {

    /// Only the version, read before anything else is interpreted.
    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    /// The encoder used for every derived sidecar ScribeKit writes.
    ///
    /// Sorted keys and a fixed date strategy, so the same state produces the
    /// same bytes on every machine and an unchanged save is a no-op to a
    /// checksum.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// The decoder used for every derived sidecar ScribeKit reads.
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Renders the record as the bytes of `derived.json`.
    ///
    /// - Returns: UTF-8 JSON.
    /// - Throws: ``DerivedSessionError/malformed`` when the record cannot be
    ///   encoded, which would mean a programming error rather than a damaged
    ///   file.
    func encoded() throws -> Data {
        do {
            return try Self.encoder.encode(self)
        } catch {
            throw DerivedSessionError.malformed
        }
    }

    /// Reads a sidecar, refusing anything this build cannot interpret.
    ///
    /// - Parameter data: The contents of `derived.json`.
    /// - Returns: The decoded record.
    /// - Throws: ``DerivedSessionError/malformed`` when the bytes are not a
    ///   readable record, or
    ///   ``DerivedSessionError/unsupportedSchemaVersion(_:)`` when they
    ///   announce a version this build does not know.
    static func decoded(from data: Data) throws -> DerivedSessionState {
        guard let probe = try? decoder.decode(SchemaProbe.self, from: data) else {
            throw DerivedSessionError.malformed
        }
        guard probe.schemaVersion == currentSchemaVersion else {
            throw DerivedSessionError.unsupportedSchemaVersion(probe.schemaVersion)
        }
        guard let state = try? decoder.decode(DerivedSessionState.self, from: data) else {
            throw DerivedSessionError.malformed
        }
        return state
    }
}
