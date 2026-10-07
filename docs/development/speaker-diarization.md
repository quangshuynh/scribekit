# Speaker Diarization Research

ScribeKit does not label who spoke. This page records why. It covers what
Apple's frameworks offer, what an Apple-native prototype measured, and what
any future attempt would have to satisfy. The harness that produced the numbers
is committed under `Tools/SpeakerDiarizationPrototype/`. It is developer tooling
and is not part of the application.

!!! note "Decision: not integrated"
    No approach available without a third-party dependency distinguished
    speakers accurately enough to put a label in front of a reader. The
    prototype is kept as an evaluation harness. Nothing in the application,
    the transcript format or the session artifacts changed.

## Three different things

| Term | Question it answers | Status in ScribeKit |
| --- | --- | --- |
| **Speaker diarization** | Which stretches of this one recording were spoken by the same voice? | Not available. Investigated here. |
| **Speaker identification** | Who is this person? | Out of scope. ScribeKit does not build voice profiles. |
| **Source attribution** | Which capture source did this audio come from? | Implicit. A meeting has one capture mode, and its sources are already in the transcript's `**Sources:**` header. |

Diarization labels are anonymous clusters within one meeting. "Speaker 1" in one
meeting has no relation to "Speaker 1" in another. Speech recognition, which
ScribeKit does, is none of these three.

## What Apple provides

Checked against the macOS 27.0 SDK's Swift interfaces and headers (Xcode 27.0)
and at run time on macOS 26.6. ScribeKit's deployment target is 26.5.

- **Speech.** The analyzer modules are `SpeechTranscriber`,
  `DictationTranscriber` and `SpeechDetector`. None of them reports speakers. A
  `SpeechTranscriber.Result` carries `range`, `resultsFinalizationTime`, `text`
  and `alternatives`. The only attributes on the text are
  `transcriptionConfidence` and `audioTimeRange`. `SpeechDetector.Result` says
  only whether speech was detected in a range. The 27.0 additions
  (`AnalyzerInputConverter`, `AssetInputSequenceProvider`,
  `CaptureInputSequenceProvider` and `ignoresResourceLimits`) add nothing about
  speakers. `SFVoiceAnalytics` (jitter, shimmer, pitch and voicing) belongs to
  `SFSpeechRecognizer`, which ScribeKit does not use because it has a
  server-backed path. Those values describe one voice's quality, and they do
  not separate voices.
- **SoundAnalysis.** The built-in classifier (`SNClassifierIdentifier.version1`)
  knows 303 labels. Its vocal labels name kinds of vocal sound, such as
  `speech`, `whispering`, `shout`, `laughter`, `singing`, `chatter` and
  `babble`. None tells one talker from another.
- **AVFAudio.** Voice-processing I/O offers
  `setMutedSpeechActivityEventListener`, which detects speech **while the input
  is muted**. That is the "you are muted" event, not speaker change.
- **ScreenCaptureKit.** A stream delivers **one mixed** `.audio` output for its
  content filter, plus an optional `.microphone` output (macOS 15). ScribeKit
  captures every selected application through one
  `SCContentFilter(display:including:exceptingWindows:)`, so the buffers carry
  no per-application identity. Attributing audio to one application would need
  one stream per application, which changes the one-stream capture model.
- **Core ML.** Core ML is a runtime. The system ships no speaker-embedding or
  diarization model.
- **CreateMLComponents.** `AudioFeaturePrint` is an on-device, system-provided
  audio embedding. It is the feature extractor behind Create ML's sound
  classifier, trained to tell kinds of sound apart. It is the closest thing to
  an embedding model on the platform, so the prototype tested it.

Apple's developer forums show the same gap. Developers asked about native
diarization after both the 26 and 27 announcements, and Apple has announced none.

## The prototype

Everything runs offline with system frameworks only. It reads fixtures, writes
reports and keeps embeddings in memory for the length of one run.

1. **Activity**: an adaptive energy detector. It can also be replaced by the
   reference speech regions ("oracle activity") so that clustering is measured
   separately from detection.
2. **Windows**: 1.5 s, 0.75 s hop, never crossing a silence. A region shorter
   than a window is one shorter window.
