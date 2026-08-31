//
//  SessionRecoveryMetadataTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@Suite("SessionRecoveryMetadata")
struct SessionRecoveryMetadataTests {

    private let sessionID = UUID(uuidString: "6F2B1A24-0C5E-4D7A-9E31-8B0A5C4D2E10")!

    /// 31 August 2026, 15:00:00 UTC.
    private let startedAt = Date(timeIntervalSince1970: 1_788_188_400)

    /// A record for a meeting that is still being written.
    ///
    /// - Parameters:
    ///   - status: Where the session stands.
    ///   - schemaVersion: The layout version to claim.
    /// - Returns: The record.
    private func metadata(
        status: SessionRecoveryStatus = .inProgress,
        schemaVersion: Int = SessionRecoveryMetadata.currentSchemaVersion
    ) -> SessionRecoveryMetadata {
        SessionRecoveryMetadata(
            schemaVersion: schemaVersion,
            sessionID: sessionID,
            title: "iOS Training - Day 2",
            startedAt: startedAt,
            sourceNames: ["Microsoft Teams", "QuickTime Player"],
            localeIdentifier: "en-US",
            status: status
        )
    }

    @Test("A record survives a round trip through its own JSON")
    func roundTrip() throws {
        let original = metadata()

        let decoded = try SessionRecoveryMetadata.decoded(from: original.encoded())

        #expect(decoded == original)
    }

    @Test("A record names its schema version, its session and its transcript")
    func recordsWhatRecoveryNeeds() throws {
        let text = try String(decoding: metadata().encoded(), as: UTF8.self)

        #expect(text.contains("\"schemaVersion\" : 1"))
        #expect(text.contains(sessionID.uuidString))
        #expect(text.contains("\"transcriptPath\" : \"transcript.md\""))
        #expect(text.contains("\"status\" : \"inProgress\""))
        #expect(text.contains("2026-08-31T15:00:00Z"))
    }

    @Test("A record holds no transcript text")
    func recordIsNotASecondTranscript() throws {
        let text = try String(decoding: metadata().encoded(), as: UTF8.self)

        #expect(!text.contains("segments"))
        #expect(!text.contains("transcriptText"))
        #expect(text.count < 600)
    }

    @Test("Bytes that are not JSON are reported as damaged rather than guessed at")
    func malformedJSONIsRefused() {
        let data = Data(#"{"schemaVersion": 1, "title": "#.utf8)

        #expect(throws: SessionRecoveryError.metadataMalformed) {
            try SessionRecoveryMetadata.decoded(from: data)
        }
    }

    @Test("JSON without a schema version is damaged, not version one")
    func missingSchemaVersionIsRefused() {
        let data = Data(#"{"title": "A meeting", "status": "inProgress"}"#.utf8)

        #expect(throws: SessionRecoveryError.metadataMalformed) {
            try SessionRecoveryMetadata.decoded(from: data)
        }
    }

