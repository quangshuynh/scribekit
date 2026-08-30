# CONTEXT.md

Current working state of the repository. Keep this short and current; see
`README.md` for the project and `AGENTS.md` for the engineering rules.

## Current milestone

Interval 8 — optional audio retention. Complete.

## Current implementation

- `ScribeKit/Models/`: `MeetingState`, `AudioRetentionMode`, `CaptureSource`,
  `MeetingSession`, `AudioCaptureState`, `TranscriptSegment` (with a
  `RecognitionState` of partial or final), `TranscriptionEvent` /
  `TranscriptionInterruption`, `TranscriptionState`,
  `SpeechRecognitionAvailability`, and new for this interval `TranscriptGap`,
  `TranscriptPersistenceState` and `MeetingStartRequest`; new for this
  interval, `AudioRetentionState`.
  `TranscriptionInterruption.audioDropped` now carries an optional
  run-relative `startTime`.
- `ScribeKit/Capture/`: discovery, `CapturedPCMBuffer`, `AudioSampleConsuming`
  with `BroadcastingAudioSampleConsumer`, and `ScreenCaptureKitAudioCapturer`.
  `AudioCaptureConfiguration` now exposes `requestedFormat`, the one place that
  says what format capture is asked for.
- `ScribeKit/Transcription/`: `SpeechTranscribing` (now with `eventTally`),
  `TranscriptionConfiguration` / `TranscriptionLocale`, `BoundedAudioQueue`,
  `SpeechAudioConverter`, `TranscriptionAudioInput` (which now reports where
  dropped audio fell), `AppleSpeechTranscriber`,
  `TranscriptionEventPublisher` / `TranscriptionEventTally`, and
  `SpeechAvailabilityProviding` / `SystemSpeechAvailability`.
- `ScribeKit/Persistence/`: `TranscriptPersisting` (the whole boundary between
  a meeting and the filesystem) with `TranscriptPersistenceError`;
  `TranscriptMarkdownFormatter` (pure string rendering, no I/O);
  `TranscriptFileStoring` / `TranscriptFileAppending` with a
  `FileManager`/`FileHandle` implementation; `MarkdownTranscriptStore`, the
  actor that owns one session; `SecurityScopedLease` with
  `SecurityScopedResourceAccessing`; `SessionDirectoryName` and
  `SessionArtifactLayout`. New for this interval, `SessionRecoveryMetadata`
  with `SessionRecoveryStatus` and `SessionCompletionOutcome`;
  `SessionRecoveryStoring` / `TranscriptFileInfo` / `SessionRecoveryError` with
  a `FileManager` implementation; and `SessionRecoveryService` with
  `SessionRecoveryCandidate`, `SessionRecoveryProblem` and
  `SessionRecoveryReport`. New for this interval, `AudioRetaining` with
  `AudioRetentionError`; `AudioFileWriting` / `AudioFileCreating` with the
  `AVFAudio` implementations `AVAudioFileCreator` and `AVAudioFileWriter`; and
  `RetainedAudioRecorder`, which owns one recording at a time.
  `TranscriptFileInfo` is now `SessionFileInfo`, because it describes a
  retained recording as well as a transcript.
- `ScribeKit/Features/MeetingSetup/`: `LiveTranscriptModel` unchanged;
  `MeetingSetupCaptureModel` coordinates capture, recognition, durable
  persistence and audio retention, and takes a `MeetingStartRequest`; `SessionRecoveryModel` is new
  and owns the recovery section's state; `MeetingSetupView` has a Start Meeting
  control, an explicit Stop, a Transcript File section, a Show in Finder
  control, a Previous Meetings section, and an Audio Retention section that now
  shows the recording's status, its path and a Show Audio in Finder control.
- `ScribeKitTests/`: Swift Testing suites (346 tests, 33 suites).

No background behaviour and no menu bar presence exist. Audio retention writes
a file; nothing plays one.

## Speech API decision

`SpeechAnalyzer` with a `SpeechTranscriber` module, from the Speech framework.

- The deployment target is macOS 26.5 and these types are available from
  macOS 26.0, so nothing was raised to reach them. `SFSpeechRecognizer` was
  rejected: it is the older API and has a server-backed path, which this
  project must not have.
- It streams: the analyzer consumes an `AsyncSequence<AnalyzerInput>` and
  publishes results as they settle.
- It is on-device by construction. Recognition runs against a model in
  `SpeechTranscriber.installedLocales`; there is no network mode to fall back
  to and no flag that would enable one.
- It supports contextual hints through `AnalysisContext.contextualStrings`,
  which `TranscriptionConfiguration.contextualStrings` is wired to. ScribeKit
  ships none, so recognition output is the recogniser's own.
- It needs no permission. Verified live: transcription ran with
  `SFSpeechRecognizer.authorizationStatus()` at `notDetermined`, with no
  prompt, inside the sandboxed app. No Info.plist usage description was added,
  because none is required and asking for one ScribeKit does not need would be
  worse than asking for nothing.

## Local recognition guarantee

Four independent things hold it up:

1. `AppleSpeechTranscriber` refuses to start unless the chosen locale's model
   is in `installedLocales`; otherwise it reports `.modelNotInstalled` and
   nothing starts. It reads that list, `isAvailable`, `supportedLocales` and
   `supportedLocale(equivalentTo:)` through `SpeechAvailabilityProviding`,
   whose only production implementation is `SystemSpeechAvailability` and
   whose only purpose is to let those four host-dependent answers be stated in
   a test. The rules built on them are unchanged, and nothing in the app
   constructs anything but the real one.
