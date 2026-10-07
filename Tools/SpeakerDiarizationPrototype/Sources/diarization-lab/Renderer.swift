//
//  Renderer.swift
//  diarization-lab
//

import AVFAudio
import DiarizationCore
import Foundation

struct RenderedFixture: Codable {
    let name: String
    let split: String
    let summary: String
    let duration: Double
    let sampleRate: Double
    let turns: [ReferenceTurn]
}

/// Renders fixture definitions to 16 kHz mono audio plus ground truth.
///
/// Ground truth is measured, not declared: each utterance is rendered alone,
/// trimmed to where its own signal starts and stops, and the reference turn is
/// exactly where those samples were placed in the mix.
struct Renderer {
    static let sampleRate = 16_000.0
    let directory: URL

    func render(_ spec: FixtureSpec) throws -> (RenderedFixture, [Float]) {
        var rng = SeededGenerator(seed: UInt64(abs(spec.name.hashValue32)))
        var mix = [Float](repeating: 0, count: Int(0.5 * Self.sampleRate))
        var cursor = 0.5
        var turns = [ReferenceTurn]()
        for turn in spec.turns {
            var speech = try utterance(voice: turn.voice, text: turn.text)
            let gain = Float(pow(10, turn.gainDecibels / 20))
            speech = speech.map { $0 * gain }
            let start = turn.overlap > 0 ? cursor - turn.overlap : cursor + turn.pauseBefore
            let first = Int(start * Self.sampleRate)
            let end = first + speech.count
            if mix.count < end { mix += [Float](repeating: 0, count: end - mix.count) }
            for i in 0..<speech.count { mix[first + i] += speech[i] }
            turns.append(ReferenceTurn(speaker: turn.speaker, start: Double(first) / Self.sampleRate, end: Double(end) / Self.sampleRate))
            cursor = max(cursor, Double(end) / Self.sampleRate)
        }
        mix += [Float](repeating: 0, count: Int(0.75 * Self.sampleRate))

        let speechRMS = Self.rms(of: mix, in: turns)
        if spec.narrowband { mix = Self.bandLimit(mix) }
        if let snr = spec.noiseSNR {
            let noise = Self.pinkishNoise(count: mix.count, rng: &rng)
            let scale = speechRMS / Float(pow(10, snr / 20)) / Self.rms(noise)
            for i in 0..<mix.count { mix[i] += noise[i] * scale }
        }
        if spec.tonalBackground {
            let bed = Self.tonalBed(count: mix.count)
            let scale = speechRMS / Float(pow(10, 12.0 / 20)) / Self.rms(bed)
            for i in 0..<mix.count { mix[i] += bed[i] * scale }
        }
        // A −70 dBFS floor so "silence" is a room, not digital zero.
        for i in 0..<mix.count { mix[i] += Float.random(in: -0.0003...0.0003, using: &rng) }

        let fixture = RenderedFixture(
            name: spec.name, split: spec.split.rawValue, summary: spec.summary,
            duration: Double(mix.count) / Self.sampleRate, sampleRate: Self.sampleRate, turns: turns
        )
        return (fixture, mix)
    }