3. **Embeddings**, both Apple-native:
    - *MFCC statistics*: mean and standard deviation of 19 cepstra, computed
      with Accelerate. This is the classic hand-engineered speaker feature.
    - *AudioFeaturePrint*: Apple's sound embedding, averaged over the window.
4. **Clustering**, in two modes:
    - *Post-meeting*: average-linkage agglomerative clustering over the whole
      recording, stopped at a cosine-distance threshold.
    - *Live*: causal leader clustering. Each window is assigned on arrival and
      never revised, the only behaviour compatible with writing as a meeting
      runs.
5. **Uncertainty**: a window is attributed with confidence only when its
   distance to its own cluster beats the nearest alternative by a margin, and
   its cluster has at least 2 s of evidence. A window that opens a new live
   cluster is never confident. Anything else is reported as uncertain, not as a
   guess.

### Corpus and ground truth

The corpus is synthetic and defined as data in `Corpus.swift`. Thirty sentences
were written for it, and macOS `say` voices render them at 16 kHz. Audio is
rendered on demand and **never committed**. Ground truth is measured from the
placed audio, not declared. Each utterance is rendered alone and trimmed to its
own signal, and each reference turn is exactly where those samples went.

- **Development split** (6 fixtures, used only to choose thresholds): one
  speaker, two alternating, three, four, a similar-voice pair (Flo US/UK) and
  noise. Its voices never appear in the test split.
- **Test split** (15 fixtures): one speaker; two alternating at equal level;
  three speakers; a speaker returning after a long absence; 4–8 s silences;
  broadband noise at 10 dB SNR; a synthetic tonal (music-like) bed; one-word
  interjections (0.34 s and up); one speaker 18 dB quieter; one speaker whose
  level drops 14 dB, as if stepping back; a similar-voice pair (Eddy US/UK);
  300–3400 Hz band-limiting; 1 s overlaps; 0.1 s turn gaps; and six speakers.

Synthetic voices are an **easy** case. Each voice is perfectly consistent with
itself and different voices come from different synthesis models. Real people
vary more within themselves and less between each other, and they share a room
and a microphone. The results below are therefore an upper bound on what these
methods would do in a real meeting.

### Metrics

Scoring is on a 10 ms grid with a 0.25 s collar either side of each reference
boundary, following NIST md-eval:

- **DER** (diarization error rate) is missed speech plus false alarm plus
  speaker confusion, over reference speech time. Clusters are mapped to speakers
  one-to-one by the Hungarian algorithm. Overlapping speech is scored, so a
  single-label system misses the second speaker.
- **Unattributed** is reference speech with no confident label.
- **Confident error** is the share of confidently labelled time that carries
  the wrong speaker. This is the number that matters for a label a reader will
  believe.
- **Splits and merges** count speakers spread over several clusters and
  clusters holding several speakers (each at 10 % or more of the time).
- **Change detection** counts reference speaker changes found within ±0.5 s,
  missed changes, false changes and the mean boundary error.
- **Separability** is the equal error rate of a same/different-speaker decision
  over all pairs of single-speaker windows in a recording. It is
  threshold-free, measures the embedding alone, and 50 % is chance.

## Results

Test split, thresholds and margins chosen on the development split:

| Embedding | Mode | Activity | DER | Confusion | Unattributed | Confident error |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| MFCC statistics | post-meeting | oracle | 25.4 % | 24.5 % | 11.2 % | 22.3 % |
| MFCC statistics | post-meeting | system | 28.8 % | 25.4 % | 17.2 % | 22.1 % |
| MFCC statistics | live | oracle | 25.2 % | 24.2 % | 17.6 % | 20.0 % |
| MFCC statistics | live | system | 25.2 % | 21.8 % | 13.9 % | 16.9 % |
| AudioFeaturePrint | post-meeting | oracle | **13.8 %** | 12.8 % | 14.1 % | 12.0 % |
| AudioFeaturePrint | post-meeting | system | 20.2 % | 16.8 % | 10.9 % | 13.9 % |
| AudioFeaturePrint | live | oracle | 21.8 % | 20.8 % | 30.7 % | 11.7 % |
| AudioFeaturePrint | live | system | 28.5 % | 25.1 % | 31.0 % | 11.7 % |