2. Model assets are never downloaded. `AssetInventory.assetInstallationRequest`
   exists and is deliberately not called; it returned a non-nil request even
   for an already-installed locale, so it is not a reliable readiness signal
   either. `AssetInventory.status` was `.supported` for a locale that
   `installedLocales` listed, so `installedLocales` is the gate.
3. `SFSpeechRecognizer` is not referenced anywhere in the app target.
4. The app carries no `com.apple.security.network.client` entitlement, so the
   sandbox does not permit it to open a socket. Verified live: `lsof -a -p
   <pid> -i` listed nothing while transcribing.

## Audio format

- ScreenCaptureKit delivers 48 000 Hz, 1 channel, float32, non-interleaved, in
  960-frame (20 ms) buffers, unchanged from Interval 4.
- The recogniser's `availableCompatibleAudioFormats` is exactly two entries:
  16 000 Hz and 8 000 Hz, 1 channel, Int16, interleaved.
  `SpeechAnalyzer.bestAvailableAudioFormat` returns 16 kHz Int16 even when a
  48 kHz float format is offered as the natural one. Conversion is therefore
  required, not chosen.
- One `AVAudioConverter` is built per run and reused; it is rebuilt only if the
  capture format changes. Conversion happens on ScreenCaptureKit's serial
  delivery queue, never on the main actor. The 48 kHz to 16 kHz ratio is exact,
  so 960 frames in gives 320 out after the resampler primes on the first
  buffer.

## PCM ownership

`CapturedPCMBuffer` holds one buffer's frames as `[Float]`, copied out of the
`CMSampleBuffer` while its callback is on the stack, because that memory is not
valid afterwards. It is the smallest copy that makes safe asynchronous
ownership possible: 960 floats, under 4 KB, released as soon as its consumers
have run. The peak level is measured with vDSP in the same pass, so the frames
are read once. No `CMSampleBuffer` is retained past its callback, and no PCM is
accumulated anywhere.

## Backpressure policy

`TranscriptionAudioInput` converts each buffer on the delivery queue and
appends it to a `BoundedAudioQueue` of 150 converted buffers — about three
seconds, roughly 96 KB — which the analyzer drains as an `AsyncSequence`.
Appending never waits.

When the queue is full the **oldest** buffer is evicted, so recognition stays
as close to live as the backlog allows and what is lost is audio it had already
fallen behind on. Each converted buffer carries the time of its first frame
counted from the first frame of the run, so an eviction leaves a real gap in
the timeline rather than sliding everything after it forward. Lost time is
accumulated and reported as `.interrupted(.audioDropped)` once it reaches half
a second, and the remainder is flushed at stop, so a badly behind recogniser
produces a readable statement rather than one event per buffer. The interface
states the total as untranscribed seconds.

## Retained audio formats

Both are native, both are written incrementally by `AVAudioFile`, and the
choice between them is the user's.

- **Raw** is linear PCM in a **CAF** container, at exactly the format capture
  delivers: 48 kHz, mono, 32-bit float. It is the captured audio, not a
  re-encoding of it. CAF rather than WAV for two measured reasons. A WAV header
  addresses its data with 32 bits, and raw capture costs **691 MB an hour**
  measured, so a meeting would pass WAV's four-gigabyte ceiling after about six
  hours; ScribeKit is built for long meetings. And a CAF left unclosed by a
  process that was killed still opens and reports its real duration, which was
  verified live rather than assumed.
- **Compressed** is **AAC at 64 kbit/s** in an MPEG-4 container, `audio.m4a`.
  Measured at **31 MB an hour**, about a twenty-second of raw. The bit rate is
  fixed in `AVAudioFileCreator.compressedBitRate`; there is no bit-rate
  picker, because it would be a choice with no question behind it.

The encoder is `AVAudioFile`'s own, which is an `ExtAudioFile` converter built
when the file is created and reused for every buffer. ScribeKit builds no
`AVAudioConverter` of its own for retention and constructs nothing per buffer:
one scratch `AVAudioPCMBuffer` is allocated for the first captured buffer and
reused, growing only if a larger buffer ever arrives.

A file's format is fixed when its container is created, and the first captured
buffer has not arrived by then, so the file is opened for
`AudioCaptureConfiguration.requestedFormat` — what ScribeKit asks
ScreenCaptureKit for. Audio that arrives at another sample rate or channel
count is refused as `unsupportedCapturedFormat` rather than resampled into a
file that would claim the wrong rate. Float-ness and interleaving are adapted
by copy, not conversion, so a mono buffer is written whichever way it is
labelled.

## Audio retention architecture

`AudioRetaining` is the only boundary between a running meeting and an audio
file. It is deliberately *not* a queue in front of a writer: it conforms to
`AudioSampleConsuming`, so the retainer is one more consumer on
`BroadcastingAudioSampleConsumer` beside the activity monitor and the
transcriber.

**Backpressure, stated exactly: there is none, because there is no queue.**
`RetainedAudioRecorder.consume(_:)` writes the buffer to the file, on
ScreenCaptureKit's serial delivery queue, before it returns.

- Maximum backlog: one buffer — the one being written.
- Audio dropped to keep up: none, ever. There is nothing to evict.
- If the writer could not keep up it would slow the delivery queue, not discard
  audio. Measured on this Mac, writing 20 ms of 48 kHz mono costs about 46 µs
  as PCM and about 200 µs as AAC, against the 20 ms before the next buffer is
  due — roughly 0.2% and 1% of the budget.
- A failed write fails **retained audio**, and that ends the meeting. Capture
  is not blamed; `AudioRetentionState` carries the reason.
- The transcript does **not** continue after a retention failure. Continuing
  would produce a recording with a silent hole in the middle while the
  interface still claimed audio was being kept, which is the loss-hiding this
  interval exists to prevent. The alternative — keep transcribing, abandon the
  audio — was rejected for that reason and is recorded as a limitation.

