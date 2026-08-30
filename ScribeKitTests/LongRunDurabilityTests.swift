//
//  LongRunDurabilityTests.swift
//  ScribeKitTests
//

import AVFAudio
import Foundation
import Testing
@testable import ScribeKit

/// What the durable artifacts do when they are written for a long time, and
/// what is left of them when the process writing them does not get to close
/// them.
///
/// Unlike the rest of the reliability coverage these tests use the real writers
/// against real files in a temporary directory: `FileManager`, `FileHandle`,
/// `AVAudioFile` and the container formats themselves. They are therefore
/// evidence about frameworks and file formats, and still not evidence about
/// ScreenCaptureKit, the Speech framework or a real user's disk filling up.
@Suite("Long-run durability")
struct LongRunDurabilityTests {

    private let zone = TimeZone(identifier: "America/New_York")!

    private let format = CapturedAudioFormat(
        sampleRate: 48_000,
        channelCount: 1,
        bitsPerChannel: 32,
        isFloat: true,
        isInterleaved: false
    )

    /// A directory that exists for the length of one test.
    private func makeRoot() throws -> URL {
        let root = URL.temporaryDirectory.appending(
            path: "scribekit-reliability-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A buffer of real samples, the size ScreenCaptureKit delivers.
    private func buffer(frames: Int = 1_024) -> CapturedPCMBuffer {
        CapturedPCMBuffer(
            format: format,
            frameCount: frames,
            presentationTime: nil,
            peakAmplitude: 0.5,
            samples: (0..<frames).map { Float(sin(Double($0) * 0.05)) * 0.5 }
        )
    }

    /// A finalised span at a given offset.
    private func segment(_ text: String, start: Double) -> TranscriptSegment {
        TranscriptSegment(
            text: text,
            startTime: start,
            endTime: start + 2,
            state: .final,
            localeIdentifier: "en-US"
        )
    }

    // MARK: - Long transcripts

    @Test("A long transcript stays parseable and ordered, and repeating it holds nothing open")
    func longTranscriptStaysConsistent() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // Three two-hour transcripts in one process, each written and closed
        // through the real store, so a session that failed to release what it
        // opened would show up as the next one refusing to write.
        for run in 0..<3 {
            let layout = try await writeLongSession(in: root, named: "Long Run \(run)")

            let markdown = try String(contentsOf: layout.transcriptURL, encoding: .utf8)
            let document = TranscriptDocument.parse(markdown)
            #expect(document.spans.count == 2_400)
            // Each span states the offset it was written at, so the document's
            // own order can be checked against the order it was written in:
            // nothing reordered, nothing lost, nothing written twice.
            let written = document.spans.compactMap { span in
                Int(span.text.dropFirst("Span at ".count).prefix { $0.isNumber })
            }
            #expect(written.count == 2_400)
            #expect(zip(written, written.dropFirst()).allSatisfy { $0 < $1 })
            #expect(markdown.contains("**Ended:**"))
            #expect(markdown.contains("**Captured:**"))
        }

        // Three distinct session directories, each with its own transcript.
        #expect(try FileManager.default.contentsOfDirectory(
            atPath: root.path(percentEncoded: false)
        ).count == 3)
    }

    /// Writes one two-hour transcript through the real store and closes it.
    ///
    /// - Parameters:
    ///   - root: The folder the session directory is created in.
    ///   - title: The meeting's title, which names its directory.
    /// - Returns: Where the session's artifacts were written.
    private func writeLongSession(in root: URL, named title: String) async throws -> SessionArtifactLayout {
        let store = MarkdownTranscriptStore(access: FakeSecurityScopedAccess(), timeZone: zone)
        let startedAt = Date(timeIntervalSinceReferenceDate: 0)
        let meeting = MeetingSession(
            title: title,
            createdAt: startedAt,
            selectedSources: [.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")],
            destination: root
        )
        let layout = try await store.startSession(meeting, localeIdentifier: "en-US", startedAt: startedAt)

        // Two hours of transcript at a span every three seconds, with a gap in
        // every block and a pause between blocks.
        var offset = 0.0
        for block in 0..<12 {
            for _ in 0..<200 {
                try await store.appendFinalSegment(segment("Span at \(Int(offset)) seconds.", start: offset))
                offset += 3
            }
            try await store.recordGap(TranscriptGap(duration: 1.5, reason: .audioDropped))
            if block < 11 {
                try await store.recordPause(
                    at: startedAt.addingTimeInterval(offset + Double(block) * 120),
                    capturedDuration: offset
                )
                try await store.recordResume(
                    at: startedAt.addingTimeInterval(offset + Double(block + 1) * 120),
                    capturedDuration: offset
                )
            }
        }
        try await store.finishSession(
            endedAt: startedAt.addingTimeInterval(offset + 1_440),
            outcome: .completed,
            capturedDuration: offset
        )
        return layout
    }

    // MARK: - Recordings a process did not get to close

    @Test(
        "What a recording is worth when nothing closed it is decided by the container, and stated",
        arguments: [AudioRetentionMode.raw, .compressed]
    )
    func partiallyWrittenRecording(_ mode: AudioRetentionMode) async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let layout = SessionArtifactLayout(destination: root, directoryName: "session")
        try FileManager.default.createDirectory(at: layout.directory, withIntermediateDirectories: true)
        let recorder = RetainedAudioRecorder()
        let url = try #require(try recorder.startSession(mode: mode, layout: layout, format: format))

        for _ in 0..<500 { recorder.consume(buffer()) }

        // The bytes on disk while the writer is still open are what a process
        // that was killed leaves behind: whatever the framework had already
        // written, with nothing that happens at close.
        let snapshot = root.appending(path: "snapshot.\(url.pathExtension)")
        try FileManager.default.copyItem(at: url, to: snapshot)
        try recorder.finishSession()

        let readableFrames = (try? AVAudioFile(forReading: snapshot))?.length
        let closedFrames = try #require((try? AVAudioFile(forReading: url))?.length)
        #expect(closedFrames > 0)

        switch mode {
        case .raw:
            // A CAF holds its frames as they are written, so an unfinalised one
            // opens and plays up to the moment writing stopped.
            let frames = try #require(readableFrames)
            #expect(frames > 0)
        case .compressed:
            // An MPEG-4 container is indexed when it is closed. This is the
            // documented limitation, checked against the framework rather than
            // asserted: whatever an unfinalised file yields, it is not the
            // audio that was written.
            #expect(readableFrames == nil || readableFrames! < closedFrames)
        case .none:
            Issue.record("A meeting that keeps no audio has no recording to read.")
        }
    }

    @Test("Twenty recordings in one process each close and each stay readable")
    func repeatedRecordingsStayReadable() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = SessionArtifactLayout(destination: root, directoryName: "session")
        try FileManager.default.createDirectory(at: layout.directory, withIntermediateDirectories: true)
        var lengths: [AVAudioFramePosition] = []

        for _ in 0..<20 {
            let recorder = RetainedAudioRecorder()
            let directory = layout.directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let cycle = SessionArtifactLayout(destination: directory, directoryName: "session")
            try FileManager.default.createDirectory(at: cycle.directory, withIntermediateDirectories: true)
            let url = try #require(try recorder.startSession(mode: .raw, layout: cycle, format: format))
            for _ in 0..<50 { recorder.consume(buffer()) }
            try recorder.finishSession()
            lengths.append(try AVAudioFile(forReading: url).length)
        }

        // Every recording holds exactly what it was given, and no recording
        // carried anything over from the one before it.
        #expect(lengths == Array(repeating: 50 * 1_024, count: 20))
    }
}
