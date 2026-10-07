//
//  Bench.swift
//  diarization-lab
//

import Darwin
import DiarizationCore
import Foundation

struct Measurement: Codable {
    let phase: String
    let wallSeconds: Double
    let cpuSeconds: Double
    let peakFootprintMB: Double
    let note: String
}

/// Samples this process's physical footprint while a phase runs, so the
/// report states peaks rather than averages.
final class FootprintSampler: @unchecked Sendable {
    private var peak: UInt64 = 0
    private var running = true
    private let lock = NSLock()
    private var thread: Thread?

    static func current() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }

    func start() {
        peak = Self.current()
        let t = Thread { [self] in
            while lock.withLock({ running }) {
                let now = Self.current()
                lock.withLock { peak = max(peak, now) }
                usleep(20_000)
            }
        }
        thread = t
        t.start()
    }

    func stop() -> Double {
        lock.withLock { running = false }
        return Double(lock.withLock { max(peak, Self.current()) }) / 1_048_576
    }
}

func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
}

func measure(_ phase: String, note: String = "", _ body: () async throws -> Void) async rethrows -> Measurement {
    let sampler = FootprintSampler()
    sampler.start()
    let cpu0 = cpuSeconds(), wall0 = Date()
    try await body()
    let wall = Date().timeIntervalSince(wall0), cpu = cpuSeconds() - cpu0
    return Measurement(phase: phase, wallSeconds: wall, cpuSeconds: cpu, peakFootprintMB: sampler.stop(), note: note)
}

enum Bench {

    static func run(directory: URL, fixtures: [(RenderedFixture, [Float])]) async throws -> [Measurement] {
        var accumulated = [Float]()
        let tests = fixtures.filter { $0.0.split == "test" }
        while Double(accumulated.count) / Renderer.sampleRate < 600 {
            for (_, samples) in tests { accumulated += samples }
        }
        let long = Array(accumulated.prefix(Int(600 * Renderer.sampleRate)))
        let url = directory.appendingPathComponent("bench-10min.wav")
        try Renderer.write(long, to: url)
        let rate = Renderer.sampleRate
        var results = [Measurement]()

        results.append(await measure("baseline footprint", note: "process idle with 10 min of audio in memory") {})

        results.append(try await measure("AudioFeaturePrint cold start", note: "first call on 2 s of audio, includes model load") {
            _ = try await AppleAudioFeaturePrintEmbedding().embed(samples: Array(long.prefix(32_000)), sampleRate: rate, windows: [TimeRange(start: 0, end: 1.5)])
        })

        var regions = [TimeRange]()
        results.append(await measure("energy activity, 10 min") { regions = EnergySpeechActivity().regions(in: long, sampleRate: rate) })
        let windows = AnalysisWindowing().windows(for: regions)

        var mfcc = [[Float]]()
        results.append(try await measure("MFCC-stats embedding, 10 min", note: "\(windows.count) windows") {
            mfcc = try await MFCCStatisticsEmbedding().embed(samples: long, sampleRate: rate, windows: windows)
        })
        results.append(try await measure("AudioFeaturePrint embedding, 10 min", note: "\(windows.count) windows, warm") {
            _ = try await AppleAudioFeaturePrintEmbedding().embed(samples: long, sampleRate: rate, windows: windows)
        })
        results.append(await measure("post-meeting clustering, 10 min", note: "agglomerative, \(windows.count) windows") {
            _ = Clustering.assign(embeddings: mfcc, windows: windows, configuration: ClusteringConfiguration(mode: .postMeeting, threshold: 0.6, margin: 0.1))
        })
        results.append(await measure("live clustering, 10 min", note: "leader, \(windows.count) windows") {
            _ = Clustering.assign(embeddings: mfcc, windows: windows, configuration: ClusteringConfiguration(mode: .live, threshold: 0.6, margin: 0.1))
        })

        for n in [400, 800, 1_600] {
            var rng = SeededGenerator(seed: UInt64(n))
            let vectors = (0..<n).map { _ in (0..<38).map { _ in Float.random(in: -1...1, using: &rng) } }
            let w = (0..<n).map { TimeRange(start: Double($0) * 0.75, end: Double($0) * 0.75 + 1.5) }
            results.append(await measure("agglomerative worst case, n=\(n)", note: String(format: "every window merged; ≈ %.0f min of continuous speech; distance matrix %.0f MB", Double(n) * 0.75 / 60, Double(n * n * 4) / 1_048_576)) {
                _ = Clustering.assign(embeddings: vectors, windows: w, configuration: ClusteringConfiguration(mode: .postMeeting, threshold: 2.1, margin: 0.1))
            })
        }

        results.append(try await measure("transcription alone, 10 min", note: "SpeechTranscriber from file; this process's CPU only — the model's own inference is not attributed to it (standalone: 0.93 s CPU, 8 MB peak)") {
            _ = try await Alignment.finals(for: url)
        })
        results.append(try await measure("transcription + live diarization concurrently, 10 min", note: "MFCC-stats + leader in a parallel task") {
            async let transcript = Alignment.finals(for: url)
            async let diarization: Void = {
                let r = EnergySpeechActivity().regions(in: long, sampleRate: rate)
                let w = AnalysisWindowing().windows(for: r)
                let v = try await MFCCStatisticsEmbedding().embed(samples: long, sampleRate: rate, windows: w)
                _ = Clustering.assign(embeddings: v, windows: w, configuration: ClusteringConfiguration(mode: .live, threshold: 0.6, margin: 0.1))
            }()
            _ = try await (transcript, diarization)
        })
        return results
    }
}