Because `consume` cannot throw, failures reach the meeting through an
`AsyncStream<AudioRetentionError>` buffering the newest one, the same shape
`AudioCapturing.interruptions` already uses. Only the first matters: the
recorder stops writing after it.

`AVAudioFile` finalises a container when its last reference goes away and has
no closing call that could report a problem, so `AVAudioFileWriter.close()`
drops the file and then opens the finished file for reading. That header read
is how "the recording was closed" becomes a fact rather than a hope.

## Partial and final semantics

The recogniser reports a volatile hypothesis for the span being spoken and,
when it settles, a finalised span covering it. Observed live: ten partials
growing word by word, then one final for the sentence. `LiveTranscriptModel`
therefore keeps finalised segments in an array and the partial as a single
value that each new partial replaces, so five hypotheses leave one entry.
Recognised text is stored exactly as returned; only display trims the space
that joins one span to the previous one.

## Runtime interruption and recovery

- A recogniser that stops by itself surfaces as
  `.interrupted(.recognitionFailed)`. The coordinator restarts it at most twice
  while capture continues, and records the time it was down as untranscribed.
  Beyond that the run is reported as failed rather than retried forever. This
  path is unit tested; it has not been observed live, because the recogniser
  did not fail.
- A capture stream that stops by itself moves capture to `failed` and stops
  recognition, which has nothing left to transcribe.
- Stopping stops capture first, then finalises recognition, so the last
  sentence is not lost and no audio arrives after the input closes.
- A run that accepted no audio at all never ends its results sequence — proved
  with a standalone harness. The wait for it is bounded at two seconds and the
  task is then cancelled, so a stop can never hang. A cancelled results task is
  not reported as a recogniser failure.

## Locale behaviour

`TranscriptionConfiguration.localeIdentifier` is explicit and BCP-47. The
screen offers every locale `SpeechTranscriber.supportedLocales` reports, marks
the ones whose model is not installed, and disables the picker during a run.
The default is the system locale when the recogniser supports it, otherwise the
first installed locale. Nothing detects or switches language on its own.

This Mac: 30 supported locales, 9 installed (all `en-*`).

## Persistence architecture

`TranscriptPersisting` is the boundary between a running meeting and the
transcript: `startSession`, `appendFinalSegment`, `recordGap`, `finishSession`.
`AudioRetaining` is the boundary between a running meeting and its recording,
and is the only other one. No `FileManager`, `FileHandle` or `AVAudioFile` call
exists above either, and test doubles exercise a whole meeting without a disk
or a codec.

`MarkdownTranscriptStore` is an actor and the serialised owner of one session:
its folder lease, its open file, and the formatter's position in the document.
Being an actor is the backpressure design — appends are ordered without a queue
of their own, and a caller awaiting one is held back by the previous write, so
there is nothing to overflow and nothing to evict. Writes run on the actor's
executor, never on the main actor and never from a SwiftUI body.

Formatting is separate from writing. `TranscriptMarkdownFormatter` is a value
type that renders strings and touches no filesystem, so the exact bytes of a
document are checked against golden strings. Its only state is the last minute
it wrote a heading for.

`TranscriptFileStoring` / `TranscriptFileAppending` is a two-method view of the
filesystem, narrow enough that the production implementation has no logic and a
double can fail on demand.

## Session layout

```
<chosen save folder>/
  2026-08-29-closures-walkthrough/
    transcript.md
    audio.caf         # raw retention only
    audio.m4a         # compressed retention only
    .scribekit/
      session.json
```

The directory name comes from `SessionDirectoryName` (date prefix plus title
slug, numeric suffix on collision) and the paths from `SessionArtifactLayout`.
`transcript.md` and `.scribekit/session.json` are always created; exactly one
audio file is created when retention is on, and none when it is off. There is
never both. The transcript is the user's document; the record is ScribeKit's
bookkeeping, and losing or failing to parse it never makes the transcript
unusable.

## Security-scoped access lifetime

`SecurityScopedLease` makes the start/stop pair macOS balances an object with an
owner. A lease is acquired when a session's directory is about to be created and
released when its transcript has been flushed and closed — including on every
failure path, so a refused start or a failed meeting never leaves one open.
Outside a meeting, access is borrowed only for validation, through
`SecurityScopedAccess.withAccess`. Verified live: `lsof` on the running app
listed no handle on the destination between meetings.

## Markdown format

```
# Closures Walkthrough

**Date:** 2026-08-29
**Started:** 10:01 AM
**Sources:** QuickTime Player
**Language:** en-US
**Captured by:** ScribeKit

## Transcript

### 10:01 AM

**10:01:33**

Today, we are learning about closures in Swift.

> **Transcription gap:** approximately 0.8 seconds of audio around 10:01:41 was not transcribed; recognition fell behind capture.

---

**Ended:** 10:02 AM
**Duration:** 1 min 4 s
```

Recognised text is written exactly as it was finalised, apart from trimming the
whitespace that joins one span to the previous one. Nothing is escaped: a
recogniser emits words, and adding backslashes would put characters in the
transcript that were never spoken.

The document is append-only. `Ended` is not known while the meeting runs, so it
is a footer rather than a header field that would have to be rewritten.

## Timestamp semantics

A segment's time is `session start + segment.startTime`, where the offset is
audio-relative — measured from the first captured frame, not from when a result
reached the interface. A minute heading is written when the minute bucket
changes and never twice for the same minute; gaps do not open one.

Formatting is deterministic and locale-independent: an ISO date and a fixed
twelve-hour English clock, computed from `Calendar(identifier: .gregorian)` in
an explicit time zone that defaults to the Mac's current one. Times to the
second omit `AM`/`PM`, which the minute heading above them carries.

