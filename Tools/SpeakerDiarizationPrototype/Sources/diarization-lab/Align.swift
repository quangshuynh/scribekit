//
//  Align.swift
//  diarization-lab
//
//  Does a finalised SpeechTranscriber result — the unit ScribeKit writes as one
//  passage — ever contain words from two speakers? If it does, a per-passage
//  speaker label is wrong by construction, however good the diarizer is.
//
//  Attribution is by text, not by time: the recognised words are aligned to
//  the known script with a word-level edit distance, so each recognised word
//  is traced to the turn it came from regardless of how the recogniser
//  timestamped it. Timing accuracy is then measured separately.
//

import AVFAudio
import CoreMedia
import DiarizationCore
import Foundation
import Speech

struct AlignmentRow: Codable {
    let fixture: String
    let finals: Int
    let mixedFinals: Int
    let wordsInMixedFinals: Int
    let alignedWords: Int
    /// Recogniser start of a turn's first word minus where that turn's audio begins.
    let turnStartErrors: [Double]
    /// Recogniser end of a turn's last word minus where that turn's audio ends.
    let turnEndErrors: [Double]
    /// Final ranges that begin before the speech they contain (absorbing silence).
    let finalsStartingInSilence: Int
}

enum Alignment {

    struct Word {
        let text: String
        let range: TimeRange?
    }

    struct Final {
        let range: TimeRange
        let words: [Word]
    }

    static func finals(for url: URL, locale: Locale = Locale(identifier: "en-US")) async throws -> [Final] {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task {
            var finals = [Final]()
            for try await result in transcriber.results where result.isFinal {
                let words = result.text.runs.map { run in
                    Word(
                        text: String(result.text[run.range].characters),
                        range: run.audioTimeRange.map { TimeRange(start: $0.start.seconds, end: $0.end.seconds) }
                    )
                }
                finals.append(Final(range: TimeRange(start: result.range.start.seconds, end: result.range.end.seconds), words: words))
            }
            return finals
        }
        let file = try AVAudioFile(forReading: url)
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        return try await collector.value
    }

    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
    }

    static func analyse(fixture: RenderedFixture, script: [TurnSpec], finals: [Final]) -> AlignmentRow {
        // Reference word stream, each word tagged with its turn.
        var reference = [(word: String, turn: Int)]()
        for (i, turn) in script.enumerated() { for w in tokens(turn.text) { reference.append((w, i)) } }
        // Hypothesis word stream, each token tagged with its final and run.
        var hypothesis = [(word: String, final: Int, range: TimeRange?)]()
        for (f, final) in finals.enumerated() {
            for run in final.words { for w in tokens(run.text) { hypothesis.append((w, f, run.range)) } }
        }
        let pairs = align(reference.map(\.word), hypothesis.map(\.word))

        var turnsPerFinal = Array(repeating: Set<String>(), count: finals.count)
        var wordsPerFinal = Array(repeating: 0, count: finals.count)
        var firstWord = [Int: TimeRange](), lastWord = [Int: TimeRange]()
        var firstTurnOfFinal = [Int: Int]()
        var aligned = 0
        for (r, h) in pairs {
            guard let r, let h else { continue }
            aligned += 1
            let turn = reference[r].turn, final = hypothesis[h].final
            turnsPerFinal[final].insert(script[turn].speaker)
            wordsPerFinal[final] += 1
            if firstTurnOfFinal[final] == nil { firstTurnOfFinal[final] = turn }
            if let range = hypothesis[h].range {
                if firstWord[turn] == nil { firstWord[turn] = range }
                lastWord[turn] = range
            }
        }
        let mixed = turnsPerFinal.indices.filter { turnsPerFinal[$0].count > 1 }
        var startErrors = [Double](), endErrors = [Double]()
        for (i, turn) in fixture.turns.enumerated() {
            if let w = firstWord[i] { startErrors.append(w.start - turn.start) }
            if let w = lastWord[i] { endErrors.append(w.end - turn.end) }
        }
        let silenceStarts = firstTurnOfFinal.filter { final, turn in
            fixture.turns[turn].start - finals[final].range.start > 0.3
        }.count
        return AlignmentRow(
            fixture: fixture.name, finals: finals.count, mixedFinals: mixed.count,
            wordsInMixedFinals: mixed.reduce(0) { $0 + wordsPerFinal[$1] }, alignedWords: aligned,
            turnStartErrors: startErrors, turnEndErrors: endErrors, finalsStartingInSilence: silenceStarts
        )
    }

    /// Word-level Levenshtein alignment. Returns matched or substituted pairs
    /// as (reference index, hypothesis index); insertions and deletions carry
    /// a nil on one side.
    static func align(_ a: [String], _ b: [String]) -> [(Int?, Int?)] {
        let n = a.count, m = b.count
        var cost = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { cost[i][0] = i }
        for j in 0...m { cost[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n { for j in 1...m {
                cost[i][j] = min(cost[i - 1][j] + 1, cost[i][j - 1] + 1, cost[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            } }
        }
        var pairs = [(Int?, Int?)]()
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, cost[i][j] == cost[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1) {
                pairs.append((i - 1, j - 1)); i -= 1; j -= 1
            } else if i > 0, cost[i][j] == cost[i - 1][j] + 1 {
                pairs.append((i - 1, nil)); i -= 1
            } else {
                pairs.append((nil, j - 1)); j -= 1
            }
        }
        return pairs.reversed()
    }
}
