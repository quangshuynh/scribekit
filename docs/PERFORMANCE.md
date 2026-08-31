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
| Interface | None — see [Limitations](#what-this-does-not-show) |

`ENABLE_TESTABILITY=YES` adds `-enable-testing` to an otherwise ordinary
Release build; optimisation is unchanged. Debug figures are not mixed in
anywhere, and the two configurations are not compared.

## Method

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

## An unresolved crash

This is the most important thing the interval found, and it is still open.

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

### What is not known

The mechanism. A shallow stack that faults on its guard page is not explained
by anything found this interval. Two hypotheses were formed and both were
falsified by the next measurement — that the main-actor hop caused it, and that
Pause/Resume caused it — so no further production change was made on a guess.
One of the four reports says the kernel "could not determine thread index for
stack guard region", which would fit a write to an unmapped page better than it
fits recursion, but that is an observation about a message, not a diagnosis.

What it needs is a debugger on a reproducing run, which is cheap now that the
recipe is known: real capture, compressed retention, leave it running, expect
it between twenty and twenty-six minutes.

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

Measured across a three-minute pause inside a running meeting:

| | Active | Paused |
|---|---|---|
| CPU | 6.9% | **0.4%** |
| Threads | 14 | 9 |
| `transcript.md` | 26 811 B | 26 811 B |
| `audio.m4a` | 9 517 363 B | 9 517 363 B |

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

- **No interface was measured.** The measured process runs no window, so these
  figures are a meeting's cost with presentation at zero — a floor, not the
  cost of a visible meeting. The visible-versus-hidden-versus-closed comparison
  the interval asked for was not obtained, so nothing here says what SwiftUI
  costs during a meeting or whether hiding a window saves anything measurable.
- **No Instruments profiling was run.** No Time Profiler, Allocations, Leaks or
  energy trace. The crash was diagnosed from the system's own crash reports;
  the CPU and memory figures are process-level sampling. Where recognition
  spends its time inside Apple's framework was not attributed.
- **Sample content is substituted, not captured.** Speech reached the pipeline
  through the real stream's buffers but was synthesised rather than played by a
  captured application, for the reason given in [Method](#method). Timing and
  format are real; provenance is not.
- **No unexpected capture end was observed.** The event most likely to cause
  one — the captured application quitting — turns out not to reach that path at
  all, so what ScribeKit should record when capture ends by itself remains
  unresolved rather than decided. It needs a real `didStopWithError`.
- **One machine, one locale, short comparisons.** Ten minutes per retention
  mode on one M1 laptop. Enough to see that AAC costs more than raw and that
  neither drifts; not enough to publish a coefficient.
- **Energy was not measured directly.** The App Nap assertion's lifetime is
  reasoned about and tested at the seam, not observed through a power trace.