## Audio and transcript timeline

A retained recording's time zero is **the first captured frame that reached the
retainer**, and a `TranscriptSegment`'s offset is measured from **the first
captured frame that reached the transcription input**. Those are the same
frame: both are consumers of the same `BroadcastingAudioSampleConsumer`, both
are started before `capturer.start`, and both therefore see the same buffer
first. So segment offset *t* is second *t* of the audio file, frame for frame,
with no synchronisation machinery and nothing to keep in step.

What is *not* exact is the wall clock. The transcript's timestamps are
`session start + offset`, and the session starts a moment before the first
frame arrives, so a stated time can be under a second early — the Interval 6
limitation, unchanged, and not made worse or better by retention. The precise
relationship is between the offsets and the file, not between the clock and the
file.

One honest edge: `TranscriptionAudioInput` does not advance its elapsed clock
for a buffer whose conversion to the recogniser's format fails, while the
recording still holds that buffer's frames, so a conversion failure would slide
the two apart by the length of the buffers it lost. No conversion has ever
failed here. Buffers *evicted* under recognition backpressure do not have this
problem: the clock advances for them, they stay in the recording, and the
recording is then the only place that audio exists.

## Gap semantics

`TranscriptGap` carries a duration, a reason and an optional run-relative
position. Dropped audio is positional: `TranscriptionAudioInput` reads the
start time of the buffer it evicted, so the marker names where the loss fell.
Time lost to a recogniser being rebuilt is not: no audio clock is running while
it is down, so only the length is stated. No position is invented for either.

## Flush and stop

Durability boundary, stated honestly: an append reaches the file as soon as
`appendFinalSegment` returns, so accepted text survives ScribeKit exiting or
being killed. The device flush that would also survive a power loss is asked
for every 25 appends and once at `finishSession`. There is no timer, no polling
and no flush per audio buffer.

Stop order: capture, then the recogniser's finalisation, then a wait until
every event the recogniser published has been handled, then the recording's
close, then footer, flush, close, and the folder lease. Only then is the
meeting reported as finished. The
wait is a barrier against the transcriber's own published-event count resumed
by the event handler, not a poll and not a sleep. Transcription events travel
through a bounded `AsyncStream`; the publisher records anything the buffer
discarded, and a non-zero count fails the meeting rather than losing finalised
speech quietly.

A write that fails mid-meeting sets `TranscriptPersistenceState.failed`, closes
the writer, releases the folder and stops capture and recognition, so ScribeKit
never keeps recognising into a transcript it is no longer saving. A failure is
never overwritten by a later claim that the transcript was saved. The recording,
if there is one, is closed after capture stops and kept: a transcript failing is
no reason to throw audio away.

## Session record

`.scribekit/session.json`, one per session directory, schema version 1. It is
operational bookkeeping, not a second transcript: no segment text, no audio, no
runtime object. Fields are `schemaVersion`, `sessionID`, `title`, `startedAt`,
`sourceNames`, `localeIdentifier`, `transcriptPath`, `audioRetention`,
`audioPath`, `status`, `endedAt` and `interruptedAt`. Encoded with sorted keys, indented and ISO-8601 dates, so the
file is legible to a person working out what happened and its bytes are stable
between writes. A real one is about 300 bytes.

There is no last-checkpoint field. "When did this last save something" is
answered by the transcript's own modification date, which is measured rather
than asserted, and which costs no writes to keep true.

`audioRetention` and `audioPath` were added this interval and the version was
deliberately **not** raised. Both are optional and additive: a record written
before they existed decodes with them absent, which is the truth about a
session that kept no audio, and a decoder that has never heard of them ignores
two extra keys. Raising the version would have made every earlier session
unreadable in exchange for nothing. `audioRetention` is written for every
session, including `"none"`; `audioPath` only when there is a recording, and it
is a claim about a name, not about a file existing. The mode is recorded
because it is not discoverable afterwards — a meeting killed before its first
captured buffer leaves a directory indistinguishable from one that kept no
audio.

`schemaVersion` is read on its own before anything else is interpreted. A
record announcing any other version is reported as unsupported and left
untouched — never decoded field by field, because fields that happen to still
parse would give a confident answer about a layout this build has never seen.
There is no migration framework.

`status` has four values:

- `inProgress` — the transcript is open. A record left like this after ScribeKit
  exits is a meeting that never finished, and is the only status recovery
  offers.
- `completed` — the transcript was flushed and closed and the meeting ended
  normally.
- `failed` — the meeting was ended because the transcript stopped being saved.
  ScribeKit was running and told the user at the time, so this is a closed
  session, not a lost one, and it is not offered for recovery.
- `interrupted` — the session was found unfinished after a relaunch and the
  user was shown it. Recorded so the same interruption is not reported forever.

## Session lifecycle ordering

Start: folder lease, session directory, `transcript.md` with its header, the
record as `inProgress`, **then the audio file**, then recognition, then
capture.

The record is written before anything is captured; a start that cannot write
one closes the file, releases the lease and fails with
`.recoveryMetadataFailed`, and neither recognition nor capture begins. The
audio file comes next because it is the other artifact the user asked for: a
start that cannot create it closes the transcript session as `failed`, and
neither recognition nor capture begins either. Capture is last, so no buffer is
delivered before every consumer that wants one exists.

Stop: capture, the recogniser's finalisation, the event drain, **the audio
file's close**, then footer, flush, close — and only then the record as
`completed`.

The recording is closed before the transcript rather than after, because the
transcript's writer owns the folder lease the recording was written under and
is the thing that writes the record. So the ordering rule generalises rather
than being duplicated: `MeetingSetupCaptureModel.closeSession` finalises
retained audio first and turns a retention failure into
`SessionCompletionOutcome.failed`, and `MarkdownTranscriptStore` still refuses
to record a completion ahead of its own flush and close.

