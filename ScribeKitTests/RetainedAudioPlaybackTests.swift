//
//  RetainedAudioPlaybackTests.swift
//  ScribeKitTests
//

import AVFoundation
import Foundation
import Testing
@testable import ScribeKit

/// A save folder the model can restore without a bookmark or the sandbox.
private nonisolated final class StubReviewSaveLocation: SaveLocationPersisting, @unchecked Sendable {
    private let folder: URL?

    init(folder: URL?) { self.folder = folder }

    func save(_ url: URL) throws {}

    func restore() throws -> URL? { folder }

    func clear() throws {}
}

@Suite("Retained audio playback")
struct RetainedAudioPlaybackTests {

    /// A flagged span, for planning playback of it.
    ///
    /// - Parameters:
    ///   - start: Seconds from the first captured frame to its start.
    ///   - end: Seconds from the first captured frame to its end.
    ///   - index: Its position in the transcript.
    /// - Returns: The candidate.
    private func candidate(start: Double, end: Double, index: Int = 4) -> TranscriptReviewCandidate {
        TranscriptReviewCandidate(
            spanIndex: index,
            startTime: start,
            endTime: end,
            confidence: 0.2,
            reasons: [.lowConfidence]
        )
    }

    /// A recording of one of the two formats ScribeKit writes.
    ///
    /// - Parameters:
    ///   - url: Where it is.
    ///   - format: Which container it is in.
    /// - Returns: The recording.
    private func audio(_ url: URL, _ format: HistoryAudioFormat) -> HistoryAudio {
        HistoryAudio(url: url, format: format, file: SessionFileInfo(byteCount: 1024, modifiedAt: nil))
    }

    // MARK: - The seek

    /// One row of the seek table.
    struct SeekCase: Sendable {
        let name: String
        let format: HistoryAudioFormat
        let spanStart: Double
        let spanEnd: Double
        let expectedStart: Double
        let expectedEnd: Double
    }

    @Test("Playback seeks to the span's own audio offset, with a little either side", arguments: [
        SeekCase(
            name: "a CAF recording seeks to the span's offset",
            format: .raw, spanStart: 133.25, spanEnd: 137.5,
            expectedStart: 131.25, expectedEnd: 139
        ),
        SeekCase(
            name: "an M4A recording seeks the same way",
            format: .compressed, spanStart: 133.25, spanEnd: 137.5,
            expectedStart: 131.25, expectedEnd: 139
        ),
        SeekCase(
            name: "a span in the first seconds starts at the beginning of the file",
            format: .raw, spanStart: 0.5, spanEnd: 2,
            expectedStart: 0, expectedEnd: 3.5
        ),
        SeekCase(
            name: "a span the recogniser gave no length still has a window",
            format: .compressed, spanStart: 60, spanEnd: 60,
            expectedStart: 58, expectedEnd: 61.5
        )
    ])
    func seek(_ testCase: SeekCase) {
        let url = URL(filePath: "/Users/example/Meetings/meeting/audio", directoryHint: .notDirectory)
        let plan = RetainedAudioPlaybackPlan(
            candidate: candidate(start: testCase.spanStart, end: testCase.spanEnd),
            audio: audio(url, testCase.format)
        )

        #expect(plan.format == testCase.format, "\(testCase.name)")
        #expect(plan.startTime == testCase.expectedStart, "\(testCase.name)")
        #expect(plan.endTime == testCase.expectedEnd, "\(testCase.name)")
        #expect(plan.spanStartTime == testCase.spanStart, "\(testCase.name)")
        #expect(plan.url == url, "\(testCase.name)")
    }

    // MARK: - Playing a real file

    /// Writes a short silent recording of one of ScribeKit's two formats.
    ///
    /// Silent because these tests are about file access and resource
    /// lifetimes, not about audio the machine has to make a noise with.
    ///
    /// - Parameters:
    ///   - format: Which container to write.
    ///   - directory: Where to write it.
    /// - Returns: The recording's location.
    private func writeRecording(_ format: HistoryAudioFormat, in directory: URL) throws -> URL {
        let url = directory.appending(
            path: format == .raw ? "audio.caf" : "audio.m4a",
            directoryHint: .notDirectory
        )
        let sampleRate = 48_000.0
        let settings: [String: Any] = switch format {
        case .raw:
            [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false
            ]
        case .compressed:
            [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1
            ]
        }

        let file = try AVAudioFile(forWriting: url, settings: settings)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        try file.write(from: buffer)
        return url
    }

