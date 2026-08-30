//
//  RetainedAudioRecorderTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// The recorder's own rules: what it opens, what it writes, what it refuses,
/// and what it does when a write fails.
///
/// Every buffer here is synthetic. Nothing in this suite reaches ScreenCaptureKit
/// or a real meeting.
@Suite("RetainedAudioRecorder")
struct RetainedAudioRecorderTests {

    private let format = CapturedAudioFormat(
        sampleRate: 48_000,
        channelCount: 1,
        bitsPerChannel: 32,
        isFloat: true,
        isInterleaved: false
    )

    private let layout = SessionArtifactLayout(
        destination: URL(filePath: "/tmp/scribekit-tests", directoryHint: .isDirectory),
        directoryName: "2026-08-30-retention"
    )

    /// A synthetic buffer of the shape ScreenCaptureKit delivers.
    ///
    /// - Parameters:
    ///   - frames: How many frames to carry.
    ///   - format: The format to claim. The captured one by default.
    /// - Returns: A buffer ready to deliver.
    private func buffer(frames: Int = 960, format: CapturedAudioFormat? = nil) -> CapturedPCMBuffer {
        let format = format ?? self.format
        return CapturedPCMBuffer(
            format: format,
            frameCount: frames,
            presentationTime: nil,
            peakAmplitude: 0.25,
            samples: [Float](repeating: 0.25, count: frames * format.channelCount)
        )
    }

    /// A recorder over a creator that hands out doubles.
    ///
    /// - Returns: The recorder and the creator behind it.
    private func makeRecorder() -> (RetainedAudioRecorder, FakeAudioFileCreator) {
        let creator = FakeAudioFileCreator()
        return (RetainedAudioRecorder(creator: creator), creator)
    }

    @Test("Keeping no audio opens no file and writes nothing")
    func noneModeCreatesNothing() throws {
        let (recorder, creator) = makeRecorder()

        let url = try recorder.startSession(mode: .none, layout: layout, format: format)
        recorder.consume(buffer())
        recorder.consume(buffer())

        #expect(url == nil)
        #expect(creator.requests.isEmpty)
        #expect(recorder.retainedFrameCount == 0)
        #expect(!recorder.isRecording)
    }

    @Test("Each retaining mode opens the artifact its layout names", arguments: [
        (AudioRetentionMode.raw, "audio.caf"),
        (AudioRetentionMode.compressed, "audio.m4a")
    ])
    func retainingModesOpenTheirArtifact(mode: AudioRetentionMode, name: String) throws {
        let (recorder, creator) = makeRecorder()

        let url = try recorder.startSession(mode: mode, layout: layout, format: format)

        #expect(url == layout.audioURL(for: mode))
        #expect(url?.lastPathComponent == name)
        #expect(creator.requests.count == 1)
        #expect(creator.requests.first?.mode == mode)
        #expect(creator.requests.first?.format == format)
    }

    @Test("Captured buffers reach the file before consume returns")
    func writesAreSynchronousAndUnqueued() throws {
        let (recorder, creator) = makeRecorder()
        _ = try recorder.startSession(mode: .raw, layout: layout, format: format)

        // The point of the assertion is that it holds immediately: there is no
        // queue, no task and no stream between capture and the file, so after
        // ten thousand deliveries the file has ten thousand writes and the
        // recorder is holding none of them.
        for _ in 0..<10_000 {
            recorder.consume(buffer())
        }

        // One file and one encoder for the whole meeting: nothing is rebuilt
        // per buffer.
        #expect(creator.files.count == 1)
        #expect(creator.lastFile?.writeCount == 10_000)
        #expect(creator.lastFile?.frameCount == 9_600_000)
        #expect(recorder.retainedFrameCount == 9_600_000)
        #expect(recorder.retainedDuration == 200)
    }

    @Test("Audio in another format is refused rather than resampled")
    func mismatchedFormatFails() async throws {
        let (recorder, creator) = makeRecorder()
        _ = try recorder.startSession(mode: .raw, layout: layout, format: format)
        recorder.consume(buffer())

        let stereo = CapturedAudioFormat(
            sampleRate: 48_000,
            channelCount: 2,
            bitsPerChannel: 32,
            isFloat: true,
            isInterleaved: true
        )
        recorder.consume(buffer(format: stereo))

        var iterator = recorder.failures.makeAsyncIterator()
        let failure = await iterator.next()
        #expect(failure?.reason == .unsupportedCapturedFormat)
        #expect(creator.lastFile?.writeCount == 1)
        #expect(creator.lastFile?.isOpen == false)
    }

    @Test("A failed write stops the recording and reports it")
    func writeFailureIsReported() async throws {
        let (recorder, creator) = makeRecorder()
        _ = try recorder.startSession(mode: .raw, layout: layout, format: format)
        creator.lastFile?.failWrites(after: 3)

        for _ in 0..<10 { recorder.consume(buffer()) }

        var iterator = recorder.failures.makeAsyncIterator()
        let failure = await iterator.next()
        #expect(failure?.reason == .audioWriteFailed)
        // Nothing more is attempted after the first failure, and the file is
        // closed rather than left dangling.
        #expect(creator.lastFile?.writeCount == 3)
        #expect(creator.lastFile?.closeCount == 1)
    }

