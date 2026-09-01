# CONTEXT.md

Current working state of the repository. Keep this short and current; see
`README.md` for the project and `AGENTS.md` for the engineering rules.

## Current milestone

Interval 25 — release hardening and manual evidence. The automated gates all
pass and the application's own configuration was audited against what the
documentation claims. One documentation-truth release blocker was found and
fixed: the published minimum macOS version. The human-driven evidence this
interval exists to collect — a real meeting, VoiceOver, a keyboard-only pass
and a visual review — was **not** collected, because no person performed it.
See *Interval 25 validation* below. **Feature freeze for v0.1.0 remains in
force.**

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
- `ScribeKit/Review/`, new for this interval: `TranscriptReviewReason` /
  `TranscriptReviewPriority` / `TranscriptReviewCandidate` /
  `TranscriptReviewPolicy` (which spans are worth reviewing, and how urgently —
  pure), `SessionReviewMetadata` / `SessionReviewError` / `SessionReviewStoring`
  / `FileManagerSessionReviewStore` (the versioned `.scribekit/review.json`
  sidecar and its one write), and `RetainedAudioPlaybackPlan` (the seek, pure) /
  `RetainedAudioPlayer` (`@MainActor @Observable`, `AVPlayer` over an
  `AVURLAsset`, owning a `SecurityScopedLease` for the length of playback).
- `ScribeKit/History/`: `TranscriptDocument` /
  `TranscriptSpan` / `TranscriptHeaderField` (reading a written transcript back,
  no I/O), `HistorySession` / `HistorySessionStatus` / `HistoryAudio` /
  `HistoryAudioFormat` / `TranscriptSearchDocument`, `HistoryStoring` /
  `FileManagerHistoryStore` / `HistoryError` (a read-only filesystem boundary),
  `HistoryService` / `HistoryReport` / `HistoryProblem` (the discovery policy,
  an actor), and `TranscriptSearchIndex` / `TranscriptSearch` /
  `HistorySearchResult` / `HistoryMatchKind` / `TranscriptExcerpt` (a pure
  matcher).
- `ScribeKit/Features/History/`: `HistoryModel`
  (`@MainActor @Observable`), `HistoryView` and `HistorySessionDetailView`.
  `ScribeKit/Features/ScribeKitRootView.swift` is the window's two tabs.
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
- `ScribeKit/Meeting/`, new for this interval and the home of the active
  meeting: `MeetingRuntime` (formerly `MeetingSetupCaptureModel`) coordinates
  capture, recognition, durable persistence and audio retention and takes a
  `MeetingStartRequest`; `LiveTranscriptModel` moved here with it;
  `MeetingRuntimeStatus` derives one lifecycle answer from the four subsystem
  states; `MeetingElapsedClock` times the running meeting;
  `MeetingActivityAsserting` / `ProcessMeetingActivity` hold the App Nap
  assertion; `MeetingQuitCoordinator` decides what Quit does.
- `ScribeKit/Features/MeetingSetup/`: `SessionRecoveryModel` owns the recovery
  section's state; `MeetingSetupView` takes the runtime rather than creating
  one, no longer stops anything in `onDisappear`, and disables the title,
  source, folder, language and retention controls while a meeting runs.
- `ScribeKit/Features/MenuBar/`, new: `MeetingMenuBarPresentation` (a pure
  mapping from runtime state to what the menu says) and `MeetingMenuBarView`.
- `ScribeKit/App/`: `ScribeKitApp` has a single `Window` scene and a
  `MenuBarExtra`; `ScribeKitAppDelegate` is new and owns the runtime.
- `ScribeKit/Models/`: new for this interval, `MeetingSnapshot`.
- `ScribeKit/App/`, new for this interval: `MeetingCommands`, the application's
  own menus, derived from the same `MeetingMenuBarPresentation` the menu bar
  reads.
- `ScribeKit/Features/`, new for this interval: `ScribeKitTab` /
  `ScribeKitTabSelection` (which screen the window shows, published as a
  scene-focus value) and `HistorySearchFocus` (a standing request for the
  History search field, published the same way).
- `ScribeKit/Diagnostics/`, new for this interval: `ScribeKitLog` (one
  subsystem, eight categories), `DiagnosticSafety` (the privacy contract and
  the sanitiser for framework text), `DiagnosticCategory` (the stable support
  name for a failure), `DiagnosticNames` (a stable word per state, in place of
  `String(describing:)`), `DiagnosticReport` with its assembly,
  `DiagnosticReportWriter`, and `MeetingDiagnostics`, the process-lifetime
  owner of the export.
- `ScribeKitTests/`: Swift Testing suites (703 tests, 65 suites).

## Meeting ownership

The active meeting is owned by `ScribeKitAppDelegate`, which holds one
`MeetingRuntime` as a `let` for the process's lifetime. Both scenes are handed
that object: the `Window` scene passes it to `MeetingSetupView`, and the
`MenuBarExtra` passes it to `MeetingMenuBarView`.

The delegate rather than `@State` on the `App` struct, for one reason:
`@NSApplicationDelegateAdaptor` is constructed before the App's own state is
available to it, and the quit policy needs the runtime. Putting the runtime in
the object that already has the application's lifetime removes the ordering
problem instead of working around it, and it is not a singleton — nothing looks
it up globally, it is passed in.

What moved and what did not:

- **Runtime** (application-scoped): the meeting's capture, recognition,
  transcript writing and audio retention; the live transcript; the snapshot of
  what the meeting was started with; the elapsed clock; the activity assertion.
- **Presentation** (view-scoped, unchanged): `MeetingSetupSourcesModel`,
  `MeetingSetupDestinationModel`, `SessionRecoveryModel`, the title field and
  the retention picker. These configure the *next* meeting, so they are exactly
  the state that should disappear with the window.

`MeetingSetupView.onDisappear` no longer exists. Nothing in the view layer can
stop a meeting except the Stop control.

## Presentation lifetime

Four lifetimes, and they are not the same thing:

- **Process.** `ScribeKitAppDelegate`, and the one `MeetingRuntime` it holds.
- **Meeting.** From Start to whichever ending arrives; always inside a process.
- **Window.** The single `Window` scene's `NSWindow`, closable and reopenable.
- **View hierarchy.** The interface inside that window, and the only one of
  the four this interval changed.

A closed SwiftUI window scene is not an idle one. The scene outlives the
window, so before this interval the whole of `ScribeKitRootView` stayed
installed behind a closed window: still observing the runtime, still having its
bodies evaluated, still being laid out on the display cycle. Interval 17
measured the consequence — hiding the window saved two to three points, while
taking the hosting view down returned the process to its headless floor — and
Interval 18 profiled why: about 30% of the process's CPU was SwiftUI layout,
most of it the live transcript's scroll view.

The window scene now holds `MainPresentationScene`, a shell that costs nothing
and contains two things: a zero-size `NSViewRepresentable` that reports which
window it is in, and a branch that builds `ScribeKitRootView` only while that
window is on screen. Closing the window releases the interface; opening it
builds a new one. `MainWindowPresence` is the whole of the mechanism. It
key-value-observes the window's `visible` and `miniaturized` properties —
rather than the notifications that usually accompany them, because a window can
be ordered on screen without becoming key, and an interface that missed that
would leave an empty window in front of the user — and re-reads the window on
the next turn of the main loop, so the answer is always the window's own.

The reporter lives in the shell rather than in the interface deliberately: the
thing that notices the window coming back cannot be part of what goes away when
the window leaves.

Nothing about the meeting lives in either. `MainPresentationScene` never reads
the runtime, so rebuilding the interface cannot invalidate the shell and
detaching cannot pause, stop or duplicate anything. A reopened window prepares
itself the way any first open does and reads current runtime state: the running
meeting's title and elapsed time, its active or paused status, capture
activity, every finalised span, the current partial hypothesis, and whatever
failure or interruption is standing. There is no UI-state cache, because there
is nothing to cache — the meeting is the state.

What the window's own `@State` still owns is the configuration for the *next*
meeting, restored from the preference store as it always was.

## One lifecycle answer

`MeetingRuntimeStatus` is computed from `captureState`, `transcriptionState`,
`persistenceState` and `audioRetentionState` — idle, preparing, transcribing,
stopping, completed, or failed with a message. It is a derivation, not a second
state machine: nothing assigns it, so the menu bar and the window cannot
disagree. Failure is reported by artifact first (transcript, then recording,
then capture, then recognition) and as soon as it exists, including while the
teardown it triggered is still running, because a meeting that has lost an
artifact is not "stopping normally".

`MeetingState` is untouched. It remains the persisted domain lifecycle in
`MeetingSession` and the session record; the runtime's status is a presentation
answer that needs a `failed` case the persisted enum does not have, and adding
one to a `Codable` enum for the sake of the menu bar would have been the wrong
trade.

## Configuration immutability

`MeetingSnapshot` is taken in `start(_:)` before anything is created, and holds
the `MeetingSession` (title, sources, destination, retention mode, creation
time) plus the locale. Everything after that reads the copy. The setup screen
disables the controls a running meeting has already fixed, but the snapshot is
what makes it true: a meeting cannot adopt a later edit even if a control were
left enabled.

## Window and quit behaviour

- **Closing the main window** ends nothing. `Window` (not `WindowGroup`) is the
  scene, so Open ScribeKit fronts or recreates the one window rather than
  stacking copies. `applicationShouldTerminateAfterLastWindowClosed` returns
  `false`, so ScribeKit stays running with its menu bar item whether or not a
  meeting is under way.
- **Quitting during a meeting** asks: "A meeting is still being transcribed."
  with *Stop Meeting and Quit* and *Cancel*. Cancel returns `.terminateCancel`
  and changes nothing. Stopping returns `.terminateLater`, runs the ordinary
  `stop()`, and replies to the termination when it finishes.
- The stop is **not** raced against a deadline. Every step in it is bounded
  already, and terminating out from under a transcript that is being closed
  would produce exactly the half-written files the policy exists to prevent.
- `MeetingQuitCoordinator` holds no AppKit — the question and the reply are
  closures — so the policy is tested without a modal alert.

## Menu bar

`MenuBarExtra` with `.menu` style. The label is one SF Symbol per status; the
menu shows the meeting's title, `Transcribing · mm:ss`, the applications being
captured and the retention mode, then Pause Meeting or Resume Meeting when the
runtime would act on one, Stop Meeting, Show Transcript in Finder and Show
Audio in Finder when there are any, then Open ScribeKit and Quit ScribeKit. Idle, it is three lines: the state, Open and Quit.

`MeetingMenuBarPresentation` is a pure value built from the status, the
snapshot and the two artifact URLs, so the mapping is unit tested. Elapsed time
is deliberately outside it: it changes every second and nothing else there
does.

Pause Meeting and Resume Meeting appear when `canPause` and `canResume` say
the runtime would act on them, alongside Stop Meeting. The application's own
menus in `MeetingCommands` are built from the same presentation value, so the
window's menus and the menu bar cannot disagree about what a meeting can take.

## Elapsed time

`MeetingElapsedClock`, one per application, owned by the runtime. It starts
with the meeting, ticks once a second with a single `Task` (a second `start`
cancels the first, so recreating the interface cannot leave two behind), and
stops when the runtime stops holding resources. It writes nothing and reads
nothing persistent; `startedAt` in the transcript and the session record remain
the authoritative account of when a meeting ran. Its `now` closure and tick
interval are injectable, so the tests advance time rather than waiting for it.

## App Nap

`ProcessMeetingActivity` holds one `ProcessInfo.beginActivity` assertion for
exactly the length of a meeting, with
`.userInitiatedAllowingIdleSystemSleep` — the narrowest option that opts the
process out of App Nap. `.userInitiated` was rejected because it also disables
idle system sleep, which is a promise ScribeKit does not make; `.latencyCritical`
was rejected as a realtime-media option with no evidence behind it here.

It is driven from `didSet` on all four subsystem states rather than from
`start` and `stop`, because a meeting also ends through capture interruption, a
retention failure and a persistence failure — anything keyed to the happy path
would leak the assertion down the other three. Tests substitute a double and
assert the assertion is taken once and released on the failure path as well as
the normal one.

**Honesty about why it is there:** no throttled hidden meeting was observed on
this Mac. The assertion was added because a hidden, windowless application
running user-initiated timed work is precisely the case App Nap exists for, and
because the failure it would cause — audio arriving late enough to be dropped —
is a silent one that a short validation run would not reliably reveal. It is
scoped to the meeting and released on every path, so its cost when unnecessary
is nothing.

## UI updates while hidden

No throttling boundary was added. With the window closed, the SwiftUI scene is
gone and nothing renders; while it is merely hidden, measured CPU did not rise
in a way that justified speculative machinery. The distinction the design keeps
is that presentation may be coalesced and capture, recognition and persistence
may not — recorded as a rule in `AGENTS.md` — so a later interval that finds a
real cost has somewhere to put the fix.

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

## Start readiness

`MeetingStartReadiness` is the single answer to whether Start Meeting can
succeed. It is a pure value derived from four inputs — `SaveLocationReadiness`
from `MeetingSetupDestinationModel`, `CaptureSourceReadiness` from
`MeetingSetupSourcesModel`, `SpeechRecognitionAvailability` from the runtime,
and whether a meeting is active — and it produces one row per prerequisite plus
at most one blocking reason.

The prerequisite order is the blocking order: save location, capture access,
speech recognition, capture source. It follows the dependencies rather than the
order `MeetingRuntime.start` happens to check things — without a folder there is
nothing to write, and without capture access there is no list to select a source
from. The setup screen shows every row; the Start control gets one reason, shown
beside the button as well as in its help, so a disabled button is never silent.

A row's status is `satisfied`, `checking`, `advisory` or `blocked`. `checking`
prevents a start without describing a problem, which matches the runtime: it
refuses to start while availability is `unknown`. `advisory` never blocks — a
folder that could not be remembered is usable for this launch.

Readiness is derived on every evaluation, never stored, so a corrected
prerequisite stops being reported without anything clearing it. It is a snapshot
rather than a subscription: nothing polls, and a permission granted or a model
installed is noticed at the next Refresh or Check Again.

## Capture access

Discovery still follows the normal macOS permission flow: the first
`SCShareableContent` request is what makes macOS ask, and nothing pre-checks in
order to avoid asking. When a request fails, `ScreenCaptureKitSourceProvider`
asks `CGPreflightScreenCaptureAccess` — public, authoritative and
non-prompting — so a missing permission is reported as one rather than as a
framework error. `SCStreamError.userDeclined` is still taken at face value.

`CaptureSourceDiscoveryError.accessUnavailable` replaces `permissionDenied`,
and the copy says access is unavailable rather than that the user denied it: a
permission never asked for and one refused are indistinguishable from here.
There is no System Settings deep link. macOS exposes no supported API for
opening a specific privacy pane, so the path is named in words.

## Ending presentation

`MeetingCompletion` records what the session was closed as and whether capture
ever ran. The second half is what separates a start that never began from a
meeting that died an hour in: both are recorded as `failed`, and they need
different things said about their artifacts.