    /// One utterance, rendered by `say`, trimmed and normalised to −23 dBFS RMS.
    func utterance(voice: String, text: String) throws -> [Float] {
        let cache = directory.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let file = cache.appendingPathComponent(String(format: "%08x.wav", (voice + "|" + text).hashValue32))
        if !FileManager.default.fileExists(atPath: file.path) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = ["-v", voice, "-o", file.path, "--file-format=WAVE", "--data-format=LEF32@16000", text]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw LabError.render("say failed for voice \(voice)") }
        }
        var samples = try Self.read(file)
        let threshold = (samples.map(abs).max() ?? 0) * 0.02
        let first = samples.firstIndex { abs($0) > threshold } ?? 0
        let last = samples.lastIndex { abs($0) > threshold } ?? samples.count - 1
        samples = Array(samples[first...last])
        let target: Float = 0.0708
        let scale = target / max(1e-6, Self.rms(samples))
        return samples.map { $0 * scale }
    }

    static func read(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.processingFormat.sampleRate == sampleRate, file.processingFormat.channelCount == 1 else {
            throw LabError.render("unexpected format in \(url.lastPathComponent)")
        }
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    static func write(_ samples: [Float], to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
    }

    static func rms(_ x: [Float]) -> Float {
        sqrt(x.reduce(0) { $0 + $1 * $1 } / Float(max(1, x.count)))
    }

    static func rms(of mix: [Float], in turns: [ReferenceTurn]) -> Float {
        var sum: Float = 0, n = 0
        for t in turns {
            for i in Int(t.start * sampleRate)..<min(mix.count, Int(t.end * sampleRate)) { sum += mix[i] * mix[i]; n += 1 }
        }
        return sqrt(sum / Float(max(1, n)))
    }

    /// White noise through a one-pole low-pass: more energy low, like a room
    /// or a fan, without pretending to be any particular real recording.
    static func pinkishNoise(count: Int, rng: inout SeededGenerator) -> [Float] {
        var y: Float = 0
        return (0..<count).map { _ in
            y = 0.97 * y + 0.03 * Float.random(in: -1...1, using: &rng) * 10
            return y + Float.random(in: -1...1, using: &rng) * 0.3
        }
    }

    /// A synthetic chord progression with plucked envelopes. Music-like in the
    /// ways that trouble an energy detector (harmonic, sustained, rhythmic);
    /// not music anyone composed.
    static func tonalBed(count: Int) -> [Float] {
        let chords: [[Double]] = [[220, 277.2, 329.6], [196, 246.9, 293.7], [174.6, 220, 261.6], [196, 246.9, 311.1]]
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            let chord = chords[Int(t / 2) % chords.count]
            let envelope = exp(-3 * t.truncatingRemainder(dividingBy: 0.5))
            var v = 0.0
            for f in chord { for h in 1...3 { v += sin(2 * .pi * f * Double(h) * t) / Double(h) } }
            return Float(v * envelope)
        }
    }

    /// Fourth-order 300–3400 Hz band-pass (two RBJ high-pass and two low-pass biquads).
    static func bandLimit(_ x: [Float]) -> [Float] {
        var y = x
        for _ in 0..<2 {
            y = biquad(y, highPass: true, frequency: 300)
            y = biquad(y, highPass: false, frequency: 3_400)
        }
        return y
    }

    static func biquad(_ x: [Float], highPass: Bool, frequency: Double) -> [Float] {
        let w = 2 * Double.pi * frequency / sampleRate, q = 0.7071
        let alpha = sin(w) / (2 * q), c = cos(w)
        let b0 = highPass ? (1 + c) / 2 : (1 - c) / 2
        let b1 = highPass ? -(1 + c) : 1 - c
        let a0 = 1 + alpha, a1 = -2 * c, a2 = 1 - alpha
        var (x1, x2, y1, y2) = (0.0, 0.0, 0.0, 0.0)
        return x.map { sample in
            let s = Double(sample)
            let out = (b0 * s + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2) / a0
            x2 = x1; x1 = s; y2 = y1; y1 = out
            return Float(out)
        }
    }
}

enum LabError: Error, CustomStringConvertible {
    case render(String), usage(String)
    var description: String {
        switch self { case let .render(m), let .usage(m): m }
    }
}

/// Deterministic randomness so a fixture renders to the same samples every time.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension String {
    /// FNV-1a, because `hashValue` is seeded per process and fixtures must
    /// render identically across runs.
    var hashValue32: Int {
        var h: UInt32 = 2_166_136_261
        for byte in utf8 { h = (h ^ UInt32(byte)) &* 16_777_619 }
        return Int(h)
    }
}
