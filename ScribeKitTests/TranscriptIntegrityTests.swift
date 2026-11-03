//
//  TranscriptIntegrityTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// The seal, the verdict and the record field that carries the seal.
///
/// Everything here is pure or touches only a temporary file the test writes.
/// Every transcript is synthetic.
@Suite("Transcript integrity")
struct TranscriptIntegrityTests {

    private let sessionID = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
    private let startedAt = TranscriptFixture.startedAt

    /// A synthetic transcript with multiline Markdown, CRLF and LF line
    /// endings, a blockquote, and text outside ASCII — the shapes a byte-level
    /// check must not normalise away.
    static let unicodeMarkdown = "# Réunion — 東京 🚀\r\n\r\n**Date:** 2026-08-29\n\n## Transcript\n\n"
        + "**10:01:33 AM**\n\nNaïve café — “quoted” Ελληνικά, 日本語, emoji 👩🏽‍💻.\n\n"
        + "> **Transcription gap:** approximately 0.8 seconds.\n\n---\n\n**Ended:** 10:02 AM\n"

    private func record(
        status: SessionRecoveryStatus = .completed,
        seal: TranscriptSeal? = nil
    ) -> SessionRecoveryMetadata {
        SessionRecoveryMetadata(
            sessionID: sessionID,
            title: "Closures Walkthrough",
            startedAt: startedAt,
            sourceNames: ["QuickTime Player"],
            localeIdentifier: "en-US",
            status: status,
            endedAt: status == .inProgress ? nil : startedAt.addingTimeInterval(120),
            transcriptSeal: seal
        )
    }

    private func session(
        status: HistorySessionStatus = .completed,
        endedAt: Date? = TranscriptFixture.startedAt.addingTimeInterval(120),
        seal: TranscriptSeal? = nil
    ) -> HistorySession {
        let directory = URL(filePath: "/Users/example/Meetings/2026-08-29-closures", directoryHint: .isDirectory)
        return HistorySession(
            directory: directory,
            sessionID: status == .unrecorded ? nil : sessionID,
            title: "Closures Walkthrough",
            status: status,
            startedAt: status == .unrecorded ? nil : startedAt,
            endedAt: endedAt,
            sourceNames: [],
            localeIdentifier: "en-US",
            transcriptURL: SessionArtifactLayout(directory: directory).transcriptURL,
            transcript: SessionFileInfo(byteCount: 10, modifiedAt: nil),
            audioRetention: nil,
            audio: nil,
            transcriptSeal: seal
        )
    }

    // MARK: - Seal

    @Test("A seal is SHA-256 over the exact bytes, in lower-case hexadecimal")
    func sealMatchesKnownVectors() {
        let abc = TranscriptSeal.sealing(Data("abc".utf8))
        #expect(abc.algorithm == "sha256")
        #expect(abc.digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(abc.byteCount == 3)

        let empty = TranscriptSeal.sealing(Data())
        #expect(empty.digest == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(empty.byteCount == 0)
    }

    @Test("Sealing a file in chunks agrees with sealing its bytes, at any chunk size", arguments: [1, 7, 64, 65_536])
    func streamingSealAgreesWithInMemory(chunkSize: Int) throws {
        let url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "ScribeKitSeal-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data(Self.unicodeMarkdown.utf8)
        try data.write(to: url)

        #expect(try TranscriptSeal.sealing(fileAt: url, chunkSize: chunkSize) == TranscriptSeal.sealing(data))
    }

    @Test("Sealing a file only reads it")
    func sealingDoesNotTouchTheFile() throws {
        let url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "ScribeKitSeal-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(Self.unicodeMarkdown.utf8).write(to: url)
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        _ = try FileTranscriptSealer().seal(transcriptAt: url)

        #expect(try Data(contentsOf: url) == Data(Self.unicodeMarkdown.utf8))
        #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
    }

