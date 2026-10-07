//
//  Corpus.swift
//  diarization-lab
//
//  The evaluation corpus, defined as data. Audio is rendered on demand from
//  these definitions with the macOS `say` voices and never committed: the
//  definitions are the project-owned artefact, the audio is reproducible.
//

import Foundation

struct TurnSpec {
    let speaker: String
    let voice: String
    let text: String
    var gainDecibels: Double = 0
    var pauseBefore: Double = 0.6
    /// Seconds this turn starts *before* the previous one ends.
    var overlap: Double = 0
}

struct FixtureSpec {
    enum Split: String { case dev, test }
    let name: String
    let split: Split
    let summary: String
    let turns: [TurnSpec]
    var noiseSNR: Double?
    var tonalBackground = false
    var narrowband = false
}

/// Sentences written for this corpus. Meeting-like, varied in length.
let sentences = [
    "We need to finish the release validation before anything else this week.",
    "I can take the documentation pass if nobody else has started it.",
    "The build on the older machine failed twice yesterday afternoon.",
    "Let's look at the crash report first and decide after that.",
    "I think the problem is in how the recording closes when we stop.",
    "Can someone confirm whether the preview still shows the last sentence?",
    "The search results looked right to me, but the ordering felt odd.",
    "We should write down the steps so the next person can repeat them.",
    "My concern is the battery cost during a three hour meeting.",
    "That number came from the profiler, not from an estimate.",
    "I'd rather ship a smaller feature that we can actually defend.",
    "The microphone picker remembered the wrong device after a restart.",
    "Please send me the session folder and I will check the timestamps.",
    "There is a gap marker in the middle of the second transcript.",
    "I agree, but we still need a plan for the accessibility review.",
    "The design looks clean in dark mode and slightly cramped in light mode.",
    "We can revisit the window size once the layout settles down.",
    "Nobody has tested the recovery path on a fresh account yet.",
    "Let me share my screen so everyone can see the same thing.",
    "The second option costs more memory but finishes much faster.",
    "I measured it three times and the results were consistent.",
    "Could we move the review section above the transcript preview?",
    "That would change the keyboard order, so let's be careful.",
    "The release notes should say exactly what was validated.",
    "I'll follow up with the test results by the end of the day.",
    "We have about ten minutes left, so let's pick the next item.",
    "The export worked, but the file name included the wrong date.",
    "Honestly I don't remember why we chose that threshold.",
    "It was tuned on synthetic speech, which is the part that worries me.",
    "Let's write that limitation into the documentation today.",
]

let interjections = ["Yes.", "Okay.", "Right.", "Sure.", "Mm hmm.", "Exactly.", "No.", "Got it."]

/// Voices used for tuning thresholds. None appears in the test split.
enum DevVoices {
    static let a = "Daniel", b = "Karen", c = "Rishi", d = "Moira"
    static let similarA = "Flo (English (US))", similarB = "Flo (English (UK))"
}

/// Voices used only for evaluation.
enum TestVoices {
    static let a = "Samantha", b = "Reed (English (US))", c = "Tessa", d = "Aman", e = "Sandy (English (US))", f = "Grandpa (English (US))"
    static let similarA = "Eddy (English (US))", similarB = "Eddy (English (UK))"
}

private func alternating(_ voices: [(String, String)], count: Int, offset: Int = 0) -> [TurnSpec] {
    (0..<count).map { i in
        let (speaker, voice) = voices[i % voices.count]
        return TurnSpec(speaker: speaker, voice: voice, text: sentences[(i + offset) % sentences.count])
    }
}