If the footer, flush or close fails, the record is not touched at all, so the
session stays `inProgress` and the next launch offers it. If the record cannot
be written after a clean close, the meeting is reported as failed rather than
finished; the file is complete but ScribeKit will not claim a completion it
could not record.

Failure semantics, in full:

| What failed | Transcript | Recording | Recorded status |
| --- | --- | --- | --- |
| Audio file cannot be created at start | created, closed | none | `failed` |
| Audio write, mid-meeting | flushed and closed | closed where it stopped | `failed` |
| Audio finalisation at stop | flushed and closed | left exactly as it is | `failed` |
| Transcript write, mid-meeting | closed, no footer | closed, kept | `failed` |
| Nothing | flushed and closed | closed | `completed` |

Nothing in any row deletes an artifact. A recording that failed is closed and
left on disk with everything that reached it, because meeting audio cannot be
captured a second time.

A meeting ended by a save failure is closed as `failed` and writes no footer:
`Ended` and `Duration` would be a claim about a document that stopped being
written, and the file has just refused a write in any case.

The record is only ever replaced atomically, so a partially written
`session.json` is not a state a crash can leave behind.

## Durability boundary

Stated exactly, and no wider: **already-durable finalised transcript content
survives a restart, a session that did not finish is detectable, and a raw
recording is readable up to the moment ScribeKit stopped.**

Recovered because it was written: every finalised span `appendFinalSegment`
returned for, the session record, and — for `audio.caf` only — the audio that
had reached the file.

Not recovered, because it was never written: audio still in an OS or framework
buffer, a partial hypothesis that was never finalised, a finalised result that
had not yet reached the file, and anything said while ScribeKit was not
running. Not recovered because it cannot be read: a partly written `audio.m4a`,
whose container is indexed at close. Surviving a power loss rather than a
process death additionally depends on the flush every 25 appends and at Stop;
retained audio has no flush of its own, so the same caveat is wider for it.

ScribeKit is not crash-proof and does not say it is.

## Startup discovery

`SessionRecoveryService.scan(_:)` lists the immediate children of the folder the
user chose and reads `.scribekit/session.json` in each. One level, no recursive
walk, nothing outside that folder. It runs when the screen appears and when a
folder is chosen, and never while a meeting is running — the session being
written is legitimately `inProgress`. No timer, no watcher, no repeat scan, and
no work left running afterwards.

A directory without a record is not a ScribeKit-recorded session and is passed
over silently; sessions written by Interval 6 are therefore not detected, which
is honest, since nothing recorded them.

The service is an actor, so the filesystem work is off the main actor and one
scan or update happens at a time. `SessionRecoveryModel` is `@MainActor` and
holds the resulting state; the view displays it and implements none of it.

Candidates are ordered by start date descending, tie-broken on directory path,
so repeated scans of the same folder produce the same list and two sessions
found together stay two sessions.

## Retained audio after an interruption

Discovery reads a recording's size and modification date and nothing else. It
never opens, decodes, repairs, moves or deletes one — verified live, byte for
byte, across two scans.

Whether a partial recording plays depends on the container, and this was
measured rather than assumed, by killing the running app with `SIGKILL`
mid-meeting:

- **`audio.caf` survives.** A CAF killed after ten seconds opened in `afinfo`
  and `AVAudioFile`, reported `estimated duration: 10.18 sec`, and decoded to
  real audio at peak 0.80. CAF writes a data chunk whose size readers derive
  from the file, so an unclosed one is still a file.
- **`audio.m4a` does not.** A killed M4A held 137 KB of encoded audio and
  `AudioFileOpenURL` refused it: an MPEG-4 container's index is written when
  the file is closed, and a killed process writes none.

The recovery row therefore states the recording's name and size and says it
"was still being written, so whether it plays depends on how far it got" — it
does not claim playability for either format. No repair or reconstruction is
attempted, and nothing is ever inferred from audio about speech that was not
transcribed.

## Recovery sandbox behaviour

Access is owned by the service and by nothing else in recovery: each call takes
`SecurityScopedAccess.withAccess` on the save folder for exactly its own
duration and releases it, including on every failure path. Nothing is held
between a scan and whatever the user does next. Verified live: `lsof` on the
running app showed no handle on the save folder between meetings.

The destination itself comes from the existing bookmark, through
`MeetingSetupDestinationModel`. When it cannot be restored or opened, ScribeKit
says it could not check for an unfinished meeting and looks nowhere else.

## Recovery UX

A `Previous Meetings` section appears only when there is something to say. For
each unfinished meeting it states the title, when the meeting started, when the
transcript was last written and how large it is, and the transcript's path —
and, when the record named a recording and the file is there, that recording's
name and size, said as a file that was still being written rather than one
known to play. When ScribeKit stopped is not shown, because nothing measured
it.

Three controls, none of which resumes anything:

- **Show in Finder** reveals `transcript.md`.
- **Mark as Interrupted** re-reads the record, confirms the transcript is still
  readable, writes the record as `interrupted`, and appends the interruption
  note. The session is not offered again.
- **Dismiss** hides the finding for this launch and changes nothing on disk, so
  it is offered again next launch. Closing a panel is not a decision worth
  writing down.

Nothing in recovery constructs a capturer or a recogniser, so no ScreenCaptureKit
or Speech permission prompt can come from it.

## Interruption marker

The note is appended to `transcript.md`, which keeps the file append-only, and
only when the user asks for it. Discovery never writes.