    @Test("A missing file cannot be sealed, and says so rather than sealing nothing")
    func missingFileIsNotSealed() {
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "absent-\(UUID().uuidString).md")
        #expect(throws: (any Error).self) { try FileTranscriptSealer().seal(transcriptAt: url) }
    }

    // MARK: - Verdict

    @Test("An unchanged transcript is verified")
    func unchangedIsVerified() {
        let data = Data(Self.unicodeMarkdown.utf8)
        let seal = TranscriptSeal.sealing(data)
        #expect(TranscriptIntegrity.assess(seal: seal, unsealed: .notRecorded, data: data) == .verified)
        #expect(session(seal: seal).integrity(of: .sealing(data)) == .verified)
    }

    @Test("A shorter, longer or same-length different transcript is changed, with both lengths stated")
    func modifiedIsChanged() {
        let original = Data(Self.unicodeMarkdown.utf8)
        let seal = TranscriptSeal.sealing(original)

        let truncated = original.prefix(original.count / 2)
        #expect(TranscriptIntegrity.assess(seal: seal, unsealed: .notRecorded, data: Data(truncated))
            == .changed(expectedByteCount: original.count, observedByteCount: truncated.count))

        let appended = original + Data("\nAdded later.\n".utf8)
        #expect(TranscriptIntegrity.assess(seal: seal, unsealed: .notRecorded, data: appended)
            == .changed(expectedByteCount: original.count, observedByteCount: appended.count))

        var flipped = original
        flipped[flipped.startIndex] = UInt8(ascii: "%")
        #expect(TranscriptIntegrity.assess(seal: seal, unsealed: .notRecorded, data: flipped)
            == .changed(expectedByteCount: original.count, observedByteCount: original.count))

        #expect(TranscriptIntegrity.assess(seal: seal, unsealed: .notRecorded, data: Data())
            == .changed(expectedByteCount: original.count, observedByteCount: 0))
    }

    @Test("Line endings are bytes: converting CRLF to LF is a change, not an equivalence")
    func lineEndingNormalisationIsAChange() {
        let original = Data(Self.unicodeMarkdown.utf8)
        let normalised = Data(Self.unicodeMarkdown.replacingOccurrences(of: "\r\n", with: "\n").utf8)
        #expect(TranscriptIntegrity.assess(seal: .sealing(original), unsealed: .notRecorded, data: normalised)
            != .verified)
    }

    @Test("A missing seal is never a mismatch, whatever the transcript holds")
    func missingSealIsUnverified() {
        for data in [Data(), Data("anything".utf8), Data(Self.unicodeMarkdown.utf8)] {
            #expect(TranscriptIntegrity.assess(seal: nil, unsealed: .notRecorded, data: data)
                == .unverified(.notRecorded))
        }
        #expect(!TranscriptIntegrity.unverified(.notRecorded).isWarning)
        #expect(!TranscriptIntegrity.unverified(.noRecord).isWarning)
    }

    @Test("A seal in an algorithm this build does not know is unverified, not changed")
    func unknownAlgorithmIsUnverified() {
        let seal = TranscriptSeal(algorithm: "blake3", digest: "00", byteCount: 3)
        #expect(TranscriptIntegrity.assess(seal: seal, unsealed: .notRecorded, data: Data("abc".utf8))
            == .unverified(.unsupportedAlgorithm("blake3")))
        #expect(session(seal: seal).integrity(of: .sealing(Data("abc".utf8)))
            == .unverified(.unsupportedAlgorithm("blake3")))
    }

    @Test("Why a session has no seal follows from what its record says")
    func unsealedReasonsFollowTheRecord() {
        #expect(session(status: .unrecorded, endedAt: nil).unsealedReason == .noRecord)
        #expect(session(status: .inProgress, endedAt: nil).unsealedReason == .stillOpen)
        #expect(session(status: .interrupted, endedAt: nil).unsealedReason == .interruptedBeforeSealing)
        #expect(session(status: .interrupted).unsealedReason == .notRecorded)
        #expect(session(status: .completed).unsealedReason == .notRecorded)
        #expect(session(status: .failed).unsealedReason == .notRecorded)
        // Before any reading, a session starts from that reason.
        #expect(session(status: .unrecorded, endedAt: nil).integrity == .unverified(.noRecord))
    }

    @Test("Verifying a session against a reading replaces nothing but the verdict")
    func verifiedCopyKeepsEverythingElse() {
        let data = Data(Self.unicodeMarkdown.utf8)
        let original = session(seal: .sealing(data))
        let checked = original.verified(against: TranscriptReading(text: Self.unicodeMarkdown, observed: .sealing(data)))
        #expect(checked.integrity == .verified)
        #expect(checked.transcriptSeal == original.transcriptSeal)
        #expect(checked.title == original.title)
        #expect(checked.transcriptURL == original.transcriptURL)
    }

    @Test("Explanations name no transcript words and only warnings read as warnings")
    func explanationsAreProportionate() {
        let verdicts: [TranscriptIntegrity] = [
            .verified, .unverified(.noRecord), .unverified(.notRecorded), .unverified(.stillOpen),
            .unverified(.interruptedBeforeSealing), .unverified(.unsupportedAlgorithm("x")),
            .changed(expectedByteCount: 10, observedByteCount: 5),
            .changed(expectedByteCount: 10, observedByteCount: 12)
        ]
        for verdict in verdicts {
            #expect(!verdict.explanation.isEmpty)
            #expect(!verdict.explanation.contains("Naïve"))
            #expect(verdict.tone == (verdict.isWarning ? .warning : (verdict == .verified ? .positive : .neutral)))
        }
        #expect(TranscriptIntegrity.changed(expectedByteCount: 10, observedByteCount: 5).explanation.contains("shorter"))
        #expect(TranscriptIntegrity.unverified(.notRecorded).explanation.contains("does not mean anything is wrong"))
    }

    // MARK: - Record

    @Test("A seal survives the record's round trip")
    func sealRoundTrips() throws {
        let sealed = record(seal: .sealing(Data("abc".utf8)))
        #expect(try SessionRecoveryMetadata.decoded(from: sealed.encoded()) == sealed)
        let text = String(decoding: try sealed.encoded(), as: UTF8.self)
        #expect(text.contains("\"transcriptSeal\""))
        #expect(text.contains("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
    }

    @Test("A record without a seal writes no seal key and stays version one")
    func unsealedRecordWritesNoKey() throws {
        let text = String(decoding: try record().encoded(), as: UTF8.self)
        #expect(!text.contains("transcriptSeal"))
        #expect(text.contains("\"schemaVersion\" : 1"))
    }

    @Test("Records written by v0.1.0 and v0.2.0 still decode, with no seal")
    func earlierRecordsDecodeWithoutASeal() throws {
        // The fields v0.2.0 wrote for a completed microphone meeting.
        let json = """
            {
              "audioRetention" : "none",
              "capturedDuration" : 120,
              "captureMode" : "microphone",
              "endedAt" : "2026-08-29T14:03:00Z",
              "localeIdentifier" : "en-US",
              "schemaVersion" : 1,
              "sessionID" : "\(sessionID.uuidString)",
              "sourceNames" : ["MacBook Air Microphone"],
              "startedAt" : "2026-08-29T14:01:00Z",
              "status" : "completed",
              "title" : "Closures Walkthrough",
              "transcriptPath" : "transcript.md"
            }
            """
        let decoded = try SessionRecoveryMetadata.decoded(from: Data(json.utf8))
        #expect(decoded.transcriptSeal == nil)
        #expect(decoded.status == .completed)
    }

    @Test("A record carrying a seal is still readable by a decoder that ignores it")
    func sealIsAdditive() throws {
        struct EarlierRecord: Decodable {
            let schemaVersion: Int
            let status: String
            let transcriptPath: String
        }
        let data = try record(seal: .sealing(Data("abc".utf8))).encoded()
        let earlier = try JSONDecoder().decode(EarlierRecord.self, from: data)
        #expect(earlier.schemaVersion == 1)
        #expect(earlier.status == "completed")
    }

    @Test("Closing a record sets the seal; pausing, gap notes and recovery carry it through")
    func sealIsSetOnlyByClosing() {
        let seal = TranscriptSeal.sealing(Data("abc".utf8))
        let open = record(status: .inProgress)
        let closed = open.closed(.completed, at: startedAt.addingTimeInterval(60), transcriptSeal: seal)
        #expect(closed.transcriptSeal == seal)
        #expect(closed.pausing(at: nil, capturedDuration: 60).transcriptSeal == seal)
        #expect(closed.notingOpenGap(startedAt: nil).transcriptSeal == seal)
        #expect(closed.markingInterruption(recordedAt: startedAt).transcriptSeal == seal)

        // An open record has none to carry, and recovery does not invent one.
        #expect(open.markingInterruption(recordedAt: startedAt).transcriptSeal == nil)
        // Closing without a readable file records none rather than a stale one.
        #expect(closed.closed(.failed, at: startedAt).transcriptSeal == nil)
    }
}