Missed speech is 1.0 % throughout, all of it from the overlap fixture. The
energy detector adds 2.5 % false alarm, mostly from the padding it keeps around
each region, and most heavily over the tonal bed.

**Where it works.** Two distinct voices taking turns, in quiet, noise, a narrow
band, over the tonal bed, with 18 dB between them or with 0.1 s between turns.
AudioFeaturePrint with post-meeting clustering scores 0 % DER on all seven of
these with oracle activity, and finds all 67 speaker changes at the reference
boundary. With its own energy detector the same configuration scores
0–14.1 % and finds 40 of the 67 changes, with mean boundary errors up to
0.34 s.

**Where it fails, and how:**

- **No single threshold fits every meeting.** MFCC statistics *split* one voice
  into as many as 9 clusters (one speaker, level change) at the same threshold
  that keeps three voices apart. AudioFeaturePrint *merges* instead: 3 speakers
  become 2, and 6 become 1 or 2. Within one recording the embeddings separate
  two or three distinct voices well, with an equal error rate of 0.0–3.4 %.
  Six voices are harder (3.6 % for MFCC, 11.2 % for AudioFeaturePrint), and so
  is a speaker who returns after a long absence (9.3 %, 16.9 %). Pooled across
  recordings the rate is about 14 %, because the distances are not comparable
  from one recording to the next.
- **Similar voices are near chance.** The Eddy US/UK pair has an equal error rate
  of 39 % (MFCC) and 45 % (AudioFeaturePrint). The system reports one speaker
  or alternates arbitrarily, with 29–71 % confusion.
- **Short interjections carry little evidence.** One-word replies have an equal
  error rate of 27–29 %.
- **Confidence does not calibrate.** On the development split, raising the margin
  from 0 to 0.3 lowered confident error only from 19 % to 16 % (MFCC) and from
  26 % to 25 % (AudioFeaturePrint). The 2 % target was not reachable with any
  margin. A merged cluster is internally consistent, so its windows look
  confident. On six speakers, 28–81 % of the time the system labelled with
  confidence was attributed to the wrong person, depending on the
  configuration.
- **Live is no better than post-meeting.** With AudioFeaturePrint it is clearly
  worse: 21.8 % DER against 13.8 % with oracle activity, 28.5 % against 20.2 %
  with the energy detector, and about 31 % of speech left unattributed. MFCC
  statistics score about the same either way (25.2 % against 25.4 % and
  28.8 %), but only because both are poor. In every multi-speaker fixture the
  live clusterer settled on at most two clusters. Without later context it
  cannot correct an early decision, and the append-only constraint forbids
  correcting it afterwards.

### Recognised passages and speaker turns

ScribeKit writes one passage per finalised `SpeechTranscriber` result. The
harness traced every recognised word back to the script turn it came from by
word-level edit-distance alignment, which does not depend on timestamps.

- **0 of 166** finals on fixtures without overlap mixed two speakers' words,
  including turns 0.1 s apart. The recogniser finalises at the pause between
  speakers, so a passage is a plausible unit to label. Synthetic voices stop
  cleanly, and real crosstalk was not measured.
- **3 of 6** finals in the overlap fixture mixed speakers. A per-passage label
  is wrong by construction there.
- **Recogniser timing is not a speaker boundary.** A final's range, and its
  first word's range, begin where the previous final ended. They absorb the
  silence before the speech: 143 of 172 finals start at least 0.3 s early, and
  the first word of a turn starts a median 0.78 s before its audio. Last words
  end a median 0.25 s early. Mapping passages to speakers would have to use
  where the diarizer heard speech, not the passage's start time.

### Cost

10 minutes of audio, Release build, Apple M1, 16 GB:

| Stage | CPU | Peak footprint increase |
| --- | ---: | ---: |
| Energy activity | 0.013 s | — |
| MFCC statistics, 705 windows | 0.13 s | ≈ 6 MB |
| AudioFeaturePrint, 705 windows (cold load 0.1–0.2 s) | 3.3 s | ≈ 35–45 MB |
| Live clustering | 0.004 s | — |
| Post-meeting clustering, 705 windows | 0.15 s | — |
| Recogniser, for comparison (this process's CPU) | 0.93 s | 8 MB |

Transcription took 10.6 s of wall time alone and 10.5 s with live diarization
running beside it, so there was no measurable interference. The cost that
matters is **agglomerative clustering at meeting length**. Its time grows with
the cube of the window count and its memory with the square: 0.03 s at 400
windows, 0.23 s at 800 and 1.78 s at 1,600 when every window merges. Three
hours of continuous speech is about 14,400 windows. That projects to about
22 minutes of CPU and a 790 MB distance matrix, which breaks the bounded-memory
rule unless the clustering is chunked.

## Third-party options

None was added. The credible local options are neural speaker-embedding
pipelines:

- **FluidAudio** (Apache-2.0 Swift SDK) runs pyannote-derived segmentation,
  WeSpeaker embeddings and clustering converted to Core ML, aimed at Apple
  Silicon. By default it **downloads models from Hugging Face at run time**,
  which ScribeKit's sandbox (no network client entitlement) forbids. Adopting
  it would mean bundling the models.
- **pyannote** models: `segmentation-3.0` is MIT. The
  `speaker-diarization-community-1` pipeline is CC-BY-4.0 and gated behind
  registration on Hugging Face.
- **sherpa-onnx** runs comparable models through ONNX Runtime. That adds a C++
  runtime as well as models.
- **Argmax SpeakerKit** is commercial.

Any of these gives up an intentional property: no third-party runtime code or
model weights in the application. They also add model licences to the
distribution, attribution duties under CC-BY, tens of megabytes of weights,
upstream maintenance, and behaviour that is reproducible only for a pinned model.
Model sizes, exact licences of converted weights and accuracy on real meetings
were not verified here. That work, done in this harness and outside the
application, comes before any recommendation to adopt one.

## Constraints on any future attempt

These follow from ScribeKit's existing invariants rather than from the prototype:

- **Speaker attribution is metadata about a transcript, not transcript
  material.** It belongs in a versioned sidecar under `.scribekit/` that names
  passages by span index, as `review.json` does. It must never be prose in
  `transcript.md`. Legacy sessions simply have no sidecar.
- **Post-meeting, not live.** Live clustering was worse, and its early
  decisions cannot be revised without rewriting what was durably written. A
  live label could only ever be provisional on screen.
- **Post-meeting needs the audio, or embeddings held until the end.** A
  Microphone meeting never retains audio, and an App Audio meeting retains it
  only when the user opts in. Without retained audio, the only option is to
  keep per-window embeddings in memory until the meeting ends. That memory
  grows with the meeting and must never reach disk.
- **Renames are user decisions.** "Speaker 1 → Quang" belongs in
  `derived.json`, never in source artifacts.
- **Reliability markers stay independent.** A gap, a recogniser restart and a
  pause are not speaker changes. Clustering state could not be assumed to
  continue across a crash, so a recovered meeting would start with no
  attribution rather than a guessed continuation.
- **Capture and transcription come first.** A diarizer would be another
  bounded consumer of the capture fan-out, allowed to fall behind and drop work.
  It could never slow audio or finalised text.

## Privacy

The embeddings here are not designed to identify anyone. They still separate
voices: within one recording, two or three distinct voices were told apart
with error rates of 0–3.4 %. Vectors saved from two meetings could be compared to link the
same person across them. That makes them biometric-like data in practice,
whether or not a name is ever attached. The prototype holds them only in memory
for one run and writes only scores. Any product version would have to do the
same: no persisted embeddings, no cross-meeting profiles and nothing sent
anywhere.

## Running the harness

```bash
cd Tools/SpeakerDiarizationPrototype
swift test
swift run -c release diarization-lab all
```

`all` renders the corpus into `.fixtures/` (ignored by Git, about 135 MB), then
writes `results/evaluation.md`, `results/alignment.md`,
`results/performance.md`, `results/evaluation.json` and
`results/ground-truth.json`. `render`, `evaluate`, `align` and `bench` run one
step. The transcription alignment needs the en-US speech model installed.