```
---

> **Session interrupted.** ScribeKit stopped before this meeting was finished,
> so the transcript ends at the last speech that reached the file. When it
> stopped is not known, and nothing was transcribed after that point.
> Interruption recorded by ScribeKit on 2026-08-29 at 10:50 AM.
```

(One line in the file; wrapped here.) It is a blockquote, like the gap markers,
so ScribeKit's structural remarks stay distinguishable from recognised speech in
the rendered document as well as in the source. It names only the moment the
interruption was recorded — not a crash time, not a gap duration — and no
recognised text is touched.

Ordering here is deliberately the opposite of completion: the record is written
first and the note second. Completion is a claim about the file, so it must
follow the file; the note is a remark in the user's document, and the failure
worth preventing is writing it twice. An interruption is therefore at worst
recorded without its note, never noted twice, and a note that cannot be appended
is reported.

## Logging

None was added. No `OSLog` category, no transcript text, no PCM, no meeting
titles, no telemetry.

## Validation status

`xcodebuild ... clean test` passes on Xcode 26.6: **346 tests in 33 suites**, no
compiler warnings. The `AppleSpeechTranscriber` suite starts and stops the real
recogniser twice, which is where its 4.2 s comes from — two bounded drains of a
run that received no audio.

Speech availability is not the same on every Mac, and the tests no longer
pretend otherwise. `SpeechTranscriber.isAvailable` is `false` on
GitHub's hosted `macos-26` runners, which have no speech models and reported no
supported locales; tests written against this Mac's thirty locales failed there
while the app behaved correctly. The unsupported-system, unsupported-locale,
model-not-installed, available and locale-listing rules are now decided against
a stated environment, so they assert the same thing on any host. What remains
against the real framework is a smoke test that reads
`SystemSpeechAvailability.isAvailable` first and asserts what is true for that
answer — no locales and `.unsupportedSystem` when there is no recogniser,
structurally valid records and correct installed-state mapping when there is —
and the lifecycle test, which still needs a real installed model and returns
without one. Neither downloads anything.

### Interval 8 live validation

Driven through the real app, sandboxed, with the interface operated by scripted
keyboard and mouse events. QuickTime Player played a `say`-generated recording
of five sentences about Swift closures as the only selected source, writing to
a folder on the Desktop chosen in the open panel. The folder and its contents
were deleted afterwards; nothing from it is in the repository.

- **No Audio File.** A meeting ran, transcribed all five sentences and stopped.
  The session directory held `transcript.md` and `.scribekit/session.json` and
  nothing else. The record read `"audioRetention" : "none"` with no
  `audioPath`, and `"status" : "completed"`.
- **Raw.** `audio.caf` appeared when the meeting started and grew as it ran.
  After Stop: 3 237 376 bytes, `afinfo` reporting `1 ch, 48000 Hz, Float32` and
  `estimated duration: 16.840000 sec` against a 17-second meeting. Decoded to
  real audio — peak 0.804, 452 984 frames above 1% — so it is the meeting, not
  silence. The record carried `"audioRetention" : "raw"` and `"audioPath" :
  "audio.caf"`. The transcript was the same document a `.none` meeting produced.
- **Compressed.** `audio.m4a`, 173 223 bytes for the same 16.84 seconds,
  `afinfo` reporting AAC at 52.9 kbit/s actual, decoding to peak 0.803 and
  452 616 audible frames — the same audio. About 19× smaller than the raw file
  of the same meeting.
- Over matched 60-second runs the sizes were `audio.caf` 13 782 016 bytes and
  `audio.m4a` 614 373 bytes for 71.7 seconds each: **691 MB/hour** and
  **31 MB/hour**, which is where the figures in the interface come from.
- After every Stop, `lsof` on the running app listed no handle on the save
  folder and no sockets. Starting again created a new dated session directory
  with its own recording; no meeting ever wrote into an earlier one, and no
  session directory ever held both a `.caf` and an `.m4a`.
- `SIGKILL` during a raw meeting: `audio.caf` 1 958 656 bytes, still opening,
  `estimated duration: 10.18 sec`, decoding to peak 0.804. The record stayed
  `inProgress`; the transcript held the sentences finalised before the kill.
- `SIGKILL` during a compressed meeting: `audio.m4a` 137 068 bytes, and both
  `afinfo` and `AVAudioFile` refused to open it. The transcript and the record
  were unaffected.
- On relaunch the recovery section offered the killed raw meeting and stated
  "Audio audio.caf · 1958656 bytes. It was still being written, so whether it
  plays depends on how far it got." Two scans left the recording and the
  transcript hashing identically to before.
- The retention picker was disabled while a meeting ran, and the Audio
  Retention section showed "Saved and closed.", the file's path and a Show
  Audio in Finder control afterwards.

### Interval 8 CPU and memory

A sanity check, not a benchmark: a Debug build, driven by scripted UI events,
with QuickTime looping. Each mode ran a 60-second window after 10 seconds of
warm-up, measured as process CPU time consumed over that window.

| Mode | CPU over 60 s | Resident memory |
| --- | --- | --- |
| No Audio File | 15.1 s (25%) | 135 → 136 MB |
| Raw | 15.1 s (25%) | 137 → 137 MB |
| Compressed | 16.2 s (27%) | 129 → 130 MB |

Raw retention costs nothing measurable on top of capture, recognition and
resampling. Compressed costs about one extra second of CPU per minute — the
AAC encoder — which is the expected shape and is bounded. Memory moved by about
a megabyte in each window with no difference between modes, which is what a
pipeline that streams rather than accumulates should look like. The absolute
figures are higher than Interval 5's because this is a Debug build with the
accessibility scripting attached; the comparison between modes is the point.

### Interval 7 live validation