`MeetingOutcomePresentation` derives from that plus the four subsystem states,
and answers three questions for every ending — what happened, what it means for
this meeting's transcript and recording, and what to do next. Its categories are
`completed`, `interrupted`, `transcriptFailure`, `audioFailure`,
`recognitionFailure` and `startFailure`; the subsystem's own message is
secondary detail. The window shows it as an inline panel with Show in Finder and
Dismiss, and the menu bar reads the same value, so an interrupted meeting reads
as interrupted in both rather than as a failure in one and a completion in the
other.

`MeetingRuntimeStatus` is unchanged. It describes what a meeting is doing now
and is derived from subsystems that cannot tell an interruption from a failure;
the outcome can, and refines the menu bar's status line.

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

**10:01:33 AM**

Today, we are learning about closures in Swift.

> **Transcription gap:** approximately 0.8 seconds of audio around 10:01:41 AM was not transcribed; recognition fell behind capture.

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

A segment's time is `epoch wall start + (segment.startTime - epoch media start)`.
For a meeting that was never paused there is one epoch — media zero at the
session start — so this is `session start + segment.startTime`, unchanged. Each
resume appends an epoch, and a segment uses the last epoch whose media start it
is at or past. The offset is audio-relative — measured from the first captured frame, not from when a result
reached the interface. A minute heading is written when the minute bucket
changes and never twice for the same minute; gaps do not open one.

Formatting is deterministic and locale-independent: an ISO date and a fixed
twelve-hour English clock, computed from `Calendar(identifier: .gregorian)` in
an explicit time zone that defaults to the Mac's current one. Every wall-clock
time states `AM` or `PM` — the header's `Started`, the footer's `Ended`, minute
headings, span times, and the pause, resume, gap and capture-interruption
remarks alike. A span's time is read on its own, quoted out of the document and
matched by search, so leaning on the heading above it to supply the period left
a line that was ambiguous by itself. Nothing else about the format moved, and
no offset, seek or captured-media time is wall-clock.

Transcripts written before this stated the period only on the minute heading.
They are not rewritten and not migrated. `TranscriptDocument` accepts both
shapes, keeps a span's time exactly as the file states it, and
`TranscriptClock.description(clock:heading:)` falls back to the heading's
period for a span that carries none.

## Audio and transcript timeline

A retained recording's time zero is **the first captured frame that reached the
retainer**, and a `TranscriptSegment`'s offset is measured from **the first
captured frame that reached the transcription input**. Those are the same
frame: both are consumers of the same `BroadcastingAudioSampleConsumer`, both
are started before `capturer.start`, and both therefore see the same buffer
first. So segment offset *t* is second *t* of the audio file, frame for frame,
with no synchronisation machinery and nothing to keep in step.

Pausing does not move that. Media time advances only while capture runs, so a
pause adds nothing to a segment's offset and nothing to the recording: the
audio after a resume continues from the frame before the pause, with no
synthetic silence and nothing buffered across it. Offset *t* is still second
*t* of the file after any number of pauses, which is what keeps review
playback's seek direct. Verified end to end in the Interval 12 validation
below, for `audio.caf` and `audio.m4a` alike.

The recogniser's own timeline does reset: a resumed run counts from its first
frame again. `MeetingRuntime` holds one accumulator, `mediaOffsetBase`, set
from a `CapturedMediaClock` after the pause has drained, and adds it to every
offset a run reports — segments and the position of dropped audio — before
anything is displayed or written. The base is read from captured frames rather
than from the wall clock, so nothing a pause spends can leak into it.

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

## Pause and resume

Pause is the front of a stop and no more: capture stops, the recogniser
finalises the audio it already holds, every event it produced is handled and
written, and then the meeting sits in `AudioCaptureState.paused` with its
transcript, its recording, its session record and its folder lease all still
open. Resume rebuilds the stream from the `AudioCaptureConfiguration`
snapshotted at the start — the same rule as every other part of a meeting's
configuration — restarts the recogniser and returns to `.capturing`.

`AudioCaptureState.paused` is `isActive` and `canStop`, and
`MeetingRuntimeStatus` derives `.paused` from it before its "something is still
active" cases, so the menu bar and the window read one answer. There is no
second lifecycle state and nothing sets a paused flag.

The two clocks, stated once. **Captured media time** is `CapturedMediaClock`, a
capture consumer first in the fan-out, counting each buffer's own frames over
its own sample rate; it is what transcript offsets, the recording and review
seek share. **Wall-clock time** is what the transcript's timestamps state, what
`MeetingElapsedClock` shows in the window and the menu bar, and what the
footer's `**Duration:**` reports — the user-facing elapsed time is deliberately
wall-clock meeting length, so a paused meeting's timer keeps running. A
transcript that was paused also carries `**Captured:**`, the recording's
length. Captured duration is otherwise internal, on `MeetingRuntime` and in the
session record.

The pause is written into the document as two blockquotes, the convention gap
markers already use:

```
> **Paused:** 11:42:10. Capture stopped here; nothing was recorded until the meeting resumed.

> **Resumed:** 11:48:32, after 6 min 22 s paused.
```

Both ends of the pause were observed, so its length is stated. Neither marker
calls an intentional pause a recognition failure or missed speech, because
nothing was captured to miss. Recognised text is untouched and timestamps
already written are never recomputed: the epoch opens before the resume marker
is appended, so only what comes after it is measured from the new wall start.

Failure semantics. A pause that reaches the drained boundary but cannot write
its marker is *not* reported as paused: the write failure fails the transcript
the way any other one does, and the meeting ends. A resume that cannot start
recognition, or cannot start capture, leaves the meeting paused with every
artifact untouched and reports why in `pauseFailureMessage`, which is held
apart from `captureState` precisely so the paused state survives it; a source
that has quit is named and never substituted, and the resume can be retried.
Stop while paused runs the ordinary stop, in the ordinary order. Quit while
paused goes through `MeetingQuitCoordinator` unchanged, because a paused
meeting is an active one.

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
- `failed` — the meeting was ended because a durable artifact stopped being
  saved. ScribeKit was running and told the user at the time, so this is a
  closed session, not a lost one, and it is not offered for recovery.
- `interrupted` — the meeting ended without being stopped, and its artifacts
  were closed holding everything that reached them. Two paths write it: a
  session found unfinished after a relaunch, marked once the user has been
  shown it so the same interruption is not reported forever; and a meeting
  whose capture stream ended by itself, closed this way while ScribeKit was
  still running. Not offered for recovery either way.

`completed` therefore means two things at once and needs both: every durable
artifact finished successfully, *and* the meeting ended because someone ended
it. Closing a transcript cleanly is a claim about a file and is never on its
own a claim about a meeting, which is why `SessionCompletionOutcome` has no
default and every path that ends a meeting states which ending it is.

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
| Capture stream ends by itself | marker, footer, flushed and closed | closed, kept | `interrupted` |
| Nothing | flushed and closed | closed | `completed` |

Nothing in any row deletes an artifact. A recording that failed is closed and
left on disk with everything that reached it, because meeting audio cannot be
captured a second time.

A meeting whose capture ended by itself keeps its footer, because the document
did close cleanly and `Ended` and `Duration` are true of it. What it gains
first, at the point capture died, is one blockquote in the convention the gap
and pause markers already use:

```
> **Capture ended unexpectedly:** 11:03:12 AM. The meeting was not stopped;
> capture of its audio ended by itself, so nothing was captured or transcribed
> after this point.
```

(One line in the file.) The moment is stated because this process observed it,
which is exactly what the recovery notice cannot say. The framework's own
reason for the failure is not written there: the meeting screen shows it while
it matters, and `transcript.md` is a meeting's record rather than a diagnostic
log. `session.json` carries the status, `endedAt` and `interruptedAt`; the
Markdown carries the remark and nothing else new.

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

## Pausing and the session record

`capturedDuration` is written for every session ScribeKit closes, not only for
one that paused: the runtime has measured it on `CapturedMediaClock` by the
time it closes a session, so leaving the field absent would describe a record
written before the field existed rather than the meeting that just ended. It
is never derived from wall-clock length, and a record that genuinely predates
the field still decodes with it absent.

`pausedAt` and `capturedDuration` were added to `session.json` additively at
schema version 1, for the reason `audioRetention` and `audioPath` were: both
are optional, a record written before they existed decodes with them absent,
and a build that has never heard of them ignores them. Raising the version
would have made every earlier session unreadable in exchange for nothing.

The record is rewritten at each pause and each resume, so a ScribeKit that
stops while a meeting is paused leaves a record that says `inProgress` with a
`pausedAt`. `SessionRecoveryMetadata.wasPausedWhenInterrupted` is exactly that
pairing, and the recovery screen states it: the meeting was paused at a stated
time and ScribeKit stopped before it was resumed or finished. Nothing resumes
capture on relaunch; recovery still only offers to mark the session interrupted,
and `markingInterruption` carries `pausedAt` through rather than dropping an
observed fact. A record ScribeKit closes clears `pausedAt`, because a closed
meeting is not paused.

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

Recovery and a running meeting never overlap. `MeetingRuntime.allowsRecovery`
is false while anything is running, which skips the scan and disables *Mark as
Interrupted*: the session being written right now is legitimately recorded as
in progress, and offering it as an interrupted meeting — or writing an
interruption note into a transcript that is still open — would be nonsense. The
scan still runs when the screen appears and when a folder is chosen, and never
on a timer or because the menu bar changed.

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

## Interrupted-session continuation

Interval 23 asked one question — should an interrupted meeting be continuable
into the same session before v0.1.0 — and answered **no**. The answer is a
decision backed by two measurements, not a scoping compromise, and the code is
unchanged.

Five cases were kept apart, because reusing one's machinery for another would
weaken it. Pause and resume inside one process is the only one that resumes
anything, and it is implemented. Capture ending under a running ScribeKit
closes the meeting as `interrupted` with a dated marker. A killed process
leaves a record saying `inProgress`. A relaunch finds that record and offers to
mark it interrupted. A session already `interrupted` is a closed account of a
meeting. Continuation would be a sixth thing: a second capture run appended to
a session a previous process left behind.

**What was measured.**

- **A retained recording cannot be reopened and continued.** `AVAudioFile`
  opens a file for writing by replacing it: a second writer over an existing
  `audio.caf` reports `framePosition == 0` and the finished file holds only the
  second run — the first run's audio is gone. Measured in a standalone harness
  and then pinned as a test against the shipping `AVAudioFileCreator`. This
  falsifies the assumption that raw CAF is the easy case: it is not merely
  unsupported, reusing the path is destructive. Appending would need a
  different file-writing implementation altogether, and none exists here.
- **An unfinalised `audio.m4a` is still unreadable.** Reproduced independently
  of Interval 12's SIGKILL run, by writing AAC and leaving the process without
  releasing the file: `ExtAudioFileOpenURL` refuses it. There is nothing to
  continue, and repairing an MPEG-4 container is not something ScribeKit does.
- **A meeting killed while capturing has recorded no captured length.**
  `session.json` is written at the start, at each pause, at each resume and at
  the close, and nothing checkpoints it in between, so the record left by the
  case continuation exists for carries `capturedDuration == nil`. Pinned as a
  test. The remaining candidates for a restart base are the recording's own
  duration — unreadable for a killed M4A, and absent when retention is
  `none` — and the transcript's last span, which under-reports by whatever was
  captured but never finalised. Continuation would therefore start its offsets
  from a guess, and an offset that names the wrong second of a recording is
  exactly the thing the two-clock rule exists to prevent.

**What follows.** Honest continuation needs a second recording per session:
`audio-0001.caf`, `audio-0002.caf`. That is not a persistence tweak. It changes
what a session directory is; `session.json`'s `audioPath` from one name to a
list, at six call sites that resolve exactly one URL; `review.json`, whose
candidates carry bare `startTime`/`endTime` seconds and no segment identity, so
review playback could no longer turn an offset into a file; History's
presentation of a recording; and the Finder actions in the menu bar and the
menus. Every session recorded before the change would need reading through the
old shape as well. That is a persistence-format change immediately before a
first release, for a condition that recovery already handles truthfully.

The transcript side is no cheaper. `TranscriptFileStoring.createFile` truncates
an existing file — `FileManager.createFile` returns `true` and leaves zero
bytes, checked — so continuation would need a new open-for-append path on the
canonical artifact's write path. And the entry point could only ever be an
`inProgress` session that has not yet been marked: an `interrupted` one already
carries its footer and its interruption note, and appending speech after those
would make the document state an ending in its middle. "You may continue a
meeting, but only if you have not pressed the one button recovery offers" is
not a user model worth shipping.

**What was not done.** No production code was written, no abstraction was left
half-wired, and the probe harness was deleted; what survives is the two tests
that establish the constraints. `ScreenCaptureKitAudioCapturer.stop()` and
`removeStreamOutput(_:type:)` were left alone: no continuation testing reached
a stream lifecycle, so nothing implicates it.

**What a user does instead.** Keep the interrupted session — its transcript
holds every finalised span that reached the file — mark it as interrupted, and
start a new meeting. Two truthful documents, and nothing invented between them.

## History discovery

`HistoryService.load(_:)` lists the immediate children of the folder the user
chose and describes each one. One level, no recursive walk, nothing outside that
folder — the same scope recovery uses, and the same reason: a session directory
is a direct child of the chosen folder, and nothing else in the user's
filesystem is ScribeKit's to enumerate.

History and recovery ask different questions and are kept apart. Recovery asks
"is there an unfinished meeting", considers only records marked `inProgress`,
and may write one thing: the interruption the user asks it to record. History
asks "what is in this folder", shows every session it can describe, and writes
nothing. They share the session layout and the record format, not a service.

The read boundary makes that structural. `HistoryStoring` has four methods —
list directories, read a record's bytes, describe a file, read a transcript —
and no method that creates, replaces, appends to or deletes anything. "Opening
History leaves every artifact byte-identical" is therefore a property of the
type, not a rule someone has to remember. `SessionRecoveryStoring` keeps its
write side because recovery legitimately writes.

The service is an actor, so filesystem work is off the main actor and one load
happens at a time. The scan is sequential rather than a task per transcript:
local storage read in order, not hundreds of concurrent reads. It runs when
asked — no timer, no watcher, no repeat scan, nothing left running afterwards.

`HistoryModel` loads when History appears, when the user presses Refresh, and
when `runtime.status.isActive` goes false, which is a meeting finishing. Each
load replaces the previous report and search index wholesale, so a session whose
folder has gone does not linger.

## History statuses

Every status a record can carry is shown: `completed`, `failed`, `interrupted`
and `inProgress`, plus `unrecorded` for a transcript with no record. An
`interrupted` row does not distinguish a meeting ScribeKit was killed during
from one whose capture ended under it, because what the row tells the user is
the same in both: the meeting was not stopped, and the transcript ends at the
last speech that reached the file.
`HistorySessionStatus` is `SessionRecoveryStatus` plus that fifth case — history
is deliberately broader than recovery, which only ever considers `inProgress`.

A failed meeting's transcript is listed like any other. ScribeKit was running and
said so at the time; hiding what reached the file would lose the only account of
what happened.

A meeting that is running appears as In Progress and its transcript is read as it
grows. That is safe with the existing writer without changing anything: the
writer only appends, takes no lock, and never rewrites what is already in the
file, so a read during a meeting sees a prefix of the finished document. No lock
is taken, no lease is held, and History cannot start, stop or touch the meeting.
`endedAt` and duration are absent for it, because nothing has written them.