func corpus() -> [FixtureSpec] {
    var fixtures = [FixtureSpec]()

    // Development split: tuning only.
    let devTwo = [("A", DevVoices.a), ("B", DevVoices.b)]
    let devThree = [("A", DevVoices.a), ("B", DevVoices.b), ("C", DevVoices.c)]
    fixtures.append(FixtureSpec(name: "dev-one-speaker", split: .dev, summary: "One speaker, eight turns", turns: alternating([("A", DevVoices.d)], count: 8, offset: 3)))
    fixtures.append(FixtureSpec(name: "dev-two-alternating", split: .dev, summary: "Two speakers alternating", turns: alternating(devTwo, count: 12, offset: 5)))
    fixtures.append(FixtureSpec(name: "dev-three-speakers", split: .dev, summary: "Three speakers round robin", turns: alternating(devThree, count: 12, offset: 9)))
    fixtures.append(FixtureSpec(name: "dev-four-speakers", split: .dev, summary: "Four speakers", turns: alternating(devThree + [("D", DevVoices.d)], count: 16, offset: 2)))
    fixtures.append(FixtureSpec(name: "dev-similar-voices", split: .dev, summary: "Same voice persona, two accents", turns: alternating([("A", DevVoices.similarA), ("B", DevVoices.similarB)], count: 10, offset: 11)))
    var devNoise = FixtureSpec(name: "dev-noise", split: .dev, summary: "Two speakers, noise at 10 dB SNR", turns: alternating(devTwo, count: 10, offset: 14))
    devNoise.noiseSNR = 10
    fixtures.append(devNoise)

    // Test split: never used for tuning.
    let two = [("A", TestVoices.a), ("B", TestVoices.b)]
    fixtures.append(FixtureSpec(name: "one-speaker", split: .test, summary: "One speaker, eight turns", turns: alternating([("A", TestVoices.a)], count: 8)))
    fixtures.append(FixtureSpec(name: "two-alternating", split: .test, summary: "Two speakers alternating, equal level", turns: alternating(two, count: 12, offset: 1)))
    fixtures.append(FixtureSpec(name: "three-speakers", split: .test, summary: "Three speakers round robin", turns: alternating([("A", TestVoices.c), ("B", TestVoices.d), ("C", TestVoices.e)], count: 12, offset: 4)))

    let separated: [TurnSpec] = [
        TurnSpec(speaker: "A", voice: TestVoices.a, text: sentences[0]),
        TurnSpec(speaker: "A", voice: TestVoices.a, text: sentences[1]),
        TurnSpec(speaker: "B", voice: TestVoices.f, text: sentences[2]),
        TurnSpec(speaker: "B", voice: TestVoices.f, text: sentences[3]),
        TurnSpec(speaker: "C", voice: TestVoices.c, text: sentences[4]),
        TurnSpec(speaker: "C", voice: TestVoices.c, text: sentences[5]),
        TurnSpec(speaker: "B", voice: TestVoices.f, text: sentences[6]),
        TurnSpec(speaker: "C", voice: TestVoices.c, text: sentences[7]),
        TurnSpec(speaker: "A", voice: TestVoices.a, text: sentences[8]),
        TurnSpec(speaker: "A", voice: TestVoices.a, text: sentences[9]),
    ]
    fixtures.append(FixtureSpec(name: "same-speaker-returns", split: .test, summary: "A speaks first and returns after a long absence", turns: separated))

    fixtures.append(FixtureSpec(name: "long-silences", split: .test, summary: "Two speakers with 4–8 s silences", turns: alternating(two, count: 8, offset: 12).enumerated().map { i, t in
        var turn = t; turn.pauseBefore = [4.0, 6.5, 8.0, 5.0][i % 4]; return turn
    }))

    var noise = FixtureSpec(name: "background-noise", split: .test, summary: "Two speakers, broadband noise at 10 dB SNR", turns: alternating(two, count: 10, offset: 16))
    noise.noiseSNR = 10
    fixtures.append(noise)

    var music = FixtureSpec(name: "tonal-background", split: .test, summary: "Two speakers over a synthetic tonal (music-like) bed at −12 dB", turns: alternating(two, count: 10, offset: 18))
    music.tonalBackground = true
    fixtures.append(music)

    var interjecting = [TurnSpec]()
    for i in 0..<8 {
        interjecting.append(TurnSpec(speaker: "A", voice: TestVoices.a, text: sentences[(i * 2 + 3) % sentences.count] + " " + sentences[(i * 2 + 4) % sentences.count]))
        interjecting.append(TurnSpec(speaker: "B", voice: TestVoices.b, text: interjections[i], pauseBefore: 0.4))
    }
    fixtures.append(FixtureSpec(name: "short-interjections", split: .test, summary: "Long turns from A, one-word replies from B", turns: interjecting))

    fixtures.append(FixtureSpec(name: "unequal-volume", split: .test, summary: "Two speakers, B 18 dB quieter", turns: alternating(two, count: 12, offset: 7).map { t in
        var turn = t; if t.speaker == "B" { turn.gainDecibels = -18 }; return turn
    }))

    fixtures.append(FixtureSpec(name: "distance-change", split: .test, summary: "One speaker whose level drops 14 dB halfway, as if stepping back", turns: alternating([("A", TestVoices.d)], count: 10, offset: 20).enumerated().map { i, t in
        var turn = t; if i >= 5 { turn.gainDecibels = -14 }; return turn
    }))

    fixtures.append(FixtureSpec(name: "similar-voices", split: .test, summary: "Same voice persona in two accents (Eddy US / Eddy UK)", turns: alternating([("A", TestVoices.similarA), ("B", TestVoices.similarB)], count: 10, offset: 22)))

    var narrow = FixtureSpec(name: "narrowband", split: .test, summary: "Two speakers band-limited to 300–3400 Hz (headset/telephone-like)", turns: alternating(two, count: 10, offset: 24))
    narrow.narrowband = true
    fixtures.append(narrow)

    fixtures.append(FixtureSpec(name: "overlap", split: .test, summary: "Two speakers, every turn overlaps the previous by 1 s", turns: alternating(two, count: 10, offset: 26).enumerated().map { i, t in
        var turn = t; if i > 0 { turn.overlap = 1.0; turn.pauseBefore = 0 }; return turn
    }))

    fixtures.append(FixtureSpec(name: "rapid-turns", split: .test, summary: "Two speakers with 0.1 s between turns", turns: alternating(two, count: 12, offset: 13).map { t in
        var turn = t; turn.pauseBefore = 0.1; return turn
    }))

    fixtures.append(FixtureSpec(name: "six-speakers", split: .test, summary: "Six speakers, two turns each", turns: alternating([("A", TestVoices.a), ("B", TestVoices.b), ("C", TestVoices.c), ("D", TestVoices.d), ("E", TestVoices.e), ("F", TestVoices.f)], count: 12, offset: 6)))

    return fixtures
}