Driven through the real app, sandboxed, with the interface operated by scripted
keyboard and mouse events. QuickTime Player played a `say`-generated recording
of five sentences about Swift closures as the only selected source, writing to a
folder on the Desktop chosen in the open panel. The folder and its contents were
deleted afterwards; nothing from it is in the repository.

- Launched with the previous run's save folder deleted, the recovery section
  said "Unfinished meeting check failed. The saved folder could not be found…"
  and offered nothing. No other folder was scanned.
- A meeting started: `transcript.md` and `.scribekit/session.json` appeared
  together. The record read `"status" : "inProgress"` with the schema version,
  session identifier, sources, locale, start date and `"transcriptPath" :
  "transcript.md"`, and 298 bytes of nothing else.
- Five sentences were finalised into the transcript (474 bytes, SHA-256
  recorded). The app was then killed with `SIGKILL` while capture and
  recognition were running — no Stop.
- The transcript's hash was unchanged by the kill; the record still read
  `inProgress`; there was no footer.
- On relaunch the recovery section appeared: "Untitled Meeting did not finish",
  "Started Aug 29, 2026 at 10:49 AM", "Transcript last written Aug 29, 2026 at
  10:49 AM · 474 bytes", and the transcript's path. Capture read "Not
  capturing", recognition read "Ready, on this Mac", and the transcript file
  section read "No transcript yet". `lsof` showed no handle on the save folder
  and no sockets. Nothing was captured, no recogniser was started, and no
  permission prompt appeared.
- Mark as Interrupted set the record to `"status" : "interrupted"` with
  `"interruptedAt"`, and appended the interruption note. The first 474 bytes of
  the file hashed identically to the pre-crash transcript, each sentence and the
  title appeared exactly once, and the note appeared once.
- Relaunching again did not offer the session, and the transcript was unchanged.
- A second meeting was run and stopped normally. Its record read `"status" :
  "completed"` with `"endedAt"`, and its transcript carried the `Ended` and
  `Duration` footer. After a relaunch it was not offered as unfinished.
- The completed record was then truncated mid-JSON and a third directory was
  planted with a `"schemaVersion": 9` record. On relaunch both were reported —
  "…session record is damaged and was left untouched. Its transcript is
  unaffected." and "…written by a newer version of ScribeKit (format 9) and was
  left untouched." — neither was offered as recoverable, both records were
  byte-identical afterwards, and the transcript beside the damaged one hashed
  identically to before.

Force-terminating immediately after a finalised segment was not attempted
separately; the kill above landed while a meeting was running with five
segments already durable, which is the same boundary.

### Interval 5 live validation, still current

Used a purpose-built looping player application (outside the repository)
speaking seven sentences about Swift closures, captured as the only selected
source. The observations below were taken before durable writing existed, which
is why nothing was open for writing at the time.

- Capture: 48 000 Hz mono float32 non-interleaved, ~50 buffers/second,
  peak 37–44%, unchanged from Interval 4.
- Recognition started with no permission prompt and reported "Transcribing on
  device".
- The transcript filled with one finalised entry per sentence, each with its
  offset from the start of the run, and one italic partial below them. Over
  ~2 minutes no partial hypothesis became an entry.
- Recognition is honest about what it heard: "async and await" came back as
  "asking and await" and was left alone. ScribeKit does not correct it.
- Stop froze the counters and returned both subsystems to idle; a second start
  produced a fresh transcript on a fresh timeline from 00:00.
- `lsof -a -p <pid> -i` listed no sockets while transcribing, and no regular
  file was open for writing. The app's container held no `.md`, `.caf`, `.m4a`
  or `session.json` afterwards.
- A ~15 minute continuous run, of which 9.5 minutes were sampled every 15 s
  with `top`: resident memory moved between 47 MB and 56 MB in a sawtooth, with
  no upward trend, and CPU held at 13–15% for capture, resampling and
  recognition together. Recognition kept up throughout; no audio was dropped,
  so the backpressure path was not exercised live and is covered by tests
  instead. The interface stayed responsive with the transcript at several
  hundred segments.

### Interval 6 live validation

Driven through the real app, sandboxed — the interface operated by scripted
keyboard and mouse events, not by calling into the code — with QuickTime Player
playing a
`say`-generated recording of three sentences about Swift closures as the only
selected source, writing to a temporary destination chosen in the open panel.
The destination and its contents were deleted afterwards; nothing from it is in
the repository.

- Three meetings were run. Each created its own dated directory —
  `2026-08-29-closures-walkthrough`, then `-2`, then `-3` — so the collision
  policy is exercised live, and no meeting appended to an earlier one.
- `transcript.md` appeared as soon as the meeting started, with the header, and
  filled in as sentences were finalised. Read from the shell while the meeting
  was still running, it was complete and valid up to that point.
- The live transcript showed the partial "Next we will discuss" at a moment
  when the file contained only finalised sentences. No partial text ever
  reached the file.
- Timestamps tracked the session timeline, and a minute heading `### 10:02 AM`
  appeared exactly once when the meeting crossed the minute.
- Stop reported "Saved and closed." and the footer with `Ended` and `Duration`
  was present. `lsof` then showed no handle on the destination and no sockets.
- Only `transcript.md` was created. No `.scribekit`, no `session.json`, no
  `audio.caf`, no `audio.m4a`, and nothing in the app container.
- Recognition stayed honest: "self contained" for "self-contained" was left
  alone, as was "async and await" when it came back correctly this time.
- The save folder was restored from its bookmark after a relaunch and the
  meeting after the relaunch wrote a new session, leaving the earlier
  transcripts byte-identical.

### Interval 6 durability smoke test

The second meeting was force-quit with `SIGKILL` while it was running, after
several sentences had been finalised. Its `transcript.md` survived: 413 bytes,
header and every finalised sentence up to the kill, valid Markdown, with no
footer — which is the honest record of a meeting that never finished. It was
read outside ScribeKit, from the shell, and was valid Markdown throughout.
Nothing was reopened, repaired or recovered; that is a later interval.