Ordering is `startedAt` descending, tie-broken on directory path, so repeated
loads of the same folder produce the same list. A session with no record has no
recorded start, so it sorts on its transcript's modification date — the only
date it actually has.

## Legacy transcripts

A directory holding `transcript.md` and no `.scribekit/session.json` is listed
as a legacy meeting when the transcript carries the evidence ScribeKit wrote it:
a `#` title heading, a `**Captured by:** ScribeKit` header field, and the
`## Transcript` heading that opens the body. All three are written by
`TranscriptMarkdownFormatter.header`, so the test is deterministic and a
Markdown file the user happens to keep in the folder is not mistaken for a
meeting.

What such a session states is limited to what its transcript states: title,
source names and locale from the header, size and modification date from the
filesystem. It has no session identity, no start, no end and no duration, and
those are shown as absent rather than derived. The transcript's `**Date:**` and
`**Started:**` fields are *not* turned back into a `Date`: the clock is
twelve-hour local time with no zone in it, so reconstructing a moment would mean
guessing which zone the meeting was held in.

Recovery is unchanged by this. A session with no record is not an unfinished
meeting and never becomes a recovery candidate; history reads the same folder
without changing what recovery considers, which was verified live with a legacy
directory present.

## Transcript parsing

`TranscriptDocument.parse` reads a written transcript back into its title, its
header fields and its finalised spans. It is pure — a string in, a value out,
no filesystem — and it returns what the document says rather than a corrected
version of it.

Structure is never inferred from the shape of a line. The grammar the formatter
writes puts a `**h:mm:ss**` clock line, a blank line, then exactly one
paragraph, so the parser consumes that paragraph *positionally*, whatever it
contains, and only tests a line against a structural pattern when it is not
expecting recognised text. A sentence that reads `---`, opens with `>` or looks
like a heading therefore stays speech. The format did not have to promise that
recognised words avoid punctuation, which it cannot.

A span keeps the clock time and the minute heading exactly as written —
`10:01:33` and `10:01 AM`. No offset is derived from them: the seconds line
carries no period of its own and the heading above it does, so the pair is what
the document actually states. That is the alignment Interval 11 needs to seek a
recording, preserved rather than approximated.

Only spans become searchable text. The header block, minute headings, gap
blockquotes, the interruption notice and the footer are things ScribeKit wrote
*about* the meeting and are structure, not speech.

## Search scope and ranking

`TranscriptSearch` is plain substring matching, case-insensitive and
locale-independent. No fuzzy matching, no stemming, no embeddings, no ranking
model, no network: a query occurs in the text or it does not, and the same query
over the same folder always produces the same list in the same order.

Searched: recognised speech, the meeting title, and the captured application
names. Not searched: everything ScribeKit wrote about the meeting, so a query
for `Transcription gap`, `Captured by` or `Duration` finds nothing — otherwise
every transcript would answer to them.

Ranking is by why a session matched, in this order: exact title, title prefix,
title substring, recognised speech, source name. Within one kind: more
occurrences first, then the earliest occurrence, then the newer session, then
the directory path. Every step is a total order over facts already computed, so
there is no scoring model to tune and no tie left to chance.

An empty query is the absence of a query rather than a failed one: every session
is returned, in the order the load produced.

## Search excerpts

A transcript match carries a bounded excerpt — at most 160 characters — that is
a verbatim substring of the span it came from. The matched range is reported as
a character offset and length rather than wrapped in markup, and truncation is
reported as two booleans rather than by putting an ellipsis into the words, so
the excerpt never stops being the user's own text. The interface applies the
highlight and draws the ellipses. The excerpt keeps the span's clock time and
minute heading.

## Search index lifetime

`TranscriptSearchIndex` is built when History loads, replaced by the next load,
and never written to disk. It holds nothing that is not already in the
documents: the lower-cased ASCII bytes of each span, for the spans that are pure
ASCII.

It exists because the naive version was measured and was too slow.
`String.range(of:options:.caseInsensitive)` costs roughly 140 ms per megabyte of
transcript in a debug build, which made a keystroke cost 290 ms over 50 one-hour
meetings and 1.1 s over 200 — with everything already in memory, so it was the
comparison and not the disk. Matching folded bytes is about fifteen times
faster.

Spans holding anything outside ASCII keep no folded form and are matched through
`String.range(of:options:)` instead: ASCII folding would be the wrong answer for
them, and a byte offset would not be a character offset. A query that is itself
outside ASCII takes that path for every span, so one query is never answered by
two matchers that could disagree.

Nothing here is a second persistence system. Drop the index and the folder is
still the whole truth; rebuild it and you get the same answers.

## History sandbox behaviour

Access is owned by the service and by nothing else in history. One load takes
`SecurityScopedAccess.withAccess` on the save folder for exactly its own
duration and releases it, including on failure, so History holds no claim on the
user's folder while it is merely being looked at. The Finder and Open actions
take the same bounded access around the call.

The destination comes from the same security-scoped bookmark the meeting screen
uses, restored through `SaveLocationPersisting`. When it cannot be restored or
opened, History says so and looks nowhere else. No entitlement changed.

## History and the active meeting

History owns no meeting. `HistoryModel` never constructs a `MeetingRuntime`,
never starts or stops capture, and never attaches a transcription consumer; the
runtime is handed to `HistoryView` for one purpose, to reload the list when a
meeting finishes. Switching tabs while a meeting runs changes what is on screen
and nothing else, which is covered by tests and was verified live.

## Artifact immutability

The invariant: opening History, refreshing it, previewing a transcript and
searching leave every transcript, recording and session record byte-identical.
No line endings are normalised, no JSON is rewritten, no modification date is
touched, no index file is written beside a transcript, and no malformed record
is repaired.

Writing notes or a reviewed mark does not weaken it. Those go to
`.scribekit/derived.json` through the only boundary that can reach it, and a
filesystem test fingerprints `transcript.md`, the recording, `session.json` and
`review.json` before a save, saves notes and marks and unmarks a passage, and
expects the fingerprints — contents and modification dates — to be identical,
with `derived.json` the only file that appeared.

Enforced by the read-only store boundary, and checked two ways. A filesystem
test fingerprints every file under a save folder with SHA-256 plus its
modification date, loads twice, searches four times, and expects the
fingerprints to be identical; another proves a load adds no file to the folder.
Live, the nine files of the three Interval 9 validation sessions were hashed
before and after a full History session and were identical, modification dates
and sizes included.

## History UX

The main window is `ScribeKitRootView`, a `TabView` with two tabs, Meeting and
History. A tab bar rather than a split view or a second window: there is one
meeting and one folder of past meetings, and both tabs read the same runtime, so
nothing about the choice can affect ownership. The window's minimum size grew to
620 x 560 to fit History's two columns.

History itself is a `NavigationSplitView`. The sidebar holds a search field, the
list of meetings and a footer with the count and Refresh; the detail pane shows
the selected meeting. Each row states the title, the status as a word rather
than a colour, the date, and — when the query matched speech — the excerpt with
its match emphasised and the transcript timestamp it came from.

The detail pane states status, start, end, duration, applications, language,
transcript size, audio state and the session folder, then Show Transcript in
Finder, Open Transcript and Show Audio in Finder, then a preview of the first 50
spans. Nothing claims a capability ScribeKit lacks: there is no editor, a
session with no recording offers no audio action, and a session whose record
named a recording that is not in the folder says exactly that rather than being
shown as one that kept none.

Failures are scoped. A folder that cannot be opened replaces the list with one
sentence; a session directory that cannot be described appears in its own
bounded "Could Not Be Read" area above the list, with a message in ScribeKit's
terms rather than a Cocoa error string, and the healthy sessions still list. The
damaged sessions sit outside the selectable list because there is nothing to
select for them.

## Uncertainty signal

`SpeechTranscriber` genuinely reports confidence, and this is what was measured
before anything was designed on top of it.

`SpeechTranscriber.ResultAttributeOption.transcriptionConfidence` attaches
`AttributeScopes.SpeechAttributes.ConfidenceAttribute` — a `Double` — to the
runs of a result's attributed text. ScribeKit now requests it alongside
`.audioTimeRange`, and `AppleSpeechTranscriber.confidence(of:)` takes the
**lowest** value any run carried: the weakest word is the one a reviewer would
want to hear again, and averaging would hide it behind the words around it.

Two facts about the attribute, both observed rather than assumed, by running the
real API over synthesised speech on this Mac's en-US model:

1. **Only finalised results carry it.** A volatile hypothesis has no confidence
   attached, so a partial segment's confidence is `nil` and nothing substitutes
   a value.
2. **The values separate right from wrong.** Correctly recognised spans reported
   a lowest-word confidence of 0.60, 0.82, 0.95, 0.97 and 0.98. A span
   containing two misrecognised words ("boat hole" for "borehole") bottomed out
   at 0.14, and one containing a mis-split word ("An isotropic" for
   "Anisotropic") at 0.33. The two populations do not overlap.

`TranscriptReviewPolicy.lowConfidence` is 0.5 and sits between them;
`veryLowConfidence` is 0.25, where the clearly wrong words fell. Apple documents
no scale for the value, so it is used for those two comparisons and nothing
else — no number derived from it reaches the interface.

A second signal was tried and rejected. Counting the volatile hypotheses that
precede a final looked like "the recogniser changed its mind repeatedly", but
39 of them preceded a single 7.2-second final: the cadence is roughly five per
second, so the count measures how long a span is, not how hard it was. Shipping
it would have been a duration proxy wearing the label of uncertainty, so it is
not in the code.

What is left is two reasons, and the interface keeps them apart because they are
different kinds of claim. `lowConfidence` is the recogniser's own judgement.
`nearInterruption` is ScribeKit's observation of its own pipeline: the span is
the first one finalised after a gap the transcript already records. Priority is
a pure function of the two — low confidence that is severe or coincides with a
gap is High, low confidence alone is Medium, a gap alone is Low — and is
table-tested.

## Review metadata

`.scribekit/review.json`, beside `session.json`, schema-versioned from its first
release and probed for its version before anything else is interpreted.

It holds what review needs and nothing else: the session's identity, whether the
recogniser reported any confidence at all in this meeting, and one entry per
flagged span carrying that span's **position in the document**, its
audio-relative start and end, its confidence, and its reasons. It holds no
transcript text. The words shown for review are read back from `transcript.md`
by index, so the sidecar cannot drift from the document or become a second copy
of it, and a candidate naming a span the transcript does not have is dropped
rather than shown against the wrong words.

The index is exact rather than approximate. `MarkdownTranscriptStore` records a
candidate only after the span has actually reached the file, and numbers it by
how many spans were written before it — which is the index `TranscriptDocument`
gives that span when the file is read back.

Writing it is best effort, and deliberately so. It happens after the transcript
has been flushed and closed and before the record is updated, and a failure does
not fail the meeting: a transcript and a recording that both closed cleanly are
not thrown away over a file that only makes a later convenience possible. A
session with no sidecar has no review information, which is exactly the state
every session recorded before this interval is in, and History says so plainly.

Reading it is on the read-only side. `HistoryStoring` gained `reviewData(at:)`
and no write method; a missing, unreadable, damaged or newer-format sidecar
yields `nil` and is not even reported as a problem, because review metadata is
never load-bearing.

## Playback and the lease

`AVPlayer` over an `AVURLAsset`. The asset is read from disk as it plays, so a
multi-hour recording costs what a short one does and no part of the file is
collected in memory — the rule retention writes under, applied to reading back.
`AVPlayerItem.forwardPlaybackEndTime` stops playback at the end of the window,
so nothing has to poll a clock to know when to stop.

The seek is the offset itself. A candidate's `startTime` is seconds from the
first captured frame and a retained recording's time zero is that same frame, so
second *t* of the file is offset *t* of the transcript. The twelve-hour clock in
the Markdown is never used for this: it is a rendering of a moment, not a
position in a file. Playback begins two seconds before the span and ends 1.5
seconds after it, clamped at zero for a span near the start of a meeting.

`RetainedAudioPlayer` owns an explicit `SecurityScopedLease` for the length of
playback — the first thing in ScribeKit that holds access longer than a call.
Every exit goes through one `teardown()`: stop, failure, a new span replacing the
old one, and `deinit`. `HistoryModel` owns the player, so leaving History,
refreshing it or selecting another meeting stops playback and gives the claim
back; a view never owns it.

An M4A that was never finalised does not open, and is reported as that, with the
reason, rather than repaired. A meeting that kept no recording lists its
passages and offers no playback.

## Review UX

The detail pane gained a Review section between the actions and the transcript
preview. It states how many passages are worth a second listen and lists them in
transcript order, each with its priority word, the transcript's own timestamp,
the recognised wording verbatim, one line per reason, and playback controls.

Three empty states, kept distinct because they mean different things: a session
with no sidecar says it has no review information; a session whose recogniser
reported confidence and flagged nothing says nothing was flagged; a session
whose recogniser reported no confidence at all says that too, rather than
letting an empty list imply the recogniser was sure.

There is no transcript editing. Each candidate now carries its state — Reviewed
or Needs Review — and the button that changes it, and the section header says
how many of the meeting's passages are marked. That is the user's own
disposition and it goes to the derived sidecar; `review.json` is not touched by
it, because what the recogniser observed is not revised by someone having looked
at it.

## Source and derived artifacts

The line Interval 13 draws, and the one every later feature has to stay on:

| Source, read-only | Derived, user-owned |
| --- | --- |
| `transcript.md`, retained audio, `session.json`, `review.json` | `.scribekit/derived.json` |
| `HistoryStoring` — no method with a write side | `DerivedSessionStoring` — reads and writes one file |

`HistoryStoring` was not given a write method. Notes and reviewed marks are
writes, so they got their own protocol, and that protocol can address
`layout.derivedURL` and nothing else — a failed derived write cannot damage a
source artifact because there is no path from the type to one. `HistoryService`
still owns access for reads; `DerivedSessionService` is its counterpart for the
sidecar, an actor that opens security-scoped access for the length of one read
or one write and closes it again. Nothing in History holds a claim on the user's
folder while notes are merely being typed; the only lease that outlives a call
is still `RetainedAudioPlayer`'s, held while audio is playing.

## Derived state

`.scribekit/derived.json`, beside `session.json` and `review.json`, schema
versioned from its first release and probed for its version before anything else
is interpreted.

It holds `schemaVersion`, `sessionID`, `revision`, `notes`, `reviewedSpanIndexes`
and `updatedAt`, and nothing else. No transcript text, no confidence, no review
reasons, no audio metadata, no source names: all of that stays in the artifacts
that own it, and this file holds only what the user decided. Reviewed marks are
stored sorted and deduplicated and dates are ISO-8601, so the same state always
serialises to the same bytes.

A candidate is identified by `spanIndex` — the position `review.json` already
numbers it by, and the same index `TranscriptDocument` gives that span when the
file is read back. Nothing is identified by wording. A mark whose index no longer
names a candidate resolves to nothing: it is never shown against another
passage, and it is left in the file rather than discarded, because a sidecar that
has outlived a review record is not a licence to throw away what the user marked.

