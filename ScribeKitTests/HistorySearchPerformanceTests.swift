//
//  HistorySearchPerformanceTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// A deterministic collection of synthetic meetings, generated the same way
/// on every run.
///
/// Sized from ScribeKit's own history: Interval 10 measured search over 50,
/// 200 and 500 one-hour meetings of 240 spans each, and this corpus has the
/// same shape so the numbers can be compared. Words are drawn from a fixed
/// vocabulary by a fixed-seed generator, so span lengths and word frequencies
/// look like speech rather than like one sentence repeated, and the same
/// seed always produces the same bytes.
private nonisolated enum SyntheticCorpus {

    private static let vocabulary = """
        the a we should think about this that release deployment schedule review team customer meeting \
        next week today tomorrow already maybe probably really just going to need have been will can \
        could would want make sure check with them us you I it is was are were be on in at for from \
        with about into over after before during budget roadmap design build test ship feature bug fix \
        server client database query index cache latency memory battery audio microphone transcript \
        question answer point idea plan problem issue risk estimate timeline quarter launch demo
        """.split(separator: " ").map(String.init)

    /// A small linear congruential generator: deterministic, and more than
    /// random enough to vary sentence shape.
    private struct Generator {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    /// One meeting's spans.
    ///
    /// - Parameters:
    ///   - meeting: Which meeting, which seeds its words.
    ///   - spanCount: How many spans it has.
    /// - Returns: The spans, as the parser would produce them.
    static func spans(meeting: Int, spanCount: Int) -> [TranscriptSpan] {
        var generator = Generator(state: UInt64(meeting) &* 2_654_435_761 &+ 97)
        return (0..<spanCount).map { index in
            var words = (0..<(18 + generator.next(14))).map { _ in vocabulary[generator.next(vocabulary.count)] }
            words[0] = words[0].capitalized
            if meeting == 137, index == spanCount / 2 { words += ["the", "zephyr", "migration", "checklist"] }
            let seconds = index * 15
            let clock = String(format: "%d:%02d:%02d AM", 9 + seconds / 3_600, (seconds / 60) % 60, seconds % 60)
            return TranscriptSpan(
                index: index,
                clock: clock,
                heading: String(clock.prefix(clock.count - 6)) + " AM",
                text: words.joined(separator: " ") + "."
            )
        }
    }

    /// A collection of meetings, alternating App Audio and Microphone.
    ///
    /// - Parameters:
    ///   - meetings: How many meetings.
    ///   - spansPerMeeting: How many spans each has.
    /// - Returns: The documents History would hold after a load.
    static func documents(meetings: Int, spansPerMeeting: Int) -> [TranscriptSearchDocument] {
        let root = URL(filePath: "/Users/example/Meetings", directoryHint: .isDirectory)
        return (0..<meetings).map { meeting in
            let directory = root.appending(path: String(format: "meeting-%04d", meeting), directoryHint: .isDirectory)
            let mode: CaptureMode = meeting.isMultiple(of: 2) ? .applications : .microphone
            let spans = spans(meeting: meeting, spanCount: spansPerMeeting)
            let started = TranscriptFixture.startedAt.addingTimeInterval(Double(meeting) * 86_400)
            let session = HistorySession(
                directory: directory,
                sessionID: UUID(),
                title: "Weekly Sync \(meeting)",
                status: .completed,
                startedAt: started,
                endedAt: started.addingTimeInterval(3_600),
                sourceNames: [mode == .microphone ? "Microphone (MacBook Air Microphone)" : "Zoom"],
                localeIdentifier: "en-US",
                transcriptURL: SessionArtifactLayout(directory: directory).transcriptURL,
                transcript: SessionFileInfo(byteCount: spans.reduce(0) { $0 + $1.text.utf8.count }, modifiedAt: started),
                audioRetention: AudioRetentionMode.none,
                audio: nil,
                captureMode: mode
            )
            return TranscriptSearchDocument(session: session, spans: spans)
        }
    }
}

/// History search and transcript find, timed over a realistic collection.
///
/// The budget was set before anything was measured, from the threshold
/// Interval 10 already recorded as the point at which an on-disk index would
/// be justified: a keystroke's search completes within 100 ms in an optimised
/// build over 200 one-hour meetings, and finding within one three-hour
/// transcript completes within one 60 Hz frame, 16 ms. Timing is asserted
/// only in an optimised build; a debug build — the one CI runs — is several
/// times slower by construction, so there only a loose guard catches a
/// pathological regression, and the numbers are printed for the record.
@Suite("History search performance", .serialized)
struct HistorySearchPerformanceTests {

    /// The keystroke budget over 200 meetings, optimised build.
    private static let searchBudget = Duration.milliseconds(100)

    /// The find budget over one three-hour transcript, optimised build.
    private static let findBudget = Duration.milliseconds(16)

    /// What a debug build must still manage, to catch something gone badly
    /// wrong without turning the suite into a benchmark.
    private static let debugGuard = Duration.seconds(1)

    /// The slowest of several runs of `body`, after one warm-up run.
    private func slowest(of runs: Int = 5, _ body: () -> Void) -> Duration {
        body()
        return (0..<runs).map { _ in ContinuousClock().measure(body) }.max() ?? .zero
    }

    /// Whether the tests were built with optimisation.
    private var isOptimised: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    private func milliseconds(_ duration: Duration) -> String {
        String(format: "%.2f", Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1e3)
    }

    @Test("A keystroke's search over 200 one-hour meetings, with and without a filter")
    func searchTwoHundredMeetings() {
        let documents = SyntheticCorpus.documents(meetings: 200, spansPerMeeting: 240)
        let bytes = documents.reduce(0) { $0 + $1.session.transcript.byteCount }
        let indexing = ContinuousClock().measure { _ = TranscriptSearchIndex(documents) }
        let index = TranscriptSearchIndex(documents)

        let cases: [(label: String, query: String, filter: HistoryCaptureFilter, expected: Int?)] = [
            ("phrase in one meeting", "zephyr migration", .all, 1),
            ("phrase in one meeting, Microphone", "zephyr migration", .microphone, 1),
            ("common word", "deployment", .all, nil),
            ("common word, App Audio", "deployment", .applications, nil),
            ("title fragment", "sync 19", .all, nil),
            ("no match", "xylophone", .all, 0),
            ("no query, Microphone", "", .microphone, 100)
        ]

        var worst = Duration.zero
        for testCase in cases {
            let results = TranscriptSearch.results(for: testCase.query, in: index, filter: testCase.filter)
            if let expected = testCase.expected { #expect(results.count == expected, "\(testCase.label)") }
            let duration = slowest { _ = TranscriptSearch.results(for: testCase.query, in: index, filter: testCase.filter) }
            worst = max(worst, duration)
            print("PERF search [\(isOptimised ? "optimised" : "debug")] \(testCase.label): \(milliseconds(duration)) ms")
        }
        print("PERF corpus: 200 meetings, \(documents.reduce(0) { $0 + $1.spans.count }) spans, \(bytes) bytes; "
              + "index built in \(milliseconds(indexing)) ms")

        #expect(worst < (isOptimised ? Self.searchBudget : Self.debugGuard))
    }

    @Test("Finding and stepping within one three-hour transcript")
    func findInThreeHourTranscript() throws {
        let documents = SyntheticCorpus.documents(meetings: 1, spansPerMeeting: 720)
        let index = TranscriptSearchIndex(documents)
        let id = try #require(documents.first?.id)

        var matchCount = 0
        let duration = slowest {
            var find = TranscriptFind(query: "deployment", matches: index.occurrences(of: "deployment", inDocument: id))
            find.next()
            find.previous()
            matchCount = find.matches.count
        }
        #expect(matchCount > 10)
        print("PERF find [\(isOptimised ? "optimised" : "debug")] 720 spans, \(matchCount) matches: "
              + "\(milliseconds(duration)) ms")
        #expect(duration < (isOptimised ? Self.findBudget : Self.debugGuard))
    }
}