    @Test("A record from a later schema is refused rather than read as this one")
    func unknownSchemaVersionIsRefused() throws {
        let data = try metadata(schemaVersion: 2).encoded()

        #expect(throws: SessionRecoveryError.unsupportedSchemaVersion(2)) {
            try SessionRecoveryMetadata.decoded(from: data)
        }
    }

    @Test("A later schema is refused even when its fields would still parse")
    func unknownSchemaVersionIsNotSalvaged() {
        let data = Data("""
            {"schemaVersion": 7, "sessionID": "\(sessionID.uuidString)", "title": "A meeting", \
            "startedAt": "2026-08-31T15:00:00Z", "sourceNames": [], "localeIdentifier": "en-US", \
            "transcriptPath": "transcript.md", "status": "inProgress"}
            """.utf8)

        #expect(throws: SessionRecoveryError.unsupportedSchemaVersion(7)) {
            try SessionRecoveryMetadata.decoded(from: data)
        }
    }

    @Test("A status this build does not know is damaged rather than assumed")
    func unknownStatusIsRefused() {
        let data = Data("""
            {"schemaVersion": 1, "sessionID": "\(sessionID.uuidString)", "title": "A meeting", \
            "startedAt": "2026-08-31T15:00:00Z", "sourceNames": [], "localeIdentifier": "en-US", \
            "transcriptPath": "transcript.md", "status": "abandoned"}
            """.utf8)

        #expect(throws: SessionRecoveryError.metadataMalformed) {
            try SessionRecoveryMetadata.decoded(from: data)
        }
    }

    @Test("Closing a session records how it ended and when")
    func closingRecordsTheOutcome() {
        let endedAt = startedAt.addingTimeInterval(3_600)

        let completed = metadata().closed(.completed, at: endedAt)
        let failed = metadata().closed(.failed, at: endedAt)

        #expect(completed.status == .completed)
        #expect(completed.endedAt == endedAt)
        #expect(failed.status == .failed)
        #expect(failed.endedAt == endedAt)
    }

    @Test("An interruption records when it was noticed and not when the meeting stopped")
    func interruptionRecordsOnlyWhatIsKnown() {
        let noticed = startedAt.addingTimeInterval(86_400)

        let marked = metadata().markingInterruption(recordedAt: noticed)

        #expect(marked.status == .interrupted)
        #expect(marked.interruptedAt == noticed)
        #expect(marked.endedAt == nil)
        #expect(marked.startedAt == startedAt)
    }

    @Test("Only an in-progress record describes a meeting ScribeKit did not close")
    func statusesSeparateClosedSessionsFromLostOnes() {
        #expect(SessionRecoveryStatus.allCases.count == 4)
        #expect(SessionCompletionOutcome.completed.recoveryStatus == .completed)
        #expect(SessionCompletionOutcome.failed.recoveryStatus == .failed)
        #expect(SessionCompletionOutcome.interrupted.recoveryStatus == .interrupted)
    }

    @Test("A meeting closed because capture ended is dated, and is not offered as an unfinished one")
    func closingAnInterruptionRecordsWhatWasObserved() {
        let endedAt = startedAt.addingTimeInterval(3_600)

        let interrupted = metadata()
            .pausing(at: startedAt.addingTimeInterval(60), capturedDuration: 60)
            .closed(.interrupted, at: endedAt, capturedDuration: 1_800)

        #expect(interrupted.status == .interrupted)
        #expect(interrupted.endedAt == endedAt)
        // ScribeKit was running and watched capture end, so unlike a session
        // found after a relaunch this one knows when it was interrupted.
        #expect(interrupted.interruptedAt == endedAt)
        #expect(interrupted.capturedDuration == 1_800)
        // A closed meeting is not paused, and is not an abandoned pause.
        #expect(interrupted.pausedAt == nil)
        #expect(!interrupted.wasPausedWhenInterrupted)
        // Recovery only ever considers a record still saying in progress.
        #expect(interrupted.status != .inProgress)
    }

    @Test("Closing records the captured length, and a caller that cannot measure one changes nothing")
    func closingCarriesTheCapturedLength() {
        let endedAt = startedAt.addingTimeInterval(600)

        let measured = metadata().closed(.completed, at: endedAt, capturedDuration: 599.5)
        let legacy = metadata().closed(.completed, at: endedAt)

        #expect(measured.capturedDuration == 599.5)
        #expect(legacy.capturedDuration == nil)
    }

    @Test("A record written before captured duration existed carries no such key and still decodes")
    func legacyRecordsDecodeWithoutACapturedLength() throws {
        let legacy = metadata().closed(.completed, at: startedAt.addingTimeInterval(600))
        let data = try legacy.encoded()

        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("capturedDuration"))
        let decoded = try SessionRecoveryMetadata.decoded(from: data)
        #expect(decoded.capturedDuration == nil)
        #expect(decoded.status == .completed)
    }

    @Test("The transcript is found relative to the directory the record was read from")
    func transcriptIsResolvedRelatively() {
        let moved = URL(filePath: "/Volumes/Backup/2026-08-31-training", directoryHint: .isDirectory)

        #expect(metadata().transcriptURL(in: moved).path(percentEncoded: false)
                == "/Volumes/Backup/2026-08-31-training/transcript.md")
    }

    @Test("A record says what the meeting was keeping of its audio")
    func recordsAudioRetention() throws {
        let record = SessionRecoveryMetadata(
            sessionID: sessionID,
            title: "iOS Training - Day 2",
            startedAt: startedAt,
            sourceNames: ["QuickTime Player"],
            localeIdentifier: "en-US",
            audioRetention: .compressed,
            audioPath: "audio.m4a",
            status: .inProgress
        )

        let text = try String(decoding: record.encoded(), as: UTF8.self)
        #expect(text.contains("\"audioRetention\" : \"compressed\""))
        #expect(text.contains("\"audioPath\" : \"audio.m4a\""))
        #expect(try SessionRecoveryMetadata.decoded(from: record.encoded()) == record)
    }

    @Test("A meeting keeping no audio names no audio file")
    func noRetentionNamesNoFile() throws {
        let record = SessionRecoveryMetadata(
            sessionID: sessionID,
            title: "iOS Training - Day 2",
            startedAt: startedAt,
            sourceNames: ["QuickTime Player"],
            localeIdentifier: "en-US",
            audioRetention: AudioRetentionMode.none,
            audioPath: nil,
            status: .inProgress
        )

        let text = try String(decoding: record.encoded(), as: UTF8.self)
        #expect(text.contains("\"audioRetention\" : \"none\""))
        #expect(!text.contains("audioPath"))
        #expect(record.audioURL(in: URL(filePath: "/tmp/session", directoryHint: .isDirectory)) == nil)
    }

    @Test("A record written before audio retention existed is still a version one record")
    func earlierRecordsStillDecode() throws {
        // Exactly the fields version one carried before retention was added.
        let json = """
            {
              "schemaVersion" : 1,
              "sessionID" : "\(sessionID.uuidString)",
              "title" : "Closures Walkthrough",
              "startedAt" : "2026-08-31T15:00:00Z",
              "sourceNames" : ["QuickTime Player"],
              "localeIdentifier" : "en-US",
              "transcriptPath" : "transcript.md",
              "status" : "inProgress"
            }
            """

        let decoded = try SessionRecoveryMetadata.decoded(from: Data(json.utf8))

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.audioRetention == nil)
        #expect(decoded.audioPath == nil)
        #expect(decoded.status == .inProgress)
    }

    @Test("The recording is found relative to the directory the record was read from")
    func audioIsFoundRelativeToItsDirectory() {
        let record = SessionRecoveryMetadata(
            sessionID: sessionID,
            title: "Closures Walkthrough",
            startedAt: startedAt,
            sourceNames: [],
            localeIdentifier: "en-US",
            audioRetention: .raw,
            audioPath: "audio.caf",
            status: .inProgress
        )
        let moved = URL(filePath: "/Users/someone/Meetings/2026-08-31-closures", directoryHint: .isDirectory)

        #expect(record.audioURL(in: moved)?.path(percentEncoded: false)
                == "/Users/someone/Meetings/2026-08-31-closures/audio.caf")
    }

    @Test("Closing a session keeps what it was recording")
    func closingKeepsRetention() {
        let record = SessionRecoveryMetadata(
            sessionID: sessionID,
            title: "Closures Walkthrough",
            startedAt: startedAt,
            sourceNames: [],
            localeIdentifier: "en-US",
            audioRetention: .raw,
            audioPath: "audio.caf",
            status: .inProgress
        )

        let closed = record.closed(.completed, at: startedAt.addingTimeInterval(600))

        #expect(closed.audioRetention == .raw)
        #expect(closed.audioPath == "audio.caf")
    }
}