Four refusals, and each of them leaves the file exactly as it is: bytes that are
not a record, a schema version this build does not know, a `sessionID` naming
another meeting, and a `revision` that is not the one the editor loaded. A
refused sidecar disables notes and marks for that meeting and is never
overwritten. None of it is load-bearing: a meeting whose derived state cannot be
read still lists, opens, previews, searches and plays exactly as it would
otherwise, and History reports no problem for it — the detail pane says what was
found and what ScribeKit refused to do about it.

## Save and conflict semantics

Two save models, because the two actions differ. A reviewed mark is a discrete
decision and is written as it is made. Notes are typed, so they are held in
memory and written when the user presses Save — no debounce, no timer, no write
per keystroke. Marking a passage writes the notes already on disk, not the draft;
saving notes carries the marks already on disk through unchanged. Neither action
can revise the other.

"Saved" is only ever said after a write returned. A failed save leaves the draft
in the editor, leaves the loaded state alone, and shows what went wrong; nothing
is reverted and no source artifact is involved. Writes are atomic
(`Data.write(options: .atomic)`), so there is no partial `derived.json`.

The conflict policy is last-writer-refused, not last-writer-wins. Every record
carries a `revision` token, minted on each write; a save reads what is on disk
first and refuses unless its revision is the one the editor loaded — including
the case where the editor saw no file and one has since appeared. A filesystem
modification date would not do, because two writes inside the same second can
carry the same date. ScribeKit has one process and one History window, so this is
not synchronisation: it is the smallest thing that makes an interleaved or
external write a refusal with a message rather than silent data loss. There is no
locking, no merge and no CRDT, and a refused save keeps the user's text so they
can copy it out or reopen the meeting.

## Notes UX

A Notes section between Review and the transcript preview: a plain
`TextEditor` over Markdown source, a Save button that is disabled when there is
nothing to save, and one line of status — *No notes yet*, *Unsaved changes*,
*Saving…*, *Saved <date>*, or the reason the last write failed. No formatting
toolbar, no rendering, no attachments, no document management. Empty by default,
and nothing generates a word of it.

Unsaved text is discarded when the user selects another meeting, and the pane
says so rather than implying a draft is kept. A reload is not that: since
Interval 24 a rebuilt listing re-attaches derived state to whichever meeting is
still selected and carries an unsaved draft through it. A meeting with no
session record has no identity to attach derived state to and says that instead
of offering an editor.

## Logging

One subsystem, the bundle identifier, and eight categories named after
concerns rather than types: `lifecycle`, `capture`, `recognition`,
`persistence`, `audio`, `recovery`, `history`, `diagnostics`. The two loggers
that existed before, each with its own copy of the subsystem constant and a
category named after the type that printed, now read from `ScribeKitLog`.

Levels are used deliberately. `info` for milestones (start requested, meeting
active, pause and resume completed, intentional stop, finalisation and what it
was recorded as, session directory created, transcript opened, recording
opened and finalised, scan results, report written); `debug` for developer
detail (pause and resume requested, source discovery); `notice` for the
unusual but handled (an automatic recogniser restart and its result, a refused
resume); `error` for a failed operation in a controlled process; `fault` at
exactly one site, the transcription event buffer overflowing, which is a
violated invariant rather than a state a user can correct. Readiness states
are never faults.

Nothing logs per audio buffer, per partial hypothesis, per finalised span, per
UI update or per file flush. A full 695-test run — thousands of delivered
buffers — produced about 1,080 lines.

## Diagnostic privacy contract

Stated once, in `DiagnosticSafety`, and applied by everything that logs or
reports. Never emitted at all: transcript text, partial hypotheses, notes,
review passages, search queries, clipboard or file contents, audio, meeting
titles, captured application names and bundle identifiers, window titles,
absolute paths, path components, home-directory or user names, and
security-scoped bookmark bytes. `.private` is not treated as permission to log
content; content is not interpolated.

Framework error text is the one grey area. It is never what a report means: a
failure is carried as a `DiagnosticCategory` plus, in the log, the system's
own domain and code. Where such text is logged locally it passes through
`DiagnosticSafety.sanitized(_:)`, which replaces every path-shaped field with
`<path>`.

Application identity was considered and rejected. Counts are enough to answer
a support question; which applications somebody had open is the shape of their
day.

## Diagnostic report

`DiagnosticReport`, `schemaVersion` 1, pretty-printed JSON with sorted keys and
ISO 8601 dates, so two reports of one state are the same bytes. Sections:
`application`, `system`, `runtime`, `readiness`, `storage`, `recovery`,
`session`, `lastOutcome`. `readiness` and `storage` are optional and absent
when the main window has not been open in this launch — not the same claim as
unready.

Assembled from state that already exists: the runtime's own published values
and whatever the setup screen last published into `MeetingDiagnostics`. It
reads no file, opens no canonical artifact, holds no history and is never
persisted. `MeetingRuntime` gained four counters for it — `pauseCount`,
`recognitionRestartCount`, `transcriptSpanCount`, `gapCount` — reset at each
start.

Deliberately excluded, beyond the contract above: transcript and recording
byte counts, which would need security-scoped access to stat a canonical
artifact; the session's identifier and directory; the readiness rows' `detail`
sentences, which quote folders and applications; and the outcome's framework
`detail`.

The failure taxonomy is `captureAccess`, `captureDiscovery`, `captureStart`,
`captureInterrupted`, `recognitionAvailability`, `recognitionStart`,
`recognitionRestartExhausted`, `saveLocation`, `transcriptPersistence`,
`audioPersistence`, `sessionMetadata`, `recoveryMetadata`. It is for support
and reporting; the subsystems keep their own richer errors for deciding what
to do.

## Diagnostic export

Help ▸ Export Diagnostics…, plus the same action on a failed or interrupted
meeting's outcome panel after its own recovery actions. Both call
`MeetingDiagnostics.export()`. A system save panel states what a report
contains and what it does not before anything is written; cancelling writes
nothing. `DiagnosticReportWriter` is given the report and nothing else, writes
atomically, and reports a failure rather than presenting a partial file as a
success. Nothing is uploaded and no entitlement was added.

## Validation status

### Interval 25 validation

**Automated, on this Mac (macOS 26.6.2 25G83, Xcode 26.6 17F113).**

- `xcodebuild … clean test`: **703 tests in 65 suites, all passing**. The only
  three warnings are the AppIntents metadata note; no compiler warnings.
- `xcodebuild -configuration Release … build`: **BUILD SUCCEEDED**, zero
  warnings.
- `mkdocs build --strict`: passes.
- Regression inventory: every category the release depends on still has a suite
  behind it — discovery, save-location persistence, capture, the recognition
  abstraction, Markdown persistence, recovery, retention, pause/resume,
  History/search, review/playback, derived state, long-run durability,
  interruption truth, readiness and start failure, accessibility semantics,
  diagnostic privacy, and Interval 24's History-reload and unsaved-draft
  boundaries. No test was added: no release-critical path was found uncovered.

**Observed on the real system, not through a test double.**

- The **Release build launches cleanly outside the test harness**, runs as an
  ordinary application and quits cleanly from an idle state. No crash report
  was produced.
- **No network socket.** `lsof -nP -a -p <pid> -i` against the running Release
  process returns nothing at idle. The built app's entitlements are
  `app-sandbox`, `files.bookmarks.app-scope`, `files.user-selected.read-write`
  and `get-task-allow` — **there is no network client entitlement**, so the
  network policy holds as a capability rather than as a convention.
  `get-task-allow` is present because this was signed locally; a Developer ID
  export must not carry it, which is Interval 26's problem.
- **No stray handles while idle.** The idle process holds no descriptor on the
  user's save folder.
- Built product metadata: `LSMinimumSystemVersion` 26.5, `LC_BUILD_VERSION`
  `minos 26.5`, `CFBundleShortVersionString` 1.0, `CFBundleVersion` 1,
  identifier `quang.ScribeKit`.

**One release blocker found and fixed: the minimum macOS claim.** All four
build configurations set `MACOSX_DEPLOYMENT_TARGET = 26.5`, and the built
binary declares `minos 26.5`, so macOS refuses to launch it on 26.0 through
26.4. The README, `docs/getting-started/requirements.md` and
`docs/development/building.md` all said *macOS 26 or later*, which would have
shipped a release naming a floor two hundredths below the one the binary
enforces. The APIs themselves are available from 26.0, but the target was not
lowered: broadening support would be a guess without a 26.0–26.4 machine to
test on, and Part L of this interval prefers documenting the version actually
supported. The documentation now says **26.5**, which is the configured target
and the only version family the application has been run on.

**Two stale current-state claims in this file, fixed.** *Pause and resume do
not exist*, *nothing plays one* and *There is no Pause item — Pause is not
implemented* all survived from before Intervals 11, 12 and 21. `MeetingCommands`
and `MeetingMenuBarView` both offer Pause and Resume from a shared
`MeetingMenuBarPresentation`, and `RetainedAudioPlayer` plays retained audio.
The test count was also stale at 695.

**Not collected, and not simulated: every piece of human evidence this interval
was created to gather.** No person drove the application. There was therefore
no real human-driven meeting, no real transcript produced by speaking into it,
no observed Pause/Resume/Stop on a live meeting, no background/window/menu-bar
lifecycle pass, no quit-during-meeting pass, no History/review/notes workflow
by hand, no keyboard-only pass, no VoiceOver pass, and no light/dark or layout
inspection. None of it was approximated through the Accessibility API and
reported as a human pass, because that is the substitution the previous four
intervals already made and the one this interval was meant to stop making.
These remain **unresolved**, and they are why v0.1.0 is not yet a source
release candidate.

### Interval 23 validation

- Two standalone AVFoundation probes, run outside the app and then deleted:
  reopening an existing `audio.caf`/`audio.m4a` for writing truncates it to
  zero and the finished file holds only the second run; an AAC file left by a
  process that exited without releasing it (67 KB of encoded audio) is refused
  by `ExtAudioFileOpenURL`.
- `FileManager.createFile` over an existing transcript returns `true` and
  leaves the file empty. Checked in one line, not shipped as a test: nothing in
  ScribeKit calls it on a file that exists.
- Two tests added, both passing: *Reopening a session's recording replaces it
  rather than continuing it* and *A running meeting has recorded no captured
  length to continue from*.
- Full clean `xcodebuild ... test` on macOS and `mkdocs build --strict`.

### Interval 22 validation

- `xcodebuild … clean test` on macOS: 695 tests in 65 suites, all passing, no
  new compiler warnings. 37 of those tests and four suites
  (`DiagnosticReportTests`, `DiagnosticExportTests`, `DiagnosticPrivacyTests`,
  and the category and sanitisation suites beside them) are new here.
- `mkdocs build --strict`: passing.

**Observed on this Mac, from a running build.** The application was launched
and Help ▸ Export Diagnostics… driven through the macOS accessibility API to a
real save panel. What that showed:

- A report with no meeting: **1,520 bytes**, written where the panel was
  pointed. It named the real state of this Mac — three applications
  discovered, none selected, capture access granted, 30 installed recognition
  locales, a remembered save location — and contained no path, no user name,
  no title and no application name. `grep` for `/Users`, the user name,
  `file://` and `title`: nothing.
- The same export **with the main window closed** produced an equivalent
  report and the application stayed running, which is the case the process-
  lifetime owner exists for. Reopening the window afterwards worked.
- The process held **no network sockets** before, during or after an export.
- Two reports written through the real assembly path in a test process — one
  with no meeting (821 bytes) and one after a paused, resumed and stopped
  meeting (1,419 bytes) — were read by hand. The second showed 120 captured
  seconds against 180 wall seconds with one pause, which is the two-clock
  behaviour stated correctly.

**Observed in the unified log.** `log show --predicate 'subsystem ==
"quang.ScribeKit"'` over a full test run: every intended event appeared —
start requested, meeting active, pause and resume completed, intentional stop,
finalisation as completed, interrupted and failed, session directory and
transcript opened, recording opened and finalised, recogniser restart
attempted, succeeded and exhausted, capture stream ended unexpectedly, scan
results, records refused, reports written and not written. Roughly 1,080 lines
for 695 tests, and `grep` found no canary, no transcript text and no `/Users`
in any of them. The one `fault` site was not reached: nothing in the suite
overflows the transcription event buffer.

**Not done.** No live meeting was driven by hand — capture, recognition and a
real recording were exercised only through the harness, so the report's
`session` section has been seen with real numbers from doubles rather than
from a microphone-in-the-room meeting. No real disk-full or permission-revoked
failure was reproduced. The VoiceOver-with-no-mouse human pass Interval 21 left
open is still open; it needs a person, and this interval did not manufacture
one.

### Interval 21 validation

- `xcodebuild … clean test` on macOS: 658 tests in 60 suites, all passing, no
  new compiler warnings. 14 of those tests and one suite
  (`AccessibilitySemanticsTests`) are new here.
- `mkdocs build --strict`: passing.

**Observed on this Mac, from a running build.** The application was launched
and its accessibility tree, menus and window read through the macOS
accessibility API. What that showed:

- All four readiness rows reported **Ready** except **Audio source**, which
  reported **Action needed** with no application selected. Screen & System
  Audio Recording was already granted, an `en-US` model was already installed,
  and a save folder was already remembered from an earlier launch — so this is
  the satisfied path, not a clean-machine first run.
- The process held **no network sockets** for its whole run.
- The window opened at 1100×820, clamped to 620×612 when shrunk and grew to
  fill the display. Nothing is fixed-size.
- **Two defects, found and fixed here.** The readiness rows published as
  `AXUnknown` elements carrying no label and no value at all, so VoiceOver had
  nothing to say about the four things a meeting needs. And the View menu held
  only *Enter Full Screen*, so the two screens were reachable only by clicking
  the tab bar.
- **Search History** (⌘F) was verified enabled only on the History screen, and
  verified to move keyboard focus onto the search field, which publishes as an
  `AXTextField` named "Search past meetings".

**What that inspection settled about SwiftUI.** An element made a leaf with
`accessibilityElement(children: .ignore)` publishes exactly one string: given
both a label and a value, the value wins and the label never reaches the tree
at all. Every composed row therefore states everything it has to say in its
label, and `TranscriptReviewCandidate.accessibilityDescription` takes the
recognised text for the same reason. Rows built from `LabeledContent` are
unaffected — those publish a label and a value, and were already correct.

**Not observed, and not claimed.** No VoiceOver pass was driven by hand, and no
keyboard-only pass was performed by a person. No permission was denied, no disk
pulled and no model uninstalled, so every Interval 20 failure state remains
injection-only.

### Interval 20 validation

- `xcodebuild … clean test` on macOS: 644 tests in 59 suites, all passing, no
  new compiler warnings. 37 of those tests and 3 of those suites are new here,
  and one existing discovery test was rewritten for the renamed access case.
- `mkdocs build --strict`: passing.
- New deterministic coverage: `MeetingStartReadinessTests` (19 tests) over the
  derived readiness model — each blocking state, the blocking priority,
  correcting each blocker in turn, failures not outlasting their cause, and
  every row naming its status in words. `MeetingOutcomePresentationTests` (11)
  over the ending categories, including the menu bar distinguishing an
  interruption from a failure. `MeetingStartFailureTests` (7) over start
  failures: session creation, audio creation, recognition start, capture start,
  an unavailable remembered source, an unavailable speech model, and an
  interruption — each asserting the runtime holds nothing afterwards (no
  activity assertion, no open writer, no capturer), that the persisted outcome
  is truthful, and that a second start succeeds once the dependency is
  corrected.