### Interval 2, 3 and 4 checks, still current

Source discovery, multi-source selection, save-location restoration and
selected-application audio capture all still behave as recorded for those
intervals; the capture observations above were taken through the same path.

## Known limitations

- Interval 2, 3 and 4 limitations still hold.
- Retention writes audio; it does not play it. There is no playback, waveform,
  scrubber or uncertainty review, and a retained recording is opened in another
  application.
- A recording is not encrypted. It is an ordinary audio file in the folder the
  user chose, as private as that folder is.
- A partly written `audio.m4a` does not open, because an MPEG-4 container is
  indexed at close. Measured, stated, and not repaired: audio repair is not
  something this interval builds.
- A retention failure ends the meeting, so speech after that moment is not
  transcribed either. The alternative — keep transcribing and abandon the
  recording — was rejected because it hides the loss, but it is a real cost and
  a later interval may want the choice to be the user's.
- Audio arriving in a format other than the one capture was asked for fails the
  meeting rather than being resampled. On this Mac ScreenCaptureKit has always
  delivered the requested 48 kHz mono float32; a Mac where it did not would get
  a failed meeting rather than a wrong-rate recording.
- Closing a recording is confirmed by reopening the finished file's header.
  That proves the container is readable; it does not prove every sample reached
  the disk, and `AVAudioFile` offers no flush of its own.
- A meeting whose recording could not be finalised writes no `Ended` and
  `Duration` footer, because it is closed as `failed`. The transcript is
  otherwise complete.
- Retention write failure, finalisation failure and creation failure are
  covered by injected failures in tests; no real disk-full or
  permission-revoked failure was reproduced.
- The retained file's alignment with transcript offsets rests on both consumers
  seeing the same first buffer. A conversion failure inside
  `TranscriptionAudioInput` would slide them apart; that has never happened.
- Audio and CPU were observed on one Mac, in a Debug build, over one-minute
  windows. A multi-hour retention run has not been measured.
- Recovery recovers the artifact and the record, not the meeting. It never
  resumes capture or recognition; continuing into the same session is a later
  interval, and was left out deliberately rather than half-built.
- Surviving a power loss depends on the flush every 25 appends and at Stop, so
  an abrupt power cut can cost the appends since the last one. ScribeKit does
  not claim to be crash-proof.
- A start that fails after the transcript was created leaves that session
  folder behind with a header and no speech, and a start that fails at the
  record leaves one with no record either. ScribeKit does not delete
  directories it created, and recovery never deletes a transcript.
- Session directories written before this interval carry no record and are not
  detected as unfinished. Their transcripts are unaffected.
- A meeting closed as `failed` is not offered for recovery. If the record could
  not be updated at that moment, it stays `inProgress` and is offered instead —
  over-reporting rather than under-reporting.
- Discovery runs at launch and when a folder is chosen. A session interrupted
  in another launch while this one is open is not noticed until the next scan.
- Only one save folder is ever scanned: the one currently in use. Sessions in a
  folder the user has moved on from are not found.
- The record's `interruptedAt` is when ScribeKit noticed, not when the meeting
  stopped. Nothing observes the second, so nothing states it.
- Metadata write failure, transcript flush failure, damaged records and
  unsupported schema versions are covered by injected failures in tests and,
  for the last two, live; a real disk-full or permission-revoked failure was
  not reproduced.
- The transcript's timeline starts when the meeting starts; audio offsets are
  measured from the first captured frame, which arrives a moment later, so a
  timestamp can be under a second early.
- Overflow of the transcription event buffer fails a meeting rather than losing
  text, but it has never been observed: the path is covered by unit tests.
- Recognition needs an installed on-device model. Uninstalled locales are
  listed and disabled, and ScribeKit will not install one.
- Dropped audio is now positional in the transcript; time lost to a recogniser
  restart is not, and is stated as a length alone.
- Bounded recovery from a recogniser failure is unit tested only; no live
  recogniser failure was reproduced.
- Confidence is not requested. `SpeechTranscriber` can attach a
  `transcriptionConfidence` attribute; it is left off until there is a review
  interface that would use it, rather than surfacing a number with nowhere to
  go.
- Stopping waits up to two seconds when the recogniser's results sequence does
  not end on its own, which happens when a run received no audio at all.
- Memory and CPU were observed, not benchmarked; formal energy measurement is
  a later interval.
- Dropping audio under backpressure has never happened on this machine, so the
  policy is proved by unit tests rather than by a live overload.

## Next interval

Interval 9: background and menu bar operation, as the roadmap has it. The
meeting screen now owns three subsystems, a start ordering with rollback at
every step, and a stop ordering that finalises two artifacts before recording a
completion. Moving the meeting behind a menu bar item means that lifecycle has
to survive the window going away — `MeetingSetupCaptureModel` is currently
owned by `MeetingSetupView` as `@State` and is stopped in `onDisappear`, which
is exactly the assumption background operation has to undo. Nothing about
retention needs to change for it: the recorder is already off the main actor
and already indifferent to whether a window exists.

The other candidate is post-meeting review against a retained recording, which
is what retention was built to make possible. That needs playback, a
transcript-to-audio seek, and `transcriptionConfidence` — three things
deliberately left out here — and it should follow rather than precede
background operation, because the alignment it depends on is already recorded
and will not decay.

`MeetingState.recovering` is still unused: recovery does not resume capture, so
nothing enters that state. It should stay unused until an interval implements
continuing an interrupted meeting, which will have to decide what a second
recognition run appended to an existing transcript means for the timeline.