    /// A directory that is removed when the work finishes.
    ///
    /// - Parameter body: Work to do with the directory.
    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = URL.temporaryDirectory.appending(
            path: "scribekit-playback-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    @Test("Both retained formats play, and each holds one lease for exactly as long as it plays",
          arguments: [HistoryAudioFormat.raw, .compressed])
    @MainActor
    func playbackHoldsOneLease(format: HistoryAudioFormat) async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeRecording(format, in: directory)
            let access = FakeSecurityScopedAccess()
            let player = RetainedAudioPlayer(access: access)

            await player.play(
                RetainedAudioPlaybackPlan(candidate: candidate(start: 0.1, end: 0.4), audio: audio(url, format)),
                in: directory
            )

            #expect(player.playback == .playing(spanIndex: 4))
            #expect(access.started == [directory])
            #expect(access.stopped.isEmpty)

            player.stop()

            #expect(player.playback == .idle)
            #expect(access.isBalanced)
        }
    }

    @Test("Pausing keeps the recording open, and stopping gives it up")
    @MainActor
    func pauseKeepsTheClaimAndStopReleasesIt() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeRecording(.raw, in: directory)
            let access = FakeSecurityScopedAccess()
            let player = RetainedAudioPlayer(access: access)

            await player.play(
                RetainedAudioPlaybackPlan(candidate: candidate(start: 0.1, end: 0.4), audio: audio(url, .raw)),
                in: directory
            )
            player.pause()

            #expect(player.playback == .paused(spanIndex: 4))
            #expect(!player.isPlaying)
            #expect(access.stopped.isEmpty)

            player.resume()
            #expect(player.playback == .playing(spanIndex: 4))

            player.stop()
            #expect(access.isBalanced)
        }
    }

    @Test("A recording that is not there is reported, and nothing is left held")
    @MainActor
    func missingRecordingIsReported() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appending(path: "audio.caf", directoryHint: .notDirectory)
            let access = FakeSecurityScopedAccess()
            let player = RetainedAudioPlayer(access: access)

            await player.play(
                RetainedAudioPlaybackPlan(candidate: candidate(start: 1, end: 2), audio: audio(url, .raw)),
                in: directory
            )

            #expect(player.failureMessage != nil)
            #expect(player.loadedSpanIndex == 4)
            #expect(access.isBalanced)
        }
    }

    @Test("An M4A that was never finalised is reported as such rather than repaired")
    @MainActor
    func truncatedCompressedRecordingIsReported() async throws {
        try await withTemporaryDirectory { directory in
            let url = try writeRecording(.compressed, in: directory)
            let truncated = try Data(contentsOf: url).prefix(96)
            try truncated.write(to: url)

            let access = FakeSecurityScopedAccess()
            let player = RetainedAudioPlayer(access: access)

            await player.play(
                RetainedAudioPlaybackPlan(candidate: candidate(start: 0.1, end: 0.4), audio: audio(url, .compressed)),
                in: directory
            )

            let message = try #require(player.failureMessage)
            #expect(message.contains("indexed when it is closed"))
            #expect(access.isBalanced)
            #expect(try Data(contentsOf: url).count == truncated.count)
        }
    }

    @Test("A meeting that kept no recording offers no playback and takes no claim")
    @MainActor
    func noAudioMeansNoPlayback() async throws {
        let directory = URL(filePath: "/Users/example/Meetings/meeting", directoryHint: .isDirectory)
        let session = HistorySession(
            directory: directory,
            sessionID: UUID(),
            title: "Transcript Only",
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            endedAt: Date(timeIntervalSince1970: 1_800_000_600),
            sourceNames: ["QuickTime Player"],
            localeIdentifier: "en-US",
            transcriptURL: directory.appending(path: "transcript.md", directoryHint: .notDirectory),
            transcript: SessionFileInfo(byteCount: 512, modifiedAt: nil),
            audioRetention: AudioRetentionMode.none,
            audio: nil
        )
        let access = FakeSecurityScopedAccess()
        let player = RetainedAudioPlayer(access: access)
        let model = HistoryModel(
            service: HistoryService(store: FakeHistoryStore(), access: access),
            saveLocation: StubReviewSaveLocation(folder: nil),
            player: player
        )

        await model.play(candidate(start: 1, end: 2), of: session)

        #expect(player.playback == .idle)
        #expect(access.started.isEmpty)
    }
}