- Not validated live: no permission was actually denied, no disk pulled and no
  speech model uninstalled on this Mac. Every readiness and failure state is
  reached through injected failures and substituted values.
- The setup screen was not driven by hand for this interval. Readiness and
  ending copy are covered by tests over the derived models rather than by a
  click-through.

### Interval 19 validation

`xcodebuild clean test` on macOS: 606 tests in 56 suites, all passing, no new
warnings.

**The lifecycle, deterministically.** `MeetingBackgroundLifecycleTests` gained
five cases over the runtime with no presentation in existence: a meeting keeps
capturing and writing while detached and a rebuilt presentation shows every
finalised span, the current partial and the capture activity with nothing
written twice; pause and resume from the menu bar with no window are shown
correctly by the next one, with captured media time carried across rather than
restarted and no second recording; Stop with no window finalises once as
`completed` and frees the next meeting; capture ending by itself with no window
still closes as `interrupted` with its artifacts finalised; and building the
presentation five times over one meeting leaves one capturer start, one
recogniser start, one recording, one activity assertion and one copy of every
span. `MainWindowPresenceTests` covers the window mechanism itself against real
`NSWindow`s: closing detaches, reopening attaches, five open/close cycles
register one pair of observations rather than one per cycle, reporting the same
window repeatedly registers nothing new, and a miniaturised window agrees with
the window rather than with the request.

**The lifecycle, measured.** Two three-minute Release `presentationCost` soaks
on the M1, each a single uninterrupted meeting split into three one-minute
phases, capturing Brave Browser with compressed retention:

| Phase | CPU, run 1 | CPU, run 2 |
|---|---|---|
| Window visible | 23.9 / 21.7 / 22.4% | 23.4 / 21.3 / 26.3% |
| Window closed (detached) | 6.7 / 6.3 / 6.7% | 7.9 / 7.2 / 6.8% |
| Window reopened | 23.8 / 28.7 / 33.5% | 29.4 / 24.8 / 23.5% |

The harness now hosts `MainPresentationScene` — the application's own scene
content — so the middle phase is the shipping lifecycle doing the detaching and
`window.close()` is the only act. It also counts the views under the window:
148 with the window open, 3 with it closed. Detached CPU lands on the ~7.1%
headless floor Interval 17 established, against the 21.1–20.7% that `orderOut`
managed. Buffers, recognised events, `transcript.md` and `audio.m4a` all
continued at the same rate through the detached phase, the meeting was never
restarted, and the run finished with 30 spans, a footer, `completed`, a 180.8 s
recording against 180.7 s of captured media and one session directory.

Reopening restores the interface and its cost. The single sample taken at the
instant of reopening read near 100% of one core — the rebuild — and the phase
around it settled back to visible cost.

**Timestamps.** `TranscriptMarkdownFormatterTests` covers 00:05:07, 11:59:59,
12:00:00, 13:28:04 and 23:59:59 for span times and for minute headings, the
header and footer pair, all four structural remarks, and one golden line
proving the recognised text either side of the timestamp is untouched.
`TranscriptDocumentTests` parses a hand-written pre-Interval-19 transcript and
gets `10:01:00` and `13:28:04` back verbatim with `10:01:00 AM` and
`13:28:04 PM` to display; a current transcript's spans state their own period
and do not borrow the heading's; and `**Ended at 1:28:04 PM**` still opens no
span. The soak's own `transcript.md` reads `**Started:** 2:16 PM`, `### 2:16 PM`
and `**2:16:16 PM**`.

### Interval 18 validation

Full suite green after `clean test`. Beyond it, three things were run for real
on an M1 MacBook Air, macOS 26, Release, with the real `SCStream`, the real
`AppleSpeechTranscriber` and the real writers.

**Capture interruption.** The semantic change was made from Interval 17's real
`didStopWithError` and validated deterministically through the runtime path —
`SCStreamDelegate` → `MeetingRuntime.handleCaptureInterruption` → artifact
finalisation → persisted status. A real interruption was not manufactured a
second time; the observed one is what the decision rests on, and the tests
state the arithmetic better than another accident would. Covered: a user Stop
records `completed`; an unexpected capture interruption records `interrupted`
while the transcript, the recording and the review sidecar all still finalise;
a recogniser that cannot be restarted still records `failed`; the next meeting
starts afterwards, with the activity assertion balanced and no writer left
open; History reads the result as Interrupted.

**Presentation cost.** Two twelve-minute three-phase `presentationCost` runs
plus two 170-second Time Profiler attachments. The profile is in
`docs/PERFORMANCE.md`: the visible cost is SwiftUI layout of the live
transcript's scroll view and the form around it, not text layout and not
ScribeKit's own code, which is under four points. Two narrow optimisations were
implemented and measured; one was nine points worse, one was inside the noise,
and both were reverted. Nothing was shipped that no measurement supported.

**Memory.** A twenty-six-minute headless run with `malloc` heap snapshots
twenty minutes apart. RSS *fell* eight megabytes over the window while the
malloc heap grew 3.9 MB, so Interval 17's monotonic RSS was a property of that
run rather than of the program. The largest grower is a framework-typed array
holding about one element per captured buffer; ScribeKit's own transcript array
grew 18 KB in twenty minutes. Nothing was released or bounded.

Not shown: any of this on Intel, under memory pressure, or over eight hours;
and no `.trace` file is committed.

### Interval 17 validation

Two things, in order: confirm Interval 16's fix from outside a test, then find
out what showing the interface costs. Full evidence and method are in
`docs/PERFORMANCE.md`; what follows is what it changed.

**The harness is committed now.** Interval 15 built one and threw it away, so
Interval 16 could not close its own fix. `Tools/SoakValidation/` is the durable
version: the real `SCStream` through the real capturer, the real on-device
recogniser, the real Markdown store and the real audio recorder, driven through
`MeetingRuntime`, sampled from inside the process every five minutes. Its
sources belong to the test target only, so nothing ships, and a run is
requested through a file the script writes into the sandbox container and
deletes afterwards — an ordinary test run and an ordinary launch reach none of
it. Measurements go beside the session directory, never into it. The two
substitutions are unchanged from Interval 15 and stated in every run's banner:
**real capture cadence, format and timing; synthetic sample values**, plus
granted rather than bookmarked folder access. No run here says a captured
application said anything.

**The crash fix is confirmed from the outside.** One continuous sixty-minute
meeting, Release build, compressed retention, ended with a normal Stop. It did
not crash: 180,205 buffers over 3,604 seconds of captured media, more than
twice the 20–26 minute band, and no new crash report on the machine. The
transcript parsed into 594 spans with its footer, the session record read
`completed`, `audio.m4a` opened at 3,604.3 s against 3,604.3 s captured, the
review sidecar was valid, and exactly one session directory existed. CPU was
flat at 7.04–7.79% throughout. This is confirmation, not proof: Interval 16's
deterministic regression remains the causal evidence, and nothing here says the
crash can never recur.

**One resource trend is open.** Footprint drifted from 91.5 MB at five minutes
to 106.3 MB at sixty — monotonic, about 0.27 MB a minute, where Interval 15's
shorter runs saw a sawtooth. What ScribeKit accumulates does not explain it:
594 spans, 73 KB of transcript and a 17.9 KB sidecar are under a megabyte
together. The rest is *inferred* to be framework caching and was not attributed,
because Instruments was again not run. It does not threaten an hour; it is worth
watching over eight.

**Showing the interface roughly triples a meeting's cost, and hiding the window
barely helps.** Measured across five runs with the setup window visible, hidden
with `orderOut`, and with its hosting view taken down: about 25% of one core
visible, about 23% hidden, and 7.2% with the view down — exactly the headless
floor. So an off-screen SwiftUI window keeps evaluating its bodies, and only
taking the hierarchy down stops the work. The rate is known too: the recogniser
publishes about 4.8 events a second, the capture summary two, the elapsed clock
one, so the interface is asked to update about 7.8 times a second and 18 points
of a core is roughly 23 ms per update.

**What that justified changing, and what it did not.** Every one of those reads
happened inside `MeetingSetupView`'s own body, so each update invalidated all
seven sections of the form. The three high-frequency readers — the elapsed
label, the capture activity line and the live transcript — now have views of
their own. It is worth about 2.4 points, repeatably, and that is all it is
worth: visible went from a 24.1–26.6% spread to 22.9–23.0%. The other fifteen
points are unattributed, no Time Profiler was run, and no further presentation
change was made on a guess. The Interval 15 lesson applies to this interval too.

**Hidden and closed remain presentation-only.** Through all three phases capture,
recognition and both durable writers carried on unchanged, no second runtime was
created, and a window opened afterwards showed the meeting still running with no
finalised span lost.

**Pause behaves as Interval 15 measured, and two more things are now known.**
Active 7.56% against paused 0.36%, both durable artifacts frozen to the byte.
Captured media time froze at 180.2 s across the pause while wall-clock elapsed
went on to 361.1 s, which is the two-clock rule holding in a real run rather
than in a test; and the recogniser's published-event count did not move at all
while paused, so the 0.36% is a recogniser that has stopped rather than one
idling. Resume restored capture and recognition. Nothing about Pause/Resume was
redesigned, and the App Nap assertion is still deliberately held through a
pause for the Interval 15 reason.

**A real `didStopWithError`, at last — and it exposes a question.** The first
sixty-minute attempt captured an application whose windows went away four and a
half minutes in, and ScreenCaptureKit reported it: *"Failed to find any displays
or windows to capture"*. This is the event Interval 15 hunted for and could not
produce. `MeetingRuntime.handleCaptureInterruption` closes the session through
`closeSession()`, whose outcome defaults to `.completed`, so `session.json`
recorded a meeting that lost its capture stream as `completed`. The durable
artifacts were fine. Nothing was changed on one observation — altering a
persisted status reaches recovery, History and the recovery screen — but the
premise Interval 15 removed has come back with evidence behind it.

### Interval 16 validation

One interval, one bug: the crash Interval 15 found and could not explain.
Diagnosis first, from the machine's own crash reports, then a deterministic
reproduction, then the smallest fix the mechanism justifies.

**What the reports actually said.** Four `EXC_BAD_ACCESS` / `SIGBUS`,
`KERN_PROTECTION_FAILURE` reports exist on the machine — one from ordinary
interactive use on 30 August, three from the measurement soaks — and all four
agree structurally: macOS 26.6.2 (25G83), the faulting thread is
`quang.ScribeKit.audio-capture`, and the faulting address is a write (ESR
`0x92000047`, WnR set) 15 to 32 bytes inside that thread's own stack guard
region. The stack pointer at the fault is 48 to 80 bytes above the base of a
544 KB stack: the thread had consumed all of it.

Interval 15 read those reports as shallow stacks and concluded the fault was
not recursion in ScribeKit. That was wrong, and the reason is worth recording.
The `.ips` format **elides recursive frames**: each report carries a
`recursionInfoArray` and an `originalLength`, and the rendered 41–48 frames
are what is left after the collapse. The real figures are `originalLength`
5,564 to 5,571 frames, with a recursion `depth` of 2,766 to 2,770 repetitions
of a two-frame cycle — a `thunk for @escaping @callee_guaranteed @Sendable
(@unowned AudioCaptureActivity) -> ()` calling itself, sitting between
`AudioCaptureActivityMonitor.publish(activity:)` and the observer
`MeetingRuntime.init` installs. Both hypotheses Interval 15 falsified were
falsified correctly; the third was never formed because the collapsed view
hid the evidence.

**The mechanism, reproduced in isolation.** The monitor held its observer as
`Mutex<(@Sendable (AudioCaptureActivity) -> Void)?>` and published with
`handler.withLock { $0 }?(activity)` — copy the function out under the lock,
call it outside, so a slow observer cannot block the delivery queue. A
function type stored as a generic container's value lives at maximal
abstraction, and copying it back out re-abstracts it; the thunk that copy
gains is left behind in the stored value. So every publish wrapped the stored
observer once more, and the next publish called through the whole chain.

A three-way comparison in a standalone program settled it: copying the
function out of the lock grew the observed call depth by two frames per
publish without bound; calling it inside the lock did not; and copying out a
*value* that holds the function did not. Only the shape ScribeKit used grows.

The arithmetic then matches every report. The monitor coalesces at 500 ms, so
publishes arrive at 2 Hz; 2,768 wrappers is 23 minutes, and 5,536 frames over
544 KB is 98 bytes a frame — the size of a two-frame thunk cycle. That is the
20–26 minute band, why it happened with and without Pause/Resume, why the
innermost frame moved from `Task.init` to `Continuation.yield` when the
main-actor hop was removed (the innermost frame is incidental; the stack is
already at its guard page by then), and why ten-minute runs never saw it. It
also explains why the fault is a *write*: the prologue of the 2,769th frame
pushing its frame pointer below the stack base.

**The fix.** The observer is now held in a value that owns its function, so
the stored closure is the one that was installed and a publish costs the same
stack on the last buffer of a meeting as on the first. Nothing else changed:
the observer is still called outside the lock, still on the delivery queue,
still coalesced at the same interval.

**Confirmation.** The regression test drives 6,000 publishes — fifty minutes
at the interval capture actually uses, comfortably past the band the crash
fell in — through the real monitor on a thread given the same 512 KB stack
ScreenCaptureKit's delivery queue has, and samples the call depth at the
first, three-thousandth and six-thousandth. Against the old monitor the depth
went 42 to 2,040 over 1,000 publishes, exactly two frames each; against the
new one all three samples are identical and the run takes 18 ms.

**Not done, and not claimed.** No 45- or 60-minute real-`SCStream` soak was
run this interval. The Interval 15 measurement harness was never committed,
and rebuilding it was out of scope here; what is proven is the mechanism, its
rate, and that it is gone — proven deterministically, at more than twice the
buffer count at which the process used to die, against the production type on
the production stack size. A real soak past 45 minutes remains the thing that
would close this from the outside. Nothing about retention changed, so the
Interval 14 artifact behaviour stands as documented; the crash that
threatened an unfinalised M4A is what was removed, not a new way of surviving
one.

### Interval 15 validation

The first real-time interval: the running subsystems under sustained
execution, measured rather than reasoned about. Full evidence, method and
limits are in `docs/PERFORMANCE.md`; what follows is what it changed.

**How it was measured.** A real `SCStream` through the real capturer, the real
on-device recogniser, the real Markdown store and the real audio recorder,
driven through `MeetingRuntime` in a Release build, sampled from inside the
process every three to five minutes. Two substitutions, both at a boundary:
the destination is the process's own temporary directory behind a granting
access double, and each real buffer's silent samples are replaced with
synthesised speech of the same frame count and format, because the machine has
no capturable application that produces speech on demand. Cadence, format and
timing are the real stream's.

**A production crash, found and still open.** Both hour-long soaks died — at
26 and 23 minutes — with `SIGBUS` against a stack guard region on
`quang.ScribeKit.audio-capture`, the delivery queue, inside the activity
handler `MeetingRuntime.init` installs. A third report with the identical chain
already existed on the machine from ordinary interactive use the day before,
with no measurement code in the stack: this is the shipped application
crashing on its own.