    @Test("Finishing after a failed write reports the write, not the close")
    func finishReportsTheEarlierFailure() throws {
        let (recorder, creator) = makeRecorder()
        _ = try recorder.startSession(mode: .raw, layout: layout, format: format)
        creator.lastFile?.failWrites(after: 1)
        creator.lastFile?.failClose()
        recorder.consume(buffer())
        recorder.consume(buffer())

        var thrown: AudioRetentionError?
        do { try recorder.finishSession() } catch { thrown = error as? AudioRetentionError }
        #expect(thrown?.reason == .audioWriteFailed)
    }

    @Test("Finishing closes the file")
    func finishClosesTheFile() throws {
        let (recorder, creator) = makeRecorder()
        _ = try recorder.startSession(mode: .raw, layout: layout, format: format)
        recorder.consume(buffer())

        try recorder.finishSession()

        #expect(creator.lastFile?.isOpen == false)
        #expect(creator.lastFile?.closeCount == 1)
        #expect(!recorder.isRecording)
        #expect(recorder.retainedFrameCount == 960)
    }

    @Test("A file that cannot be closed fails the session")
    func finishFailureIsReported() throws {
        let (recorder, creator) = makeRecorder()
        _ = try recorder.startSession(mode: .raw, layout: layout, format: format)
        creator.lastFile?.failClose()

        var thrown: AudioRetentionError?
        do { try recorder.finishSession() } catch { thrown = error as? AudioRetentionError }
        #expect(thrown?.reason == .audioFinishFailed)
    }

    @Test("Finishing without a session is refused")
    func finishWithoutSessionIsRefused() {
        let (recorder, _) = makeRecorder()

        var thrown: AudioRetentionError?
        do { try recorder.finishSession() } catch { thrown = error as? AudioRetentionError }
        #expect(thrown?.reason == .noSessionInProgress)
    }

    @Test("A second session is refused while one is open")
    func secondSessionIsRefused() throws {
        let (recorder, _) = makeRecorder()
        _ = try recorder.startSession(mode: .raw, layout: layout, format: format)

        var thrown: AudioRetentionError?
        do {
            _ = try recorder.startSession(mode: .raw, layout: layout, format: format)
        } catch {
            thrown = error as? AudioRetentionError
        }
        #expect(thrown?.reason == .sessionAlreadyInProgress)
    }

    @Test("A file that cannot be created fails the start and leaves nothing open")
    func creationFailureFailsTheStart() {
        let (recorder, creator) = makeRecorder()
        creator.failCreation()

        var thrown: AudioRetentionError?
        do {
            _ = try recorder.startSession(mode: .compressed, layout: layout, format: format)
        } catch {
            thrown = error as? AudioRetentionError
        }
        #expect(thrown?.reason == .cannotCreateAudioFile)
        #expect(!recorder.isRecording)
        #expect(creator.files.isEmpty)
    }

    @Test("Cancelling closes the file and starts no new one")
    func cancelClosesTheFile() throws {
        let (recorder, creator) = makeRecorder()
        _ = try recorder.startSession(mode: .raw, layout: layout, format: format)
        recorder.consume(buffer())

        recorder.cancelSession()

        #expect(creator.lastFile?.isOpen == false)
        #expect(!recorder.isRecording)
    }

    @Test("Two meetings write two files in two session directories")
    func restartOpensADistinctFile() throws {
        let (recorder, creator) = makeRecorder()
        let second = SessionArtifactLayout(
            destination: layout.directory.deletingLastPathComponent(),
            directoryName: "2026-08-30-retention-2"
        )

        let first = try recorder.startSession(mode: .raw, layout: layout, format: format)
        recorder.consume(buffer())
        try recorder.finishSession()
        let again = try recorder.startSession(mode: .raw, layout: second, format: format)
        recorder.consume(buffer())
        try recorder.finishSession()

        #expect(first != again)
        #expect(creator.files.count == 2)
        #expect(creator.files.allSatisfy { $0.frameCount == 960 })
        #expect(recorder.retainedFrameCount == 960)
    }

    @Test("A recording is opened for the format capture was asked for")
    func recordingUsesTheRequestedCaptureFormat() throws {
        let (recorder, creator) = makeRecorder()
        let configuration = AudioCaptureConfiguration(sourceIDs: ["com.example.App"])

        _ = try recorder.startSession(mode: .raw, layout: layout, format: configuration.requestedFormat)
        recorder.consume(buffer())

        #expect(configuration.requestedFormat == format)
        #expect(creator.requests.first?.format == format)
        #expect(creator.lastFile?.frameCount == 960)
    }

    @Test("Buffers arriving with no session open are ignored")
    func buffersOutsideASessionAreIgnored() {
        let (recorder, creator) = makeRecorder()

        recorder.consume(buffer())

        #expect(creator.files.isEmpty)
        #expect(recorder.retainedFrameCount == 0)
    }
}
