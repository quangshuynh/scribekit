//
//  SessionReviewMetadata.swift
//  ScribeKit
//

import Foundation

/// A reason review metadata could not be written or read.
nonisolated enum SessionReviewError: Error, Equatable, Sendable {
    /// The sidecar is there but is not a record this build can interpret.
    case malformed

    /// The sidecar announces a schema version this build does not know.
    case unsupportedSchemaVersion(Int)

    /// The sidecar could not be written.
    case writeFailed
}

/// What a meeting observed about its own recognition, kept beside the
/// transcript in `.scribekit/review.json`.
///
/// This is not transcript content and never becomes any. `transcript.md` stays
/// canonical and is written exactly as the recogniser produced it; the sidecar
/// holds positions, offsets and evidence, so review can point at a passage
/// without a confidence annotation ever appearing in recognised prose.
///
/// It duplicates nothing. A candidate names a span by index and the words are
/// read back from the transcript, so the two cannot disagree and losing the
/// sidecar costs review information and nothing else — a session without one
/// behaves exactly like every session recorded before this file existed.
///
/// The record is versioned from its first release, and ``schemaVersion`` is
/// read on its own before anything else is interpreted, so a file written by a
/// later ScribeKit is refused rather than misread as this one.
nonisolated struct SessionReviewMetadata: Codable, Equatable, Sendable {

    /// The schema version this build writes and is able to read.
    static let currentSchemaVersion = 1

    /// The version of the record's layout.
    let schemaVersion: Int

    /// The session's stable identity, matching ``MeetingSession/id`` and the
    /// identity `session.json` carries.
    let sessionID: UUID

    /// Whether the recogniser attached its own confidence to any span in this
    /// meeting.
    ///
    /// Recorded because its absence is meaningful: a session where no
    /// confidence was reported has only ScribeKit's own observations to offer,
    /// and saying so is better than letting an empty candidate list imply that
    /// the recogniser was sure.
    let recognizerConfidenceAvailable: Bool

    /// The spans put forward for review, in transcript order.
    let candidates: [TranscriptReviewCandidate]

    /// Creates a record.
    ///
    /// - Parameters:
    ///   - schemaVersion: The layout version. Defaults to
    ///     ``currentSchemaVersion``; a test passes another to prove an unknown
    ///     version is refused.
    ///   - sessionID: The session's stable identity.
    ///   - recognizerConfidenceAvailable: Whether the recogniser reported any
    ///     confidence of its own.
    ///   - candidates: The spans put forward for review, in transcript order.
    init(
        schemaVersion: Int = SessionReviewMetadata.currentSchemaVersion,
        sessionID: UUID,
        recognizerConfidenceAvailable: Bool,
        candidates: [TranscriptReviewCandidate]
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.recognizerConfidenceAvailable = recognizerConfidenceAvailable
        self.candidates = candidates
    }

    /// The candidates in the order review shows them: transcript order, which
    /// is the order they were spoken.
    var orderedCandidates: [TranscriptReviewCandidate] {
        candidates.sorted { $0.spanIndex < $1.spanIndex }
    }
}

// MARK: - Encoding

nonisolated extension SessionReviewMetadata {

    /// Only the version, read before anything else is interpreted.
    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    /// The encoder used for every review sidecar ScribeKit writes.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Renders the record as the bytes of `review.json`.
    ///
    /// - Returns: UTF-8 JSON.
    /// - Throws: ``SessionReviewError/malformed`` when the record cannot be
    ///   encoded, which would mean a programming error rather than a damaged
    ///   file.
    func encoded() throws -> Data {
        do {
            return try Self.encoder.encode(self)
        } catch {
            throw SessionReviewError.malformed
        }
    }

    /// Reads a sidecar, refusing anything this build cannot interpret.
    ///
    /// - Parameter data: The contents of `review.json`.
    /// - Returns: The decoded record.
    /// - Throws: ``SessionReviewError/malformed`` when the bytes are not a
    ///   readable record, or
    ///   ``SessionReviewError/unsupportedSchemaVersion(_:)`` when they
    ///   announce a version this build does not know.
    static func decoded(from data: Data) throws -> SessionReviewMetadata {
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(SchemaProbe.self, from: data) else {
            throw SessionReviewError.malformed
        }
        guard probe.schemaVersion == currentSchemaVersion else {
            throw SessionReviewError.unsupportedSchemaVersion(probe.schemaVersion)
        }
        guard let metadata = try? decoder.decode(SessionReviewMetadata.self, from: data) else {
            throw SessionReviewError.malformed
        }
        return metadata
    }
}

/// Writes the review sidecar beside a transcript.
///
/// A separate boundary from ``SessionRecoveryStoring`` because it answers a
/// separate question, and narrow enough that the production implementation has
/// no logic and a double can fail on demand.
nonisolated protocol SessionReviewStoring: Sendable {

    /// Writes a session's review metadata.
    ///
    /// - Parameters:
    ///   - metadata: What the meeting observed about its own recognition.
    ///   - layout: Where the session's artifacts live.
    /// - Throws: ``SessionReviewError/writeFailed`` when the sidecar could not
    ///   be written. Nothing else in the session directory is touched.
    func writeReview(_ metadata: SessionReviewMetadata, to layout: SessionArtifactLayout) throws
}

/// The review sidecar as `FileManager` writes it.
nonisolated struct FileManagerSessionReviewStore: SessionReviewStoring {

    /// Creates the system-backed store.
    init() {}

    func writeReview(_ metadata: SessionReviewMetadata, to layout: SessionArtifactLayout) throws {
        let data = try metadata.encoded()
        do {
            try FileManager.default.createDirectory(
                at: layout.metadataDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: layout.reviewURL, options: [.atomic])
        } catch {
            throw SessionReviewError.writeFailed
        }
    }
}
