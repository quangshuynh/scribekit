# Performance and energy evidence

What ScribeKit was measured doing, on one machine, under sustained real-time
execution. Every number here came from a run described below; nothing is
projected, and nothing is a claim about battery life.

Read this as operational evidence — enough to spot a gross regression and to
tell a real bottleneck from a suspected one. It is not a benchmark suite, and
none of it is statistically rigorous.

## Environment

| | |
|---|---|
| Machine | MacBookAir10,1 (Apple M1), 8 cores, 16 GB |
| System | macOS 26.6.2 (25G83) |
| Toolchain | Xcode 26.6 (17F113) |
| Build | Release, optimised, with `ENABLE_TESTABILITY=YES` |
| Recognition | On-device `SpeechTranscriber`, locale `en-US` |
| Captured sources | Real ScreenCaptureKit application capture |
| Interface | Measured separately — see [The interface](#the-interface) |

`ENABLE_TESTABILITY=YES` adds `-enable-testing` to an otherwise ordinary
Release build; optimisation is unchanged. Debug figures are not mixed in
anywhere, and the two configurations are not compared.

## Method

Since Interval 17 the harness is committed, under `Tools/SoakValidation/`.
Its sources belong to the test target only, so nothing in it ships, and a run
is requested through a file `run-soak.sh` writes into the sandbox container and
deletes afterwards — an ordinary test run and an ordinary launch reach none of
it. Its README states what each run does. Everything below was produced by it.

The measured process runs the real subsystems: a real `SCStream` through the
real `ScreenCaptureKitAudioCapturer`, the real `AppleSpeechTranscriber` over
Apple's on-device recogniser, the real `MarkdownTranscriptStore` writing
through `FileHandle`, and the real `RetainedAudioRecorder` writing through
`AVAudioFile`. Meetings are started, paused, resumed and stopped through
`MeetingRuntime`, the same object the application owns.

Two substitutions, both at a boundary and both deliberate:

1. **Sample content.** This machine has no capturable application that
   produces speech on demand, so a consumer sitting between the real stream and
   the real pipeline replaces each buffer's silent samples with synthesised
   speech — `AVSpeechSynthesizer`, resampled to 48 kHz mono float, about 38
   seconds looped. The buffers' cadence, format, frame counts and presentation
   times are the real stream's; only the sample values are substituted. The
   recogniser therefore does real work on real speech, and the retention
   writers encode real signal rather than silence.
2. **Folder access.** The destination is the process's own temporary
   directory, reached through a granting `SecurityScopedResourceAccessing`,
   because a security-scoped bookmark can only come from a system panel.

Sampling is from inside the process — `phys_footprint` via `task_vm_info`,
CPU via `getrusage(RUSAGE_SELF)`, threads via `task_threads` — every 300
seconds in the soak and every 180 in the comparisons, so the instrument does
not become part of the workload. CPU is process CPU seconds over wall seconds:
100% means one core saturated, on a machine with eight.

## A crash, found here, resolved in Interval 16, confirmed in Interval 17

This is the most important thing the interval found. It was left open here and
diagnosed in Interval 16; the evidence below is what this interval had, and
the section that closes it is **What is not known**, corrected at the end.

ScribeKit crashes during sustained meetings with `EXC_BAD_ACCESS` / `SIGBUS`,
`KERN_PROTECTION_FAILURE` against a stack guard region, on
`quang.ScribeKit.audio-capture` — the capture stream's own delivery queue.
Three occurrences on this machine:

| When | Context | Innermost ScribeKit frames |
|---|---|---|
| 2026-08-30 19:54 | Ordinary interactive use of the application | monitor publish → activity handler → `Task.init` |
| 2026-08-31 00:44 | Measured soak, 26 min in | monitor publish → activity handler → `Task.init` |
| 2026-08-31 01:55 | Measured soak after the change below, 23 min in | monitor publish → activity handler → `Continuation.yield` |
| 2026-08-31 02:22 | Control run with **no** Pause/Resume, ~21 min in | monitor publish → activity handler → `Continuation.yield` |

The first of those has no measurement code anywhere in its stack: it is the
shipped application, used normally, crashing on its own.

In all three the chain into the fault is identical up to the last step:

```
StreamOutput.stream(_:didOutputSampleBuffer:of:)
  → BroadcastingAudioSampleConsumer.consume
  → AudioCaptureActivityMonitor.consume → record → publish
  → the activity handler installed by MeetingRuntime.init
```

### What was tried, and what it showed

The handler installed by `MeetingRuntime.init` created an unstructured
`Task { @MainActor … }`, and it runs on ScreenCaptureKit's delivery queue — so
a meeting created a main-actor task from inside the audio callback twice a
second for its whole length. That is ruled out in as many words by
`AGENTS.md`: a live capture pipeline "never routes high-frequency audio
callbacks through the main actor". It was the obvious suspect and it was
changed: the summary now crosses to the main actor through one long-lived
consumer of an `AsyncStream(bufferingPolicy: .bufferingNewest(1))`, so the
delivery queue yields a value and creates nothing.

**It did not fix the crash.** The next soak died in the same place, on the same
queue, with the same guard-page fault — the innermost frame simply became the
new operation, `AsyncStream.Continuation.yield`, instead of `Task.init`. That
is the useful result: whatever runs on that thread at that moment is what
appears in the report, so the fault is not the operation. The delivery thread's
stack is what is wrong, and the operation is only its victim.

The change was kept, because the code it replaced violated the pipeline's own
stated rule and did strictly more work on the audio callback thread. It is
recorded as a correctness fix, not as a remedy for this.

### What is known

- The fault is on ScribeKit's own delivery queue, never on the main thread.
- The captured stacks are shallow — around 30 to 46 frames, ending normally at
  `start_wqthread` — so this is not deep recursion in ScribeKit, despite the
  label the system puts on it.
- **It is a function of elapsed capture time, not of Pause/Resume.** The first
  two occurrences followed a Pause/Resume by three to five minutes, which
  looked like a lead. A control run with no Pause/Resume at all crashed too, at
  about 21 minutes. All four fall in a band of roughly **20 to 26 minutes of
  continuous capture** — around 60 000 to 80 000 delivered buffers.
- The three ten-minute retention comparisons never reproduced it, which is
  consistent: they end below the band.
- `ScreenCaptureKitAudioCapturer.stop()` invalidates its output and stops the
  stream but never calls `removeStreamOutput(_:type:)`, and a Resume registers
  a new `StreamOutput` for a new `SCStream` on the *same* serial
  `sampleQueue`. That is an untested observation about the teardown path. It is
  no longer a candidate explanation for this crash, since the control run had
  no Resume, but it is worth looking at on its own.

### What was not known here, and what it turned out to be

The mechanism. Two hypotheses were formed here and both were falsified by the
next measurement — that the main-actor hop caused it, and that Pause/Resume
caused it — so no further production change was made on a guess.

The stacks above were read as shallow, and they are not. The `.ips` format
collapses recursive frames; each of these reports carries a
`recursionInfoArray` and an `originalLength` recording what was removed. The
real stacks are about 5,570 frames deep, of which roughly 2,768 are a
repeating two-frame thunk cycle between the monitor's publish and the observer
it calls. The delivery queue's 512 KB stack was being exhausted by an observer
that grew by one wrapper per published update, at 2 Hz. Interval 16's entry in
`CONTEXT.md` has the diagnosis, the isolated reproduction and the fix.

### Confirmed from the outside

Interval 16 proved the mechanism and removed it deterministically. Interval 17
ran the thing that was missing: one continuous sixty-minute meeting against a
real `SCStream`, the real on-device recogniser, the real Markdown store and
compressed retention, ended with a normal Stop.

It did not crash. 180,205 buffers were delivered across 3,604 seconds of
captured media — more than twice the 20–26 minute band every earlier
occurrence fell in, and roughly sixty times the 2,768 published summaries that
used to exhaust the delivery queue's stack. No new crash report appeared on the
machine: the four `.ips` files there are still the four from 30 and 31 August,
none newer than 02:22.

The supported claim is that the corrected monitor completed a sixty-minute
real-time pipeline run, more than twice the historical failure window, and
finalised normally. It is not a claim that the crash can never recur; the
deterministic Interval 16 regression remains the causal proof, and this is the
external confirmation of it.

## Sixty minutes, continuous

Release build, compressed retention, TextEdit captured, sampled every five
minutes. Observations at start, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55 and
60 minutes, then a normal Stop.

| Minute | CPU | Footprint | Threads | Thermal | `transcript.md` | `audio.m4a` |
|---:|---:|---:|---:|---|---:|---:|
| 5 | 7.20% | 91.5 MB | 14 | nominal | 6 026 B | 2 433 041 B |
| 10 | 7.79% | 92.6 MB | 16 | nominal | 12 272 B | 4 805 159 B |
| 15 | 7.34% | 94.3 MB | 13 | nominal | 18 237 B | 7 180 728 B |
| 20 | 7.24% | 94.8 MB | 16 | nominal | 24 632 B | 9 547 316 B |
| 30 | 7.27% | 98.5 MB | 13 | nominal | 36 885 B | 14 288 171 B |
| 45 | 7.12% | 100.1 MB | 12 | nominal | 54 969 B | 21 407 140 B |
| 60 | 7.04% | 106.3 MB | 13 | nominal | 73 596 B | 28 523 170 B |

- **CPU is flat, and slightly declining.** 7.20% at five minutes and 7.04% at
  sixty, with no sample outside 7.04–7.79%. It agrees with the 6.9–7.1% the
  truncated Interval 15 soaks reached before dying.
- **Both files grow steadily and are only appended to.** The transcript adds
  about 1.2 KB a minute and the recording about 0.47 MB a minute — the same
  rate the ten-minute comparison measured — with no step, stall or rewrite.
- **Thermal state was `nominal` at every sample.** Threads stayed between 12
  and 16 while capturing and settled to 11 after Stop.
- **Footprint drifts upward.** 91.5 MB at five minutes to 106.3 MB at sixty:
  roughly 0.27 MB a minute, and monotonic rather than the sawtooth Interval 15
  saw over its shorter runs. What ScribeKit itself accumulates does not account
  for it — 594 finalised spans and 73 KB of transcript text, plus a 17.9 KB
  review sidecar, is under a megabyte between them. The remaining ~14 MB is
  therefore inferred, not measured, to be framework-side caching, and
  attributing it needs Instruments, which was again not run. It is bounded
  enough not to threaten an hour and large enough to be worth watching over
  eight.

**Finalisation.** Stop returned the meeting to `completed` and the runtime to
not running. The transcript parsed into 594 spans and carried its footer; the
session record read `completed`; `audio.m4a` opened at 3 604.3 s against
3 604.3 s of captured media; the review sidecar was valid JSON; exactly one
session directory existed in the destination.

## The interface

The gap Interval 15 left. The same meeting was run with the setup window
visible, hidden with `orderOut`, and with its hosting view taken down — five
minutes each in one run, two minutes each in the shorter runs used to repeat
it. Capture, recognition, retention and transcript work are identical
throughout and the meeting is never restarted, so what changes between phases
is presentation and nothing else.

| Phase | CPU, before the fix | CPU, after |
|---|---|---|
| Window visible | 26.6 / 24.1 / 26.0% | 23.0 / 22.9% |
| Window hidden (`orderOut`) | 26.2 / 23.2 / 22.4% | 21.1 / 20.7% |
| View taken down | 7.2 / 7.6% | 7.2 / 7.3% |

Three things follow, and the first is the important one.

- **Showing the interface roughly triples a meeting's cost.** About 18 points
  of one core on top of a 7.1% floor. That is not a rounding error and it is
  reproducible across five runs.
- **Hiding the window saves almost nothing.** Two to three points. An off-screen
  SwiftUI window keeps evaluating its bodies; only taking the view hierarchy
  down returns the process to the headless floor — which it does exactly,
  which is also the proof that the floor is real and the phases are honest.
- **The update rate is known.** The recogniser published 582, 578 and 583
  events in three consecutive two-minute phases — about 4.8 a second, and
  unaffected by whether anything is on screen. With the capture summary at 2 Hz
  and the elapsed clock at 1 Hz, the interface was asked to update about 7.8
  times a second, so 18 points of a core is roughly 23 ms of CPU per update.

**What was fixed.** Every one of those reads happened inside
`MeetingSetupView`'s own body, so each update invalidated all seven sections of
the form. The three high-frequency readers — the elapsed label, the capture
activity line and the live transcript — now have views of their own. That is
worth about 2.4 points, repeatably: visible fell from a 24.1–26.6% spread to
22.9–23.0%, with the floor unmoved.

**What was not fixed, and is not explained.** The other ~15 points. The
remaining cost is a SwiftUI form re-evaluating at a few hertz, and nothing
measured here says which part of it is expensive. No Time Profiler was run, so
the split between ScribeKit's own view bodies and AppKit/SwiftUI layout is
unattributed, and no further presentation change was made on a guess. The
window is also not the application's own: the harness hosts
`ScribeKitRootView` over the runtime being measured, because the app's window
observes the app's own idle runtime. That idle window exists in every phase and
does no work, but it is a difference from a real session worth stating.

**Behaviour with the window hidden and closed.** Capture, recognition and both
durable writers carried on unchanged through all three phases: buffers
continued at the same rate, `transcript.md` and `audio.m4a` kept growing
across the hidden and closed phases, no second runtime was created, and a
window opened afterwards showed the meeting still running with no finalised
span lost. Closing the window is a presentation act and remained one.

## Retention modes

Ten minutes each, same workload, same sources, one after another. Transcript
output was equivalent across all three (149 finalised spans and about 12 KB at
the nine-minute sample in every mode), so the differences are the writers'.

| Mode | CPU (avg) | Per-window CPU | Audio written | Transcript | Threads after stop |
|---|---|---|---|---|---|
| No audio file | 4.8% | 4.7 / 4.8 / 4.8 | — | 13 503 B | 12 |
| Raw (CAF) | 5.6% | 5.8 / 5.6 / 5.5 | 115 300 096 B | 13 403 B | 11 |
| Compressed (M4A) | 6.7% | 6.7 / 6.6 / 6.7 | 4 910 156 B | 13 359 B | 11 |

What that says:

- Retaining nothing costs about 4.8% of one core. That figure is capture plus
  recognition plus the transcript, and recognition dominates it.
- Raw costs roughly **+0.8 points** over retaining nothing, and grows at about
  11 MB per minute — which is 48 kHz mono float32 written as-is, so the writer
  adds essentially nothing beyond the bytes.
- Compressed costs roughly **+1.9 points** over retaining nothing and **+1.2
  points** over raw, and grows at about 0.47 MB per minute. AAC encoding is the
  most expensive retention option and produces a file about **23× smaller**.
- No mode showed drift across its three windows, and none showed writer
  latency or backpressure: sizes advanced smoothly and no retention failure was
  reported.

The default is compressed. This does not argue against that — a point of a core
on an M1 for a 23× smaller file is a reasonable trade — but it is the real
number, not an assumption.

## Sustained execution

Compressed retention. **No run of an hour completed**: all three attempts ended
in the crash above, at 26, 23 and about 21 minutes. The figures below are what
the runs reached before that, and they agree with each other and with the
ten-minute comparisons.

- **CPU is flat.** 6.9 / 6.9 / 6.9% at five, ten and fifteen minutes in the
  first soak; 7.0 / 7.0 / 7.1% in the second; 7.4% at five, ten, fifteen and
  twenty minutes in the control run. Nothing accumulates that costs time, over
  the stretch that was observed.
- **Memory is bounded.** Resident footprint moved between roughly 78 and 93 MB
  across every run measured, rising and falling rather than climbing: the
  ten-minute comparisons ended at 92.0, 78.8 and 79.3 MB having each passed
  through both ends of that band. This is a sawtooth, not growth proportional
  to meeting length.
- **Thermals stayed nominal.** `ProcessInfo.thermalState` was `.nominal` at
  every sample of every run.
- **Nothing leaks at Stop.** Threads settle from 13–14 while capturing to 11–12
  five seconds after Stop, the meeting reports `completed`, and the runtime
  reports itself no longer running. Observed in the three ten-minute runs,
  which are the ones that reached a normal Stop.

## Pause

Measured across a three-minute pause inside a running meeting. The Interval 15
figures are on the left; Interval 17 repeated the measurement through the
committed harness and is on the right.

| | Active | Paused | Active (I17) | Paused (I17) |
|---|---|---|---|---|
| CPU | 6.9% | **0.4%** | 7.56% | **0.36%** |
| Threads | 14 | 9 | 14 | 12 |
| `transcript.md` | 26 811 B | 26 811 B | 3 971 B | 3 971 B |
| `audio.m4a` | 9 517 363 B | 9 517 363 B | 1 485 074 B | 1 485 074 B |
| Captured media | — | — | 180.2 s | 180.2 s |
| Recognition events | — | — | 880 | 880 |

The second run adds two things the first did not measure. Captured media time
is frozen to the tenth of a second across the pause while wall-clock elapsed
advances from 180.6 s to 361.1 s, which is the two-clock rule holding in a
real run rather than in a test. And the recogniser publishes nothing at all
while paused — the event count does not move — so the 0.36% is not a recogniser
idling quietly, it is a recogniser that has stopped. Resume returned the
meeting to transcribing and the media clock to advancing, reaching 360.4 s by
the end of the run.

Pause does what it says. Capture and recognition stop, both durable artifacts
stop growing to the byte, five threads go away, and what is left is about 6% of
the active cost — the residue of a process holding open files, not a polling
loop. The elapsed clock keeps advancing during the pause, which is correct:
elapsed time is wall-clock and does not stop when capture does. Resume returned
the meeting to transcribing.

The App Nap assertion is deliberately **held** through a pause. Nothing is
being captured then, so it is not buying throughput; it is buying the process's
life. `beginActivity` also opts the process out of sudden termination, and a
pause is exactly when ScribeKit holds an open, unfinalised recording — which,
as Interval 14 established against the real container, is unreadable if the
process dies before it is closed.

## An unexpected capture end, observed at last

Interval 15 looked for a real `didStopWithError` and could not produce one.
Interval 17 got one by accident. The first sixty-minute attempt captured an
application whose windows went away four and a half minutes in, and
ScreenCaptureKit reported it: capture failed with *"Failed to find any
displays or windows to capture"*, the stream stopped, and
`MeetingRuntime.handleCaptureInterruption` ran.

What happened next is the open question Interval 14 raised and Interval 15
could not settle for want of exactly this event. The handler closes the session
through `closeSession()`, whose outcome defaults to `.completed`, so
`session.json` recorded a meeting that lost its capture stream as `completed`.
The durable artifacts themselves were fine — the transcript parsed and carried
its footer, and the 259-second recording opened and matched the captured
duration — but the record describes a failure as a normal end.

Nothing was changed here on the strength of one observation: this interval's
job was measurement, and altering a persisted status enum reaches recovery,
History and the recovery screen. It is recorded as the evidence that question
was waiting for.

## ScreenCaptureKit and a source that quits

Asked directly, with the real framework: capture one application, quit it, and
watch.

TextEdit was captured alone and then quit. It disappeared from
`SCShareableContent.applications` between one five-second sample and the next.
ScreenCaptureKit then:

- delivered **no** stream error,
- called **no** `didStopWithError`,
- produced **no** content-change signal ScribeKit could observe,
- and **kept delivering audio buffers at an unchanged rate** — about 51 per
  second — for the remaining 45 seconds, indistinguishable in cadence from
  before the application existed.

So the answer is that there is no signal. A stream whose only source has quit
stays alive and keeps producing silence, and nothing reaches ScribeKit that
distinguishes that from an application that has simply gone quiet.

ScribeKit does not act on this, on purpose. The only way to infer source death
from what the framework provides is to watch for silence, and silence is not
death — a meeting where nobody is talking looks identical. Inventing that
inference would mean ending meetings that were merely quiet, which is worse
than the gap it would close.

## What this does not show

- **Most of what the interface costs is unattributed.** The measurement exists
  and is reproducible; the explanation covers about 2.4 points of 18. What the
  other fifteen are spent on is not known, and nothing here should be read as
  saying SwiftUI is or is not at fault.
- **No Instruments profiling was run.** No Time Profiler, Allocations, Leaks or
  energy trace. The crash was diagnosed from the system's own crash reports;
  the CPU and memory figures are process-level sampling. Where recognition
  spends its time inside Apple's framework was not attributed, and neither is
  the interface's remaining cost or the hour-long footprint drift.
- **The interface measured is not the application's own window.** The harness
  hosts `ScribeKitRootView` over the runtime it is measuring; the application's
  own window observes the application's own runtime, which is idle in that
  process. The comparison between phases is sound because the difference is
  isolated, but it is not a recording of a user's session.
- **Sample content is substituted, not captured.** Speech reached the pipeline
  through the real stream's buffers but was synthesised rather than played by a
  captured application, for the reason given in [Method](#method). Timing and
  format are real; provenance is not.
- **One machine, one locale**, and the hour-long run happened once.
- **One machine, one locale, short comparisons.** Ten minutes per retention
  mode on one M1 laptop. Enough to see that AAC costs more than raw and that
  neither drifts; not enough to publish a coefficient.
- **Energy was not measured directly.** The App Nap assertion's lifetime is
  reasoned about and tested at the seam, not observed through a power trace.
