# Speaker diarization prototype

Developer tooling for evaluating speaker diarization approaches against a
synthetic corpus with measured ground truth. It is not part of the shipping
application: ScribeKit does not link it, and the package has no dependencies
beyond frameworks that ship with macOS.

The findings, the methodology and the decision they support are recorded in
[`docs/development/speaker-diarization.md`](../../docs/development/speaker-diarization.md).
This file only says how to run the harness.

## Running

```
swift test                                  # scoring and clustering semantics
swift run -c release diarization-lab all    # render, evaluate, align, bench
```

Single steps: `render`, `evaluate`, `align`, `bench`. `align` and `bench` need
the en-US `SpeechTranscriber` model installed.

## Layout

- `Sources/DiarizationCore/`: MFCC features (Accelerate), energy activity
  detection, analysis windows, the two Apple-native embeddings, post-meeting
  and live clustering with abstention, and the scoring (DER with md-eval
  semantics, change detection, splits and merges).
- `Sources/diarization-lab/`: the corpus definition, the renderer (`say`
  voices, measured ground truth), the evaluation with dev-only tuning, the
  transcript-alignment study, and the performance bench.
- `results/`: generated reports from the last run. Regenerate them rather
  than editing them.
- `.fixtures/`: rendered audio, about 135 MB, ignored by Git. Fixtures are
  reproducible from `Corpus.swift` and are never committed.

## Adding a candidate

Implement `WindowEmbedding` and add it to `Evaluator.embeddings`. Thresholds
are chosen on the dev split only, so a candidate is compared on the test
split under the same rules. A candidate that needs a third-party model is
evaluated here, outside the application, before anything is proposed for it.
Embeddings stay in memory for one run and are never written out.