The handler ran on ScreenCaptureKit's delivery queue and created a
`Task { @MainActor … }` there, twice a second for the length of a meeting —
precisely what `AGENTS.md` forbids — so that was changed: the summary now
crosses through one long-lived consumer of an `AsyncStream` buffering only the
newest value, and the delivery queue creates nothing. **It did not fix the
crash.** The next soak died the same way, with the innermost frame simply
becoming `Continuation.yield` instead of `Task.init`. The fault is the delivery
thread's stack, not the operation running on it, and the captured stacks are
shallow — so it is not recursion in ScribeKit despite the label the system
gives it. A second hypothesis, that Pause/Resume caused it, was falsified the
same way: a control run with no Pause/Resume crashed at about 21 minutes. All
four occurrences fall in a band of roughly 20 to 26 minutes of continuous
capture, which is why the ten-minute retention comparisons never saw it. The change was kept as a correctness fix against the pipeline's own
rule, and is not claimed as a remedy. No further production change was made on
a guess; the one guess made was falsified by the next measurement. Full
evidence is in `docs/PERFORMANCE.md`.

**Measured behaviour.** No hour-long run completed, so the sustained figures
cover the 21–26 minutes each long run reached. CPU is flat over that stretch —
6.9/6.9/6.9% then 7.0/7.0/7.1% of one core at five, ten and fifteen minutes
with compressed retention, on an eight-core M1.
Resident footprint oscillates between roughly 78 and 93 MB and does not track
meeting length. Thermal state was nominal at every sample. Threads settle from
13–14 to 11–12 after Stop. Retention costs, ten minutes each under equivalent
load: no audio 4.8%, raw CAF 5.6% growing ~11 MB/min, compressed M4A 6.7%
growing ~0.47 MB/min — AAC is the most expensive option and produces a file
about 23× smaller. Nothing drifted within any run.

**Pause.** Active 6.9% against paused 0.4%, threads 14 to 9, and both durable
artifacts frozen to the byte across a three-minute pause. There is no polling
loop keeping work alive. The elapsed clock keeps advancing, which is right:
elapsed time is wall-clock and does not stop when capture does.

**Decisions this interval settled.**

1. *The restart budget resets at an explicit Resume.* The bound exists to stop
   a recogniser recovering from itself forever unnoticed; a Resume is a person
   deciding to carry on, and it has just proved the recogniser starts. The
   budget is therefore per capture run rather than per meeting. It stays
   bounded — a run still self-restarts at most `maximumRecoveryAttempts` times,
   and only a person can reset that, so no automatic path is unbounded.
2. *The App Nap assertion is held through a pause, deliberately.* Nothing is
   captured or recognised then, so it is not buying throughput. It is buying
   the process's life: `beginActivity` also opts out of sudden termination, and
   a pause is exactly when ScribeKit holds an open, unfinalised recording that
   Interval 14 showed is unreadable if the process dies first.
3. *Capture-end status is unchanged, for a measured reason.* See below.

**ScreenCaptureKit does not report a captured application quitting.** Asked
with the real framework — capture TextEdit alone, quit it, watch. It vanished
from `SCShareableContent.applications` between samples, and the stream
delivered no error, no `didStopWithError`, no observable content change, and
kept producing buffers at an unchanged ~51 per second for the remaining 45
seconds. There is no signal. ScribeKit does not act on this on purpose: the
only available inference is silence, and silence is not death — a meeting where
nobody is speaking looks identical, so the heuristic would end quiet meetings.

This also settles the capture-end question Interval 14 left open, by removing
its premise. The event most likely to end capture unexpectedly never reaches
`handleCaptureInterruption`, so there is no observed unexpected capture end to
reason from. Changing a persisted status enum on unobserved semantics would be
the speculative change the evidence does not support; `completed` stands until
a real `didStopWithError` has been seen.

**Not validated, and not claimed.** No interface was measured: the measured
process runs no window, so every figure above is a meeting's cost with
presentation at zero, and the visible/hidden/closed comparison was not
obtained. No Instruments profiling was run — the crash came from the system's
own reports and the rest from process-level sampling, so time spent inside
Apple's recogniser is not attributed. Energy was not observed through a power
trace. One machine, one locale, ten-minute retention comparisons.

### Interval 14 validation

A falsification pass: long logical runs and deliberate faults at every seam a
meeting depends on, run against the real coordination code through doubles, and
against the real writers and container formats on disk. Four production defects
were found and fixed. Everything below states which kind of evidence it is.

**Tested by deterministic injection.** `ReliabilityHarness` drives one
`MeetingRuntime` over the four existing doubles with both clocks under the
test's control: buffers arrive through the capturer's own delivery path, so the
media clock, the activity monitor, the recogniser's input and the retainer see
them in order; recognition events are published the way a run publishes them;
and every failure is armed on the double that would really have failed. No
disk, no permission, no sleeping.

- A two-hour meeting: 7 200 s of captured media, 240 finalised spans, 23
  Pause/Resume cycles, one recogniser self-restart in the middle, normal Stop.
  Offsets strictly increasing and equal to the media time each span was
  recognised at; pause and resume markers monotonic in captured time; one
  session directory, one transcript, one recording; the recording holding
  exactly 7 200 s of frames and not one of synthetic pause silence; the footer
  told the same captured duration the media clock held; final state
  `completed`; the activity assertion released.
- 25 sequential meetings in one process, some with Pause/Resume, one with a
  recogniser restart: each returned to a terminal state, closed its transcript
  and recording, released the assertion, and left 25 distinct session
  directories with nothing carried between them.
- Fault matrices: transcript failure at an append, a gap, a pause marker, a
  resume marker and the footer; retained-audio failure at creation, mid-write
  and finalisation; a start that fails at recognition and at capture; capture
  ending by itself; a resume whose source has gone away and then comes back.
- Recogniser restarts: offset continuity across a restart, no duplicated or
  lost durable text, the restart limit enforced, and both terminal cases — the
  limit reached, and a restart that cannot start recognition again.

**Observed against the real framework.** `LongRunDurabilityTests` uses the real
`MarkdownTranscriptStore`, `FileManager`, `FileHandle`, `RetainedAudioRecorder`
and `AVAudioFile` against files in a temporary directory.

- Three two-hour transcripts written and closed in one process: 2 400 spans
  each, every one parsed back by `TranscriptDocument` in the order it was
  written, with the footer and the captured duration present, and three
  distinct session directories.
- A recording copied while its writer was still open — the bytes a killed
  process leaves behind — reopened with `AVAudioFile`. A CAF holds its frames
  as they are written and the copy opens and reads; an unfinalised M4A does
  not, which is the documented limitation, now checked against the framework
  rather than asserted. The closed file reads fully in both cases.
- Twenty recordings written and finalised in one process each hold exactly the
  frames they were given, with nothing carried over between them.

**Defects found and fixed.**

1. *A recogniser restart reset the transcript's timeline.* A restarted run
   counts its offsets from its own first frame; `mediaOffsetBase` was updated
   at a pause but never at a self-restart, so every span after a mid-meeting
   restart was written at a position near the start of the meeting. Offsets
   went backwards, the wall-clock timestamps derived from them went backwards,
   and review playback would have sought to the wrong second of the recording.
   The base is now scheduled at the handled-event count a drain would have
   waited for, because a restart happens inside the handler for the event that
   caused it and cannot wait for itself; an event the old run published on its
   way out therefore keeps the old run's base.
2. *A recogniser that could not be brought back left everything running.* The
   run was reported as failed and nothing else happened: capture kept running,
   the transcript and recording stayed open, the App Nap assertion stayed held,
   the transcript recorded nothing about the untranscribed stretch, and because
   the runtime still counted the meeting as active, no further meeting could be
   started in that process. It now ends the meeting the way every other
   terminal subsystem failure does.
3. *A failed start was recorded as a completed meeting.* A start that could not
   begin recognition or capture closed its transcript with
   `SessionCompletionOutcome.completed`, so History listed an empty transcript
   under the status a meeting that ran and finished gets — contradicting what
   this document already said the start path did. It is recorded as `failed`.
4. *A pause whose marker failed leaked the recording.* The transcript failure
   ended the meeting, but the teardown was guarded on `canStop`, and at a pause
   boundary capture and recognition have already stopped; the recording's
   writer was never closed, the assertion never released, and `isRunning`
   stayed true for the life of the process. The recording is now finalised on
   that path too.

**Measurements.** Debug build, Xcode 26.6 (17F113), macOS 26.6.2, MacBookAir10,1
(Apple M1), `clean test`: 552 tests in 53 suites, 5.7 s. The accelerated runs
say nothing about CPU, memory, App Nap or thermals; they are evidence about
ordering, arithmetic, state and release. Process-wide file-descriptor counting
was tried as leak evidence and abandoned: the test runner runs suites in
parallel, so the count moves for reasons that have nothing to do with the code
under test. Writer and lease lifetime are asserted at the double layer instead,
where an unclosed writer is observable directly.

**Not validated this interval, and not claimed.** No real-time soak of the
running application, no ScreenCaptureKit source-disappearance observation, no
abrupt `kill -9` of the app followed by relaunch discovery, and no
background/closed-window continuation check: all four need the application
driven by hand with screen-recording permission and a save folder chosen in a
system panel. The recorder work above approximates process death by reading the
bytes on disk while the writer is open, which is faithful to what a killed
process leaves but does not exercise relaunch discovery.

### Interval 13 validation

Focused, on a synthetic session folder written by the real formatter and the
real record and review encoders: a transcript with two spans, a 4 KB recording,
`session.json` and a `review.json` with two candidates. The four source files
were SHA-256'd before anything was written.

The sequence, driven through the same types the pane drives — `HistoryService`
for the listing, `DerivedSessionModel` over `DerivedSessionService` and the real
`FileManagerDerivedSessionStore` for the writes:

1. The meeting listed as Completed with both candidates resolved to spans.
2. The second passage was marked Reviewed.
3. A fresh model reopened the meeting: the mark was there, and the other
   candidate was still unmarked.
4. It was marked Unreviewed and stayed that way across another reopen.
5. Notes of five lines containing `#`, `**bold**`, `*italic*`, a backticked
   command, a `- [ ]` and a blockquote were typed. The pane said *Unsaved
   changes*; after Save it said *Saved*, and a third model read back the text
   byte for byte, including both trailing newlines.
6. Editing again returned it to *Unsaved changes*, and saving again to *Saved*.
7. All four source hashes were identical to the ones taken at the start, and
   `.scribekit/` held exactly `derived.json`, `review.json` and `session.json`.
8. Security-scoped access was balanced: seven starts, seven stops, none left
   open.
9. `derived.json` was then replaced with `{ broken`. The meeting still listed,
   the notes area refused to open, a save attempt wrote nothing, the damaged
   bytes were preserved exactly, and the source hashes were still identical.

No network call is possible from any of this: the derived types touch
`Foundation` and the filesystem only.

### Interval 12 validation

Focused, on synthesised speech, with no microphone and no meeting audio. A
harness drove the real pipeline with ScreenCaptureKit replaced and nothing
else: two phrases synthesised in process with `AVSpeechSynthesizer`, converted
to the 48 kHz mono float32 the capturer delivers, chunked into 20 ms buffers
and handed to the real `AppleSpeechTranscriber`, the real `RetainedAudioRecorder`
and the real `MarkdownTranscriptStore`. Phrase A, Pause, 25 s paused, Resume,
phrase B, Stop. Run once for `.raw` and once for `.compressed`.

Both runs:

1. One session directory, and in it `transcript.md`, one audio file and
   `.scribekit/` — nothing reopened, nothing duplicated.
2. The transcript and the audio file stopped growing at the pause and had not
   changed 25 s later (314 bytes and 464,896 bytes for CAF; 88,144 for M4A).
3. The document read, in order: phrase A at 6:08:31,
   `> **Paused:** 6:08:36`, `> **Resumed:** 6:09:01, after 25 s paused`, a new
   `### 6:09 PM` minute heading, and phrase B at **6:09:01** — the wall clock
   after the real pause, not 6:08:38. Footer: `**Duration:** 36 s`,
   `**Captured:** 5 s`.
4. The recording was 4.94 s, equal to the captured clock to within 2×10⁻¹⁴ s,
   and contained none of the 25 s pause.
5. Phrase B was written at media offsets 2.42–4.94 s. That stretch of the
   recording was extracted and transcribed **independently**, and came back as
   the same sentence — so a post-resume offset still seeks to its own audio.
6. No duplicate speech, no offset reset, and Stop closed the recording, the
   transcript and the lease.

`audio.m4a` survived the pause with its writer left open and finalised cleanly
at Stop: `AVURLAsset` reported its duration and `AVAudioFile` read it back.
Nothing reopens or segments the container.

**Not done.** The interface was not driven by hand: the Pause and Resume
controls in the window and the menu bar are covered by unit tests and by
`MeetingMenuBarPresentation`, not by a click-through. No live ScreenCaptureKit
meeting was recorded for this interval.

**Networking and sandbox.** Unchanged. The entitlements file was not touched,
nothing added here references `URLSession`, `Network` or any socket API, and no
dependency was added.

### Interval 11 validation

Focused, on synthetic speech, with no microphone and no meeting audio.

**The signal.** A standalone program built against the real Speech framework ran
`SpeechAnalyzer` with a `SpeechTranscriber` over speech synthesised by `say`,
with `.transcriptionConfidence` requested. It reported per-word confidences on
finalised results and none at all on volatile ones. Two runs: five ordinary
sentences gave lowest-word confidences of 0.60, 0.82, 0.95, 0.97 and 0.98, all
correctly recognised; a sentence with two hard words gave 0.14 for "boat hole"
(spoken: "borehole") and 0.33 for "isotropic" (spoken: "anisotropic"). This is
what the thresholds are set from.

**End to end.** A harness drove the real pipeline with ScreenCaptureKit replaced
and nothing else: speech synthesised in process with `AVSpeechSynthesizer`,
converted to the 48 kHz mono float32 the capturer delivers, chunked into 20 ms
buffers and handed to the real `AppleSpeechTranscriber` and the real
`RetainedAudioRecorder` together, with the real `MarkdownTranscriptStore`
writing the transcript and the sidecar, and the real `HistoryService` reading it
back.

1. The recogniser finalised the passage with a confidence of 0.107 and the
   wording "Isotropic diffusion smoothed the butter hole telemetry." — a genuine
   misrecognition. The sidecar carried one candidate, span 0, priority High,
   reason `lowConfidence`, offsets 4.24–7.23 s.
2. History read it back with the recognised wording byte-identical to the
   transcript's, the timestamp the document states, and the reason attached.
3. The playback plan seeked to 2.24–8.73 s. That stretch of `audio.caf` was
   then extracted and transcribed **independently**, and came back as exactly
   the flagged wording — so the seek lands on the passage rather than near it.
4. `RetainedAudioPlayer` reached `playing`, `stop()` returned it to `idle`, and
   the injected access double showed every start balanced by a stop. The
   transcript's SHA-256 was identical before and after review and playback.

**Memory.** The process footprint grew 5.4 MB while a 1.4 MB recording played,
which is `AVPlayer`'s own machinery rather than the file. This is a sanity
check, not a proof of streaming: the recording was small enough that loading it
whole would not have shown. Streaming rests on `AVURLAsset` being file-backed.

