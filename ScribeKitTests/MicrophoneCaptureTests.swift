//
//  MicrophoneCaptureTests.swift
//  ScribeKitTests
//

import AVFAudio
import Foundation
import Synchronization
import Testing
@testable import ScribeKit

/// Records what reached it, the way the meeting's fan-out consumer would see
/// it.
private nonisolated final class RecordingConsumer: AudioSampleConsuming, @unchecked Sendable {
    private let state = Mutex<(buffers: [CapturedPCMBuffer], unreadable: Int)>(([], 0))

    var buffers: [CapturedPCMBuffer] { state.withLock { $0.buffers } }
    var unreadable: Int { state.withLock { $0.unreadable } }

    func consume(_ buffer: CapturedPCMBuffer) {
        state.withLock { $0.buffers.append(buffer) }
    }

    func recordUnreadableSample() {
        state.withLock { $0.unreadable += 1 }
    }
}

/// The microphone's side of the capture boundary, exercised with buffers made
/// in the test and stated permission answers — no microphone, no audio engine
/// running, and no permission prompt.
@Suite("Microphone capture boundary")
struct MicrophoneCaptureTests {

    /// A float buffer of the given shape, each channel filled by `value`.
    private func pcm(
        sampleRate: Double = 48_000,
        channels: Int = 1,
        frames: Int,
        interleaved: Bool = false,
        value: (_ channel: Int, _ frame: Int) -> Float
    ) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: interleaved
        ))
        let capacity = AVAudioFrameCount(max(frames, 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity))
        buffer.frameLength = AVAudioFrameCount(frames)
        let data = try #require(buffer.floatChannelData)
        for frame in 0..<frames {
            for channel in 0..<channels {
                if interleaved {
                    data[0][frame * channels + channel] = value(channel, frame)
                } else {
                    data[channel][frame] = value(channel, frame)
                }
            }
        }
        return buffer
    }

    // MARK: - Adapter

    @Test("A tenth of a second at 48 kHz becomes five 20 ms buffers with every frame kept, in order")
    func cutsIntoTwentyMillisecondPieces() throws {
        let buffer = try pcm(frames: 4_800) { _, frame in Float(frame) / 4_800 }
        let pieces = try #require(MicrophonePCMBufferAdapter.buffers(from: buffer, at: nil))

        #expect(pieces.map(\.frameCount) == [960, 960, 960, 960, 960])
        #expect(pieces.allSatisfy { $0.format.sampleRate == 48_000 && $0.format.channelCount == 1 })
        #expect(pieces.allSatisfy { $0.format.isFloat && !$0.format.isInterleaved })
        let joined = pieces.flatMap(\.samples)
        #expect(joined.count == 4_800)
        #expect(joined.first == 0)
        #expect(joined[960] == Float(960) / 4_800, "the second piece starts where the first ended")
        #expect(pieces.allSatisfy { $0.presentationTime == nil }, "no time is invented when the engine gave none")
    }

    @Test("Another sample rate is kept, cut at its own 20 ms, with the remainder in a last short piece")
    func keepsTheDeviceRate() throws {
        let buffer = try pcm(sampleRate: 44_100, frames: 2_000) { _, _ in 0.1 }
        let pieces = try #require(MicrophonePCMBufferAdapter.buffers(from: buffer, at: nil))
        #expect(pieces.map(\.frameCount) == [882, 882, 236])
        #expect(pieces.allSatisfy { $0.format.sampleRate == 44_100 })
        let seconds = pieces.map(\.duration).reduce(0, +)
        #expect(abs(seconds - 2_000.0 / 44_100) < 1e-9, "no audio is added or lost")
    }

    @Test("Several channels are averaged into one, whichever layout they arrive in")
    func mixesChannelsToMono() throws {
        let separate = try pcm(channels: 2, frames: 960) { channel, _ in channel == 0 ? 0.5 : -0.1 }
        let interleaved = try pcm(channels: 2, frames: 960, interleaved: true) { channel, _ in
            channel == 0 ? 0.5 : -0.1
        }
        for buffer in [separate, interleaved] {
            let pieces = try #require(MicrophonePCMBufferAdapter.buffers(from: buffer, at: nil))
            #expect(pieces.count == 1)
            #expect(pieces[0].format.channelCount == 1)
            #expect(pieces[0].samples.allSatisfy { abs($0 - 0.2) < 1e-6 })
            #expect(abs(pieces[0].peakAmplitude - 0.2) < 1e-6)
        }
    }

    @Test("Each piece carries the engine's time for its own first frame")
    func presentationTimesAdvanceByPiece() throws {
        let buffer = try pcm(frames: 1_920) { _, _ in 0 }
        let time = AVAudioTime(sampleTime: 96_000, atRate: 48_000)
        let pieces = try #require(MicrophonePCMBufferAdapter.buffers(from: buffer, at: time))
        #expect(pieces.count == 2)
        #expect(pieces.first?.presentationTime == 2.0)
        #expect(abs((pieces.last?.presentationTime ?? 0) - 2.02) < 1e-9)
    }

    @Test("Audio in a format it cannot read is reported rather than reinterpreted")
    func refusesIntegerAudio() throws {
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48_000,
            channels: 1,
            interleaved: true
        ))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 960))
        buffer.frameLength = 960
        #expect(MicrophonePCMBufferAdapter.buffers(from: buffer, at: nil) == nil)

        let empty = try pcm(frames: 0) { _, _ in 0 }
        #expect(MicrophonePCMBufferAdapter.buffers(from: empty, at: nil) == nil)
    }

    // MARK: - Tap

    @Test("The tap hands every piece to the consumer, and nothing once it has been stopped")
    func tapDeliversUntilInvalidated() throws {
        let consumer = RecordingConsumer()
        let tap = MicrophoneTap(consumer: consumer)

        let first = try pcm(frames: 4_800) { _, _ in 0.3 }
        tap.deliver(first, at: nil)
        #expect(consumer.buffers.count == 5)
        #expect(consumer.buffers.map(\.frameCount).reduce(0, +) == 4_800)

        tap.invalidate()
        let late = try pcm(frames: 4_800) { _, _ in 0.3 }
        tap.deliver(late, at: nil)
        #expect(consumer.buffers.count == 5, "audio after a stop is not counted as the meeting's")
    }

    @Test("An unreadable buffer is counted, not dropped silently")
    func tapCountsUnreadable() throws {
        let consumer = RecordingConsumer()
        let tap = MicrophoneTap(consumer: consumer)
        let empty = try pcm(frames: 0) { _, _ in 0 }
        tap.deliver(empty, at: nil)
        #expect(consumer.unreadable == 1)
        #expect(consumer.buffers.isEmpty)
    }

    // MARK: - Capturer refusals

    private func configuration(_ id: String = "BuiltInMicrophoneDevice") -> AudioCaptureConfiguration {
        AudioCaptureConfiguration(sourceIDs: [id], mode: .microphone)
    }

    @Test("Creating and stopping a microphone capturer asks macOS nothing")
    func idleCapturerIsInert() async {
        let access = FakeMicrophoneAccess(authorization: .notDetermined)
        let capturer = MicrophoneAudioCapturer(consumer: RecordingConsumer(), access: access)
        await capturer.stop()
        try? await capturer.prepare(configuration: AudioCaptureConfiguration(sourceIDs: ["com.example.Meet"]))
        #expect(!access.wasConsulted, "App Audio preparation and an idle stop never touch the microphone")
    }

    @Test("Preparing a Microphone meeting asks for access once and confirms the input")
    func prepareAsksThenConfirms() async throws {
        let access = FakeMicrophoneAccess(authorization: .notDetermined, answer: true)
        let capturer = MicrophoneAudioCapturer(consumer: RecordingConsumer(), access: access)
        try await capturer.prepare(configuration: configuration())
        #expect(access.requests == 1)
        #expect(access.inputReads == 1)
    }

    @Test("Preparing is refused for a refusal, a restriction, no input or a different input")
    func prepareRefusals() async {
        let refused = FakeMicrophoneAccess(authorization: .notDetermined, answer: false)
        await #expect(throws: AudioCaptureError.microphoneAccessDenied) {
            try await MicrophoneAudioCapturer(consumer: RecordingConsumer(), access: refused)
                .prepare(configuration: configuration())
        }
        let restricted = FakeMicrophoneAccess(authorization: .restricted)
        await #expect(throws: AudioCaptureError.microphoneAccessRestricted) {
            try await MicrophoneAudioCapturer(consumer: RecordingConsumer(), access: restricted)
                .prepare(configuration: configuration())
        }
        let silent = FakeMicrophoneAccess(authorization: .authorized, input: nil)
        await #expect(throws: AudioCaptureError.microphoneUnavailable) {
            try await MicrophoneAudioCapturer(consumer: RecordingConsumer(), access: silent)
                .prepare(configuration: configuration())
        }
        let switched = FakeMicrophoneAccess(authorization: .authorized)
        await #expect(throws: AudioCaptureError.microphoneInputChanged) {
            try await MicrophoneAudioCapturer(consumer: RecordingConsumer(), access: switched)
                .prepare(configuration: configuration("AppleUSBAudioEngine:1"))
        }
    }

    @Test("A start never prompts, and refuses before building an engine when access or the input is wrong")
    func startRefusesWithoutPrompting() async {
        let undetermined = FakeMicrophoneAccess(authorization: .notDetermined)
        await #expect(throws: AudioCaptureError.microphoneAccessDenied) {
            try await MicrophoneAudioCapturer(consumer: RecordingConsumer(), access: undetermined)
                .start(configuration: configuration())
        }
        #expect(undetermined.requests == 0, "a resume is never where the user is first asked")

        let revoked = FakeMicrophoneAccess(authorization: .denied)
        await #expect(throws: AudioCaptureError.microphoneAccessDenied) {
            try await MicrophoneAudioCapturer(consumer: RecordingConsumer(), access: revoked)
                .start(configuration: configuration())
        }

        let switched = FakeMicrophoneAccess(authorization: .authorized)
        await #expect(throws: AudioCaptureError.microphoneInputChanged) {
            try await MicrophoneAudioCapturer(consumer: RecordingConsumer(), access: switched)
                .start(configuration: configuration("AppleUSBAudioEngine:1"))
        }
    }

    @Test("A start for application capture is not the microphone capturer's to run")
    func startRefusesApplicationConfiguration() async {
        let access = FakeMicrophoneAccess(authorization: .authorized)
        await #expect(throws: AudioCaptureError.noSourcesSelected) {
            try await MicrophoneAudioCapturer(consumer: RecordingConsumer(), access: access)
                .start(configuration: AudioCaptureConfiguration(sourceIDs: ["com.example.Meet"]))
        }
        #expect(!access.wasConsulted)
    }
}