**Networking.** Unchanged and unchecked-by-need: the app still carries no
`com.apple.security.network.client` entitlement, and nothing added in this
interval references `URLSession`, `Network` or any socket API. The entitlements
file was not touched.

**Not done.** The interface itself was not driven by hand: the Review section,
its three empty states and its controls are covered by the unit tests and by the
model, not by a click-through. No live ScreenCaptureKit meeting was recorded for
this interval, so the flagged passage came from synthesised speech fed to the
same entry point capture uses rather than from audio a Mac played.

`xcodebuild ... clean test` passes on Xcode 26.6: **463 tests in 44 suites**, no
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

### Interval 10 live validation

Run against `~/Documents/ScribeKitValidation`, the three completed sessions
Interval 9 left, with three scenario directories added for the run and removed
afterwards: a copy of a real transcript with no session record, a directory with
a truncated `session.json`, and a directory holding a shopping list called
`transcript.md`.

- **History lists the folder.** Three real completed sessions, newest first,
  each with its recorded status, times and sizes. The audio sizes shown —
  67,276 and 2,391,327 bytes — match the files on disk exactly.
- **Search.** Typing `menu` narrowed three meetings to one and showed
  `The **menu** bar item shows the meeting title and the elapsed time, stopping
  from the menu bar finishes the transcript and the audio file.` at
  `10:56:34 AM · 24 matches`. That is the exact wording at that exact timestamp
  in the file, and the two sessions with header-only transcripts correctly did
  not match. Clearing the field returned all three.
- **Detail.** The 10:56 session's preview reproduced its spans and timestamps
  verbatim.
- **Legacy.** The record-less copy listed as `Legacy` with "Transcript last
  written", no start, end or duration, its header's applications and language,
  "No audio file beside the transcript", and **no** Show Audio in Finder button.
- **Damaged.** The truncated record appeared under "Could Not Be Read" with
  "This meeting's session record is damaged and was left untouched. Its
  transcript is unaffected." The other four meetings listed normally.
- **Not a meeting.** The shopping list was not listed, and produced no problem
  row.
- **Recovery unchanged.** With the legacy directory present, the meeting screen
  still offered it as nothing: only the damaged record was reported, and no
  record-less session became a recovery candidate.
- **Finder actions.** Show Transcript in Finder revealed `transcript.md` in the
  legacy session's folder; Show Audio in Finder revealed
  `2026-08-30-untitled-meeting/audio.m4a`.
- **A meeting during History.** A new `History Validation` meeting captured
  QuickTime Player playing the synthetic validation speech. Switching to History
  while it ran left it running: the transcript grew 810 → 1208 → 1715 bytes
  across the switch and the refresh, the menu bar still read
  `History Validation · Transcribing · 02:08`, and History listed the meeting as
  `In Progress` with no end time and read its transcript live.
- **Stop and refresh.** Stop Meeting from the menu bar closed it normally —
  `status: completed`, `endedAt`, footer `Duration: 2 min 18 s`, audio closed at
  1,142,181 bytes. History refreshed itself when the meeting finished, without a
  manual Refresh: the row changed to `Completed` and gained its end time and
  duration.
- **Immutability.** The nine files of the three Interval 9 sessions were hashed
  with SHA-256 before the run and after all of the above: identical, with
  identical modification dates and sizes.

### Interval 10 performance

Measured on this Mac in a debug build (`@testable` requires one; the release
configuration cannot host these tests), over synthetic one-hour meetings of 240
spans each, loading from a real temporary folder:

| Sessions | Spans | Transcript bytes | Load + index | Search | Memory |
| --- | --- | --- | --- | --- | --- |
| 50 | 12,001 | 2.0 MB | 0.21 s | 25–39 ms | +5 MB |
| 200 | 48,001 | 7.9 MB | 0.82 s | 100–160 ms | +17 MB |
| 500 | 120,001 | 19.9 MB | 2.05 s | 250–390 ms | +36 MB |

Search covers four queries: a phrase in one meeting, a phrase in all of them, a
title fragment, and one that matches nothing; the range is across those. An
empty query costs well under a millisecond at every size, because it returns the
sessions without touching text.

Memory is about 1.8 times the transcript's own size, which is the text plus its
folded copy, and it is bounded by the folder rather than by how long History
stays open.

The trigger for an on-disk index: a folder where a load exceeds a second or a
query exceeds about 100 ms in a release build. That is somewhere past 200
one-hour meetings on this hardware. At that point the answer is SQLite FTS5 over
the same spans, rebuilt from the Markdown and still disposable — not a change of
where the truth lives.

### Interval 9 live validation

Driven through the real sandboxed app, with the interface operated by scripted
accessibility actions and keyboard events. QuickTime Player played a
`say`-generated 4 min 41 s recording as the only selected source, retention set
to Compressed, writing to `~/Documents/ScribeKitValidation` chosen in the open
panel. That folder and the source recording were left in place; nothing from
either is in the repository.

- **Hide.** A meeting ran with the window visible, then ScribeKit was hidden
  with ⌘H for 60 s (`AXVisible` confirmed `false`). `transcript.md` grew from
  2 270 to 3 466 bytes and `audio.m4a` from 943 518 to 1 426 852 bytes across
  that window. Nothing about the meeting's state changed.
- **Menu bar while hidden.** The menu read `Background Validation`,
  `Transcribing · 03:08`, `Capturing QuickTime Player`, `Keeping compressed
  audio`, then Stop Meeting, Show Transcript in Finder, Show Audio in Finder,
  Open ScribeKit, Quit ScribeKit. The elapsed time advanced between openings.
- **Reopen.** Open ScribeKit from the menu bar unhid the app and brought back
  one window showing the same meeting: "Capturing 1 application(s)",
  "Transcribing on device", 10 805 buffers / 216.1 s, the transcript file path,
  Start Meeting disabled, and the segments recognised while it was hidden.
- **Close the window.** ⌘W left the process running and the meeting under way;
  `transcript.md` grew from 4 785 to 5 623 bytes and `audio.m4a` from 1 901 837
  to 2 219 342 bytes over the next 40 s, with the menu bar still reporting
  `Transcribing · 04:38`.
- **Reopen repeatedly.** Open ScribeKit invoked four times in a row produced
  one window and one frontmost application every time.
- **Stop from the menu bar.** The transcript closed with `**Ended:** 11:01 AM`
  and `**Duration:** 4 min 58 s`; the record read `"status" : "completed"` with
  an `endedAt`; `audio.m4a` finalised at 2 391 327 bytes and `afinfo` read it
  as AAC 62.6 kbit/s, 1 ch, 48 000 Hz, `estimated duration: 297.64 sec`. The
  menu collapsed to `Meeting finished` with the two Finder items and no Stop.
  `lsof` on the process listed no handle under the save folder and no sockets.
- **Quit during a meeting.** A second meeting was started and Quit chosen from
  the menu bar. The alert appeared as specified. *Cancel* left the process
  alive with the meeting still transcribing and the record still `inProgress`.
  Quitting again and choosing *Stop Meeting and Quit* exited the process with
  `"status" : "completed"`, an `**Ended:**`/`**Duration:** 42 s` footer, and a
  readable `audio.m4a` of 41.88 s.
- **Relaunch.** No Previous Meetings section (all three sessions completed), no
  file written to the save folder, 0.82 s of CPU at launch — nothing captures
  itself on launch. The remembered application selection was restored.
- The macOS screen-capture indicator was visible in the menu bar for the whole
  of every meeting, hidden window or not.

### Interval 9 background measurements

One Debug build, one Mac, one meeting, 20-second sampling windows of process
CPU time and RSS. Rough, not a benchmark; Interval 12 is where measurement
becomes formal.

| Phase | CPU per 20 s | RSS |
| --- | --- | --- |
| Window visible and frontmost | ~4.1 s (≈20% of a core) | 129–146 MB |
| Application hidden (⌘H) | ~4.5 s | 153–154 MB |
| Window closed | ~3.5 s | 145 MB |

The qualitative result the interval asked for holds: capture and transcription
work continues unchanged with no window, and closing the window lowers total
process CPU by roughly 15%. The hidden phase reading slightly above the visible
one is not a real increase — speech density varies across the recording and the
visible phase was sampled while screenshots were being taken — so the honest
statement is that hiding does not reduce the work and closing does. Memory
stayed inside a 25 MB band across a five-minute meeting with no upward trend,
and returned to 146 MB after Stop.

No live failure was reproduced while the window was hidden. Quitting the
captured application does not end the ScreenCaptureKit stream — it keeps
delivering silence, which is the documented Interval 4 behaviour — so there was
no controlled way to fail a hidden meeting without injecting one. The failure
paths are covered by injected failures in unit tests, including the assertion
that a failure raised with nothing observing it is still there when a window is
opened.

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

- **No recorded VoiceOver or keyboard-only pass.** The accessibility tree of a
  running build was read through the accessibility API and the strings under it
  are covered by tests, but nobody has listened to VoiceOver read setup, an
  active meeting and History, or worked a meeting through without a mouse.
  ScribeKit claims no conformance to any accessibility standard.
- **Refusal is still injection-only.** Every Interval 20 blocked and failed
  state — denied capture access, a missing speech model, an unreachable save
  folder, a failed transcript or recording — has only ever been produced by an
  injected failure. The Mac these were checked on satisfied every prerequisite.
- **The tab bar is not in the Tab-key order.** ⌘1 and ⌘2 are the keyboard route
  between the two screens.
- **The Help menu is empty.** The default *ScribeKit Help* item reports that
  help is unavailable, so it was removed rather than left as a control that
  does nothing. Linking to the documentation site was deliberately not added:
  ScribeKit has no network entitlement and opens no external links, and adding
  the first one for a menu item was not worth the change in posture.
- **The restart budget is per meeting, not per recognition run.** Two
  self-restarts are all a meeting gets, however many hours and however many
  resumes it spans, and an explicit Resume does not give it more. That is a
  deliberate ceiling on a recogniser that keeps failing rather than a measured
  number, and raising it to make a test pass would be the wrong reason to.
- **Reopening the window costs a rebuild.** The interface is built from
  nothing, so reopening spends a burst of CPU laying out a transcript that may
  be hours long, and a long meeting's list costs more to rebuild than a short
  one's. Measured as a single sample near 100% of one core, gone by the next
  twenty-second window. Nobody has yet reopened a window during an eight-hour
  meeting to see how large that burst gets.
- **Miniaturising detaches too.** A miniaturised window is not visible, so it
  is treated exactly like a closed one. That is deliberate — nothing is on
  screen to lay out — but it means deminiaturising pays the same rebuild.
- **Accelerated runs are not real-time evidence.** The two-hour meeting above
  costs a second, because nothing sleeps and no audio is synthesised. It proves
  ordering, arithmetic and release; it proves nothing about CPU, memory under a
  real recogniser, App Nap or thermals.
- Notes are not searchable. `TranscriptSearchIndex` is built from transcripts
  and session metadata, and derived state is deliberately not in it: mixing
  user-written text into transcript matches would need its own ranking and its
  own way of showing where a hit came from, and neither was worth building
  before the notes exist to search.
- Unsaved notes do not survive leaving a meeting. The draft lives in
  `DerivedSessionModel`, and selecting another meeting or reloading History
  clears it. The pane says so; a persisted draft is a second unsaved artifact
  and was not worth one.
- Derived state needs a recorded session identity, so a legacy transcript with
  no `session.json` cannot have notes or marks. Attaching them to a directory
  path instead would break the moment a folder was renamed.
- The conflict check is a revision token compared immediately before the write,
  not a lock. Two writers interleaving between that check and the atomic
  replace is possible in principle; with one process and one History window it
  is not reachable in practice, and the failure mode would be a lost derived
  edit, never a damaged source artifact.

- **Readiness is a snapshot, not a subscription.** Nothing polls for a
  permission, a disk or a model to change; the user presses Refresh, Try Again
  or Check Again. That is deliberate — the alternative is a timer for a state
  that changes once a month — but it means a granted permission is not noticed
  on its own.
- **There is no System Settings deep link.** macOS exposes no supported API for
  opening a specific privacy pane, and the `x-apple.systempreferences:` scheme
  is undocumented, so the path is named in words instead. This is the one place
  this interval chose an honest instruction over a convenient button.
- **A permission never asked for and one refused are indistinguishable.**
  `CGPreflightScreenCaptureAccess` answers whether access exists, not why, and
  the copy says only that.
- **`didCaptureAudio` is a flag, not a measurement.** It records that capture
  reached `.capturing`, which is what separates a start failure from a meeting
  that ran. A meeting that captured no audio despite starting is still
  described as a meeting that ran, because it was.
- **Source disappearance during a running capture is unchanged.** ScreenCaptureKit
  may emit no actionable signal, ScribeKit uses no silence heuristic and
  replaces nothing automatically. This interval deliberately did not touch it.

- Interval 2, 3 and 4 limitations still hold.
- **A pause is a cut in the recording, not a silence in it.** The file holds
  captured audio only, so the resume is audible as a join and the recording
  alone does not say how long the pause lasted. The transcript does.
- **`**Duration:**` and `**Captured:**` are different measurements.** The first
  is the meeting's wall-clock length, the second the recording's; neither is
  derived from the other, and only a paused meeting states both.
- **The media-offset base is read from captured frames, not from the
  recogniser's own clock.** `TranscriptionAudioInput` does not advance its
  elapsed clock for a buffer whose conversion fails, so a conversion failure
  would slide the base and the recogniser's run-local offsets apart by the
  length of the buffers it lost. This is the Interval 8 edge, unchanged in
  kind; no conversion has ever failed here.
- **A resume that fails is reported but not retried automatically.** The
  meeting stays paused and the user retries it. Nothing watches for the source
  to come back.
- **Crash recovery still does not resume.** A meeting that was paused when
  ScribeKit stopped is detectable and honestly described, and that is all: the
  next launch offers to mark it interrupted, exactly as for any other
  unfinished session.
- **Confidence has no documented scale, so the thresholds are empirical.** They
  separate cleanly on this Mac's en-US model over synthesised speech. Another
  locale, another model, or real speech over a real meeting's audio may sit
  differently, and nothing has measured that.
- **A flagged passage is a whole finalised span.** Confidence is per word, and
  the lowest one flags the span it is in, so review points at the sentence
  rather than at the word inside it. The reviewer hears the sentence.
- **Review information is only as good as the sidecar.** A meeting killed before
  it finished writes none, because the sidecar is written when the session
  closes; a meeting whose sidecar write failed has none either, and neither
  failure is surfaced anywhere except as the absence History states.
- **There is no reviewed state.** A passage cannot be marked as dealt with,
  because History has no write side and this interval did not open one.
- **There is no correction.** Review shows and plays; it never proposes,
  replaces or edits a word, and `transcript.md` has no editor.
- **Older sessions have no review information and no precise seek.** A session
  recorded before this interval has no sidecar, so it has no candidates and
  nothing offers to seek into its recording. No offset is reconstructed for one.
- **Playback stops at the end of the window, not at the end of the recording.**
  There is no scrubber, no waveform, no continuous listening and no way to play
  a meeting from the top; the controls exist to hear one passage.
- **A recording that will not open is reported and left.** ScribeKit does not
  repair a truncated MPEG-4 container, and says so rather than failing silently.
- **Playback was proved on short files.** Streaming rests on `AVURLAsset` being
  file-backed rather than on a measurement over a multi-hour recording.
- **The Review interface was not driven by hand.** It is covered by tests and by
  the end-to-end harness described above, not by a click-through of the app.
- **History lists one folder, one level deep.** The save folder the user chose,
  its immediate children, and nothing else. A session moved out of it is gone
  from history; so is every session in a folder the user has since replaced.
- **No filesystem watcher.** History reads on appear, on Refresh and when a
  meeting finishes. A session added by something else while History is open
  appears at the next refresh.
- **Search is substring matching, and nothing more.** No stemming, so `closures`
  does not find `closure`; no fuzzy matching, so a recogniser's misheard word is
  found only by searching what it actually wrote; no phrase matching across two
  finalised spans, because a span is the unit the file stores.
- **Search cannot find ScribeKit's own writing**, by design. The header, minute
  headings, gap markers, the interruption notice and the footer are not
  searchable text; titles and application names are searched as metadata.
- **Whole transcripts live in memory while History is open.** Roughly 1.8 times
  the transcript bytes, bounded by the folder. Comfortable to 200 one-hour
  meetings on this Mac; past that an on-disk index is the answer, and the
  threshold is recorded above.
- **A legacy session states less than it looks like it could.** Its transcript
  names a date and a start time, but in a twelve-hour local clock with no zone,
  so no `Date` is reconstructed from it. It sorts on its transcript's
  modification date, which changes if the file is copied.
- **A session ScribeKit cannot describe is named by its folder and nothing
  else.** A damaged, unreadable or newer-format record is reported and left
  exactly as it is; history does not fall back to reading the transcript beside
  it as a legacy session, because a record that exists is evidence that should
  be read, not routed around.
- **History is read-only.** No rename, no delete, no export, no editing, no
  tags and no folders. The files are the user's to manage.
- **Playback is for review and nothing else.** History plays the stretch of a
  recording around a flagged passage. It offers no way to play a meeting from
  the top, no scrubber and no waveform, and it still never decodes a recording
  merely to list it.
- **Pause and resume work within one process only.** Interval 12 implemented
  them — see *Pause and resume* above — by keeping one file with one time
  origin and letting captured media time stop while wall-clock time does not.
  Nothing carries that across a process: a meeting that was paused when
  ScribeKit stopped is offered for recovery, not for resumption.
- No throttling boundary exists between the runtime and the interface. A closed
  window renders nothing because its scene is gone; a merely hidden one is
  still evaluated by SwiftUI, and the measurement that would justify building a
  coalescing layer was not there. A long meeting with a hidden window has not
  been profiled for view work specifically.
- The App Nap assertion is justified by Apple's documented semantics, not by an
  observed throttle on this Mac. Nothing measured a hidden meeting being slowed
  down; the assertion exists so that it cannot be.
- Quitting during a meeting waits for the stop with no timeout. Every step is
  bounded, so this has always returned promptly, but a wedged filesystem would
  hold termination rather than abandoning a half-closed transcript.
- ScribeKit stays running when its last window closes, including with no
  meeting. That is deliberate for a menu bar application, but it means the app
  has to be quit explicitly.
- The menu bar item is compact by choice: it shows one meeting and offers Stop.
  It is not a second interface, and there is no way to start or configure a
  meeting from it.
- Elapsed time is wall-clock time since the meeting started. It is not audio
  time, and it does not subtract gaps.
- A live runtime failure with the window hidden was not reproduced; the path is
  covered by injected failures in unit tests.
- Background CPU and memory were sampled on one Mac in a Debug build over
  20-second windows in a single five-minute meeting. No multi-hour hidden run
  has been measured, and no battery claim is made.
- Retention writes audio, and playback plays one flagged passage of it. There
  is still no waveform and no scrubber, and a whole recording is played in
  another application.
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
  resumes capture or recognition, and continuing into the same session is not
  a later interval any more: Interval 23 investigated it and decided against it
  for v0.1.0, for the reasons in *Interrupted-session continuation* above. The
  answer to an interrupted meeting is to keep it and start a new one.
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
- The record's `interruptedAt` is when ScribeKit noticed. For a session found
  after a relaunch that is not when the meeting stopped, because nothing
  observes the second; for a capture stream that ended while ScribeKit was
  running, the two are the same moment and it is recorded.
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
- Stopping waits up to two seconds when the recogniser's results sequence does
  not end on its own, which happens when a run received no audio at all.
- Memory and CPU were observed, not benchmarked; formal energy measurement is
  a later interval.
- Dropping audio under backpressure has never happened on this machine, so the
  policy is proved by unit tests rather than by a live overload.

- **A diagnostic report is a snapshot, not a history.** It says nothing about
  a meeting before the last one and nothing about a previous launch beyond what an
  unfinished-session scan found. Building a durable event journal was
  deliberately not done.
- **`readiness` and `storage` are absent when the window has not been open in
  this launch.** Absent means unevaluated. Making them present would mean
  either lying or moving the setup screen's derivations into the process,
  which is a larger change than a report justifies.
- **No transcript or recording byte counts.** They would need security-scoped
  access to stat a canonical artifact, and the counters already say more.
- **The `fault` site has never fired**, in tests or on this Mac.
- **Report generation is proved not to touch canonical artifacts by a test
  and by construction** — the writer is given a report and nothing else — not
  by a filesystem audit during a live meeting.
- **The export was driven through the accessibility API, not by a person.**
  What a first-time user makes of the save panel's wording is unmeasured.

## History and notes usability

Interval 24 assessed the whole History workflow — open History, tell the
meetings apart, find one, search transcript text, select a result, read the
transcript, read the status, inspect review candidates, play retained audio,
mark reviewed, switch meetings and return, write and save a note, relaunch —
against a disposable save folder of eighteen synthetic meetings covering
completed, interrupted, failed, legacy, retained audio present, retained audio
absent, review candidates present, none flagged, a recogniser that reported no
confidence, an existing long note, a very long title, a four-hundred-passage
transcript and enough filler for search and sorting to matter. The folder was
built by the real writers, driven through the Accessibility API on a running
Debug build, and removed afterwards; the user's own save-folder bookmark was
restored.

**One release blocker, found and fixed.** With a meeting selected, any rebuild
of the listing cleared the derived model and never re-attached it. Three things
rebuild the listing and only one of them is deliberate: the Refresh button,
returning to the History tab, and a meeting finishing while History is open.
The consequences were an unsaved note destroyed by ordinary ⌘1/⌘2 navigation
with no prompt; a Notes pane left permanently reading *Reading this meeting's
notes…* with no editor and no Save; Mark Reviewed and Mark Unreviewed gone from
every candidate; and the *N of M marked reviewed* summary silently dropped. It
did not recover on its own — the user had to select another meeting and come
back. Observed live in the running app and held by tests.

The correction is two small changes and no new concept. `HistoryModel`
remembers which session `selectSession` was last given and re-attaches derived
state at the end of every load, detaching it only when that session is no
longer in the folder. `DerivedSessionModel` carries an unsaved draft across a
re-read of the same meeting when the sidecar on disk is still the revision the
editor was working from; a sidecar that changed underneath is shown as it now
is, because that is the version a save would have to land on. Selecting a
different meeting still discards the draft, which is documented and warned
about, and the in-app caption now says *another meeting* rather than *this
meeting* because that was the half of the sentence the old behaviour broke.

**Everything else was found sufficient and deliberately left alone.** Ordering
is newest first and legible; completed, interrupted, failed and legacy are
words in a capsule rather than a colour, each with a full explanation sentence
in the detail pane and in its accessibility label; a long title truncates in
the row and is shown whole in the detail; ⌘2 opens History and ⌘F reaches the
search field; the list is keyboard navigable and selecting by arrow key opens
the right meeting; substring search over transcript text returns *1 of 18* with
an excerpt and a timestamp, and clearing it restores the list; *no meetings* and
*no meeting matches* are distinct sentences; a meeting that flagged nothing is
distinguished from one whose recogniser reported no confidence, and both from
a meeting that kept no recording; Play Audio and Mark Reviewed are separate
actionable controls and playback state stays on the candidate that owns it;
Save says *Saved* only after the write, and a reviewed mark survives a quit and
relaunch. No grouping, filtering, sorting control, fuzzy search, scrubber,
autosave or navigation confirmation was added, and none was justified.

**Artifact invariance, measured rather than asserted.** Across the whole
session — eighteen meetings listed, searched, selected, read, one recording
played, a mark written, a note saved, repeated reloads and a full relaunch —
exactly one file in the save folder was written: `derived.json` in the single
meeting the user acted on. Every `transcript.md`, `audio.m4a`, `session.json`
and `review.json` was byte-identical afterwards, checked by digest.

**Evidence limits.** Everything above was driven through the Accessibility API,
not by a person: no human read the screen, and no VoiceOver was running. Audio
playback was confirmed by the player's own control state rather than by
listening. The meeting-finished reload was not reproduced with a real meeting;
it is the same `load()` call as the Refresh button, which was. The full
VoiceOver-with-no-mouse pass is still outstanding and belongs to Interval 25.

## Feature freeze

Feature freeze for v0.1.0 begins after Interval 24. Intervals 25 to 28 may fix
release blockers and defects found through evidence, and may not add
discretionary product features. Deferred product ideas — interrupted-session
continuation, notes search, summaries, export, transcript editing, document
management — do not become pre-release intervals.

## Next interval

**Closed by Interval 23.** Whether an interrupted meeting should be continuable
into the same session is answered, and the answer is no for v0.1.0. It is
answered with measurements rather than with an estimate of effort: a retained
recording is replaced rather than extended when it is reopened, an unfinalised
M4A cannot be read at all, and the record a killed meeting leaves has no
captured length to continue offsets from. The documentation says so plainly,
the roadmap no longer lists continuation as planned, and two tests hold the
constraints in place.

**Open.** Everything Interval 22 left open is still open: the
VoiceOver-with-no-mouse human pass, source disappearance during a running
capture, `ScreenCaptureKitAudioCapturer.stop()` not calling
`removeStreamOutput(_:type:)` since Interval 15, and the visible-presentation
cost Interval 18 profiled. New and honest: nothing here was validated against a
real interrupted meeting on this Mac either — the constraints were measured on
files written by AVFoundation directly, and the recovery path they concern is
covered by tests and by Interval 12's live SIGKILL run rather than by a fresh
one.

**Interval 25 did not close it.** Everything that could be established without
a person was established: the clean test, the Release build, the strict docs
build, a real launch of the Release application, the absence of a network
socket, the entitlement set, the built product's metadata, and a documentation
audit that found and fixed a false minimum-macOS claim. What remains is exactly
what four intervals have now named and none has produced — a person driving the
application. Not an Accessibility API script standing in for one.

**The source release candidate is blocked on human evidence, not on code.** The
outstanding list is a real meeting spoken into by hand, with Pause, Resume and
Stop observed live and the resulting artifacts inspected; the background,
window and menu-bar lifecycle; quit during a meeting; the History, review and
notes workflow by hand; a keyboard-only pass; a VoiceOver pass; and a light,
dark and layout inspection. Nothing in the code needs to change for any of it,
and each produces either confirmation or a list of real defects.

**Also still open, and unchanged.** Source disappearance during a running
capture, `ScreenCaptureKitAudioCapturer.stop()` not calling
`removeStreamOutput(_:type:)` since Interval 15, and the visible-presentation
cost Interval 18 profiled.

**Interval 26 inherits a packaging list, not a code list.** The application's
version metadata still says `1.0`/`1` and must become `0.1.0` with a real build
number; the bundle identifier `quang.ScribeKit` is a decision that has not been
made deliberately; the locally signed build carries `get-task-allow`, which a
Developer ID export must not; and the deployment target is settled at 26.5
unless a 26.0–26.4 machine becomes available to test a lower one against.
Signing identity, notarization credentials, archive and export, the DMG,
Gatekeeper and a fresh packaged installation all belong there.

## Interval 22's closing note

**Closed by Interval 22.** ScribeKit can now be supported without being
trusted. Its own transitions and failures are named in the unified log under
one subsystem and eight categories, and a user can hand somebody a
point-in-time report that says which subsystem stopped and in what condition
without carrying a word of what was said, a folder path, or the name of an
application they had open. The privacy boundary is a test rather than a
convention.

**Open.** The VoiceOver-with-no-mouse human pass Interval 21 named is still
the one piece of evidence that cannot be automated, and Interval 22 did not
manufacture it. Also still open: source disappearance during a running
capture, `ScreenCaptureKitAudioCapturer.stop()` not calling
`removeStreamOutput(_:type:)` since Interval 15, and the visible-presentation
cost Interval 18 profiled. New and honest: no live meeting was driven by hand
this interval either, so the report's `session` section has been read with
real numbers from doubles rather than from a real recording.

## Interval 21's closing note

**Closed by Interval 21.** The application has its own menus, derived from the
same value the menu bar and the window read, so three surfaces cannot disagree
about what a meeting can currently do. The two screens have a keyboard route.
The History search field has a Find command that reaches it. The composed rows
— readiness, review candidates — publish complete sentences rather than
fragments or, in the readiness rows' case, nothing at all.

**Open.** The evidence gap Interval 20 named is narrower but not closed: the
satisfied path has now been seen on a real Mac, and refusal has not. A person
with VoiceOver on and their hands off the mouse is the next piece of evidence
worth collecting, and it is the one thing here that cannot be automated. Also
still open: source disappearance during a running capture,
`ScreenCaptureKitAudioCapturer.stop()` not calling `removeStreamOutput(_:type:)`
since Interval 15, and the visible-presentation cost Interval 18 profiled.

## Interval 20's closing note

Interval 20 answered the question a first launch asks. A new user now sees the
four things a meeting needs before they press anything, each with its state in
words and the control that resolves it, and an ending is described rather than
implied: an interrupted meeting is no longer presented as a finished one in
either the window or the menu bar.

**Closed.** Start readiness is one derived value rather than three views each
checking a subset, so a disabled Start button always has a stated reason and a
corrected prerequisite clears itself. Missing capture access is distinguished
from a discovery failure by an authoritative, non-prompting system call rather
than by repeating a framework error. Every ending answers what happened, what
it means for the files, and what to do next.

**Open, and deliberately untouched.** Source disappearance during a running
capture. ScreenCaptureKit may emit no actionable signal, and solving it is a
capture architecture change, not a UX one. Also still open:
`ScreenCaptureKitAudioCapturer.stop()` never calls
`removeStreamOutput(_:type:)`, unimplicated and uncleared since Interval 15;
and the visible-presentation cost Interval 18 profiled, which wants a different
shape of transcript view rather than another split of the current one.

**New, and honest.** Nothing here was proved against a real refusal. No
permission was denied on this Mac, no disk pulled, no model uninstalled. The
states are reached through injected failures, and the first user to hit one for
real is the evidence this interval does not have. That is the natural thing for
a later interval to collect, and it costs nothing to collect it: the states are
already named, so the question is only whether the machine produces the ones
ScribeKit expects.

The obvious candidates after this are a real first-run on a clean Mac, and the
accessibility pass this interval deliberately kept to the controls it added.
