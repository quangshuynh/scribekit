<p align="center">
  <img src="docs/images/scribekit-logo2.png" alt="ScribeKit app icon" width="256">
</p>

# ScribeKit

[![CI](https://github.com/quangshuynh/scribekit/actions/workflows/ci.yml/badge.svg)](https://github.com/quangshuynh/scribekit/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-5-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-26%2B-blue.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A native macOS app for background-first meeting transcription. ScribeKit runs
quietly while you work in other applications and writes timestamped Markdown
transcripts to a folder you choose, on your machine.

**Status: early development.** Audio capture from selected applications, live
on-device transcription, durable Markdown transcripts, crash recovery, optional
audio retention, background operation with a menu bar item, and local transcript
history and search work end to end.

## Philosophy

- **Local-first.** Transcription and storage happen on your Mac. No accounts,
  no cloud database, no telemetry, no analytics.
- **Raw transcripts are source material.** ScribeKit never silently rewrites a
  transcript with AI, summarisation, grammar cleanup or inferred substitutions.
  Any derived notes are explicitly requested, stored separately, and clearly
  marked as derived.
- **Honest about uncertainty.** Low-confidence transcription is surfaced for
  review rather than quietly smoothed over.
- **Never hidden.** Capture is always visible to the user.

## Currently implemented

- Meeting configuration screen: title, audio retention mode, save location.
- Discovery of running applications through ScreenCaptureKit, with selection of
  one or several of them as intended audio sources, and a manual Refresh.
- Audio capture from the selected applications, started and stopped explicitly,
  with the selection resolved against the applications running at that moment
  and a clear failure when one of them has quit. Capture reports the format and
  level it is actually receiving.
- Live speech transcription of that audio, recognised on this Mac with Apple's
  `SpeechAnalyzer` and an installed on-device language model. Partial text is
  shown as an ephemeral guess and finalised text accumulates as transcript
  segments, so a sentence heard word by word leaves one entry rather than one
  per word.
- An explicit recognition language, chosen from the locales the recogniser
  supports, with the ones whose model is not installed listed and disabled
  rather than silently unavailable.
- Honest reporting of a missing model, an unsupported language, a recogniser
  that stops by itself, and audio that recognition fell too far behind to
  transcribe.
- A durable Markdown transcript. Starting a meeting creates a dated session
  folder in the chosen save location and a `transcript.md` inside it, and each
  finalised span is appended to that file as it is recognised, with a
  wall-clock timestamp taken from the session start plus the span's own audio
  offset. The file is append-only, so it is readable in any editor while the
  meeting is still running.
- Incremental autosave with no timer: a finalised span reaches the file as soon
  as it is recognised, the file is flushed to the storage device every 25
  appends, and Stop flushes and closes the transcript before it reports the
  meeting finished.
- Explicit gap markers in the transcript for audio that was never transcribed,
  positioned where the audio fell when the pipeline knows, and honest about the
  length alone when it does not.
- Honest reporting when the transcript stops being writable: the meeting is
  stopped rather than left recognising speech that nothing is saving.
- Session recovery after an interruption. Each session directory carries a
  small `.scribekit/session.json` recording where the session stands, written
  before a meeting begins and updated only after its transcript has been
  flushed and closed. On launch, ScribeKit looks in the save folder for
  sessions left marked in progress and offers to reveal the transcript, record
  the interruption, or leave the finding for next time. It does not resume
  capture, does not start recognition, and does not rewrite recognised speech.
- A save folder chosen in the system open panel and remembered across launches
  with a security-scoped bookmark, with honest reporting when the folder has
  been moved, deleted or had its access revoked, and controls to replace or
  forget it.
- Optional audio retention. A meeting keeps no audio by default; choosing Raw
  or Compressed writes one audio file beside the transcript as the meeting
  runs, streamed to disk buffer by buffer rather than held in memory. The file
  is closed before the session is recorded as finished, and a recording that
  fails or cannot be finalised is reported and left on disk rather than deleted
  or quietly completed.
- Background operation. A meeting keeps capturing, transcribing and writing
  while the ScribeKit window is hidden, minimised, covered by other
  applications or closed altogether. The meeting belongs to the application,
  not to the window, so the window is somewhere to watch a meeting rather than
  something the meeting depends on.
- A menu bar item, always present. With no meeting it offers Open ScribeKit and
  Quit ScribeKit. With one running it names the meeting, shows its state and
  elapsed time, the applications being captured and what is being kept of the
  audio, and offers Stop Meeting, Show Transcript in Finder, Show Audio in
  Finder and the same two commands. Stop from the menu bar is the same stop the
  window performs: capture ends, the recogniser finalises what it has, the
  audio file is closed, and the transcript is flushed, closed and recorded as
  finished.
- Closing the window keeps ScribeKit running, whether or not a meeting is under
  way; Open ScribeKit brings the same window back rather than opening another.
- Quitting during a meeting asks first, and stopping from that prompt finishes
  the transcript and the audio file before the application exits. Quitting is
  not a crash, and ScribeKit does not leave a meeting for the next launch to
  discover when it could simply finish it.
- Local transcript history. A History screen lists the meetings in your save
  folder — completed, failed, interrupted, and the one running right now —
  newest first, with each meeting's status, times, applications, language,
  transcript size and whether a recording is beside it. Selecting one shows its
  details and a preview of its transcript, and reveals the transcript or the
  recording in the Finder or opens the transcript in whichever application you
  use for Markdown.
- Local search across those transcripts. Plain, case-insensitive text search
  over meeting titles, recognised speech and captured application names, with a
  short excerpt of the matching passage and the transcript timestamp it came
  from. It is deterministic substring matching, not semantic or AI search: no
  embeddings, no vector database, no cloud service, and no index file written
  anywhere near your transcripts.
- History that reads and never writes. Listing, previewing, refreshing and
  searching leave every transcript, recording and session record byte-identical,
  including their modification dates. A meeting whose session record is damaged,
  missing or written by a newer ScribeKit is reported as such and left exactly
  as it is, and never stops the rest of the folder from listing.
- A directory holding a ScribeKit transcript with no session record — written
  before session records existed — is listed as a legacy meeting with only the
  facts its transcript actually states. Markdown ScribeKit did not write is not
  listed as a meeting.
- Remembered setup choices: the audio retention mode and the applications last
  selected, matched against a fresh discovery on each launch.
- Domain models for the session lifecycle, audio retention, capture sources and
  session metadata, with unit tests.
- Shared Xcode scheme and a macOS CI workflow that builds and runs unit tests.

A session produces the user-owned `transcript.md`, one small operational record
in a hidden `.scribekit` folder beside it, and — only when audio retention is
switched on — one audio file. Losing or failing to read the record never makes
the transcript unusable, and no retention mode changes a word of it.

Listing applications and capturing their audio require Screen & System Audio
Recording permission, which macOS asks for the first time ScribeKit looks for
sources. Without it the screen reports the missing permission instead of a list
or a capture. Transcription itself asks for no permission at all, because it
runs against a speech model on this Mac rather than through a service.

## On-device recognition

Speech recognition uses `SpeechAnalyzer` and `SpeechTranscriber`, Apple's
on-device speech APIs, against a language model installed on this Mac.
ScribeKit checks that the model for the selected language is installed and
refuses to start when it is not; it never downloads one on your behalf and
never falls back to network recognition. It does not use `SFSpeechRecognizer`,
the older API that can send audio to Apple's servers. The app ships without the
network client entitlement, so the sandbox does not permit it to open a network
connection at all.

## Planned

All of the following are *planned*, not available:

- Pausing and resuming a meeting.
- Continuing an interrupted meeting into the same session.
- Post-meeting review of uncertain passages, against the retained audio.
- Playback of a retained recording inside ScribeKit.
- Optional derived notes that never modify the raw transcript.

## Audio retention modes

Audio retention is opt-in and off by default. When it is on, one file is
written into the session directory beside `transcript.md`, incrementally, while
the meeting runs. The file stays on your Mac: nothing is uploaded, and nothing
is encrypted — anyone who can read the folder can play the recording.

| Mode | File | Behaviour |
| --- | --- | --- |
| No Audio File | none | Default. Only the transcript is kept; no audio touches disk. |
| Raw (Lossless) | `audio.caf` | Linear PCM in a CAF container, in exactly the 48 kHz mono 32-bit float audio ScreenCaptureKit delivered. Measured at 691 MB an hour. |
| Compressed | `audio.m4a` | AAC at 64 kbit/s in an MPEG-4 container. Measured at 31 MB an hour — about a twentieth of the raw size. |

Both files open in QuickTime Player and anything else that reads standard
macOS audio. A recording's time zero is the first captured audio frame, which
is the same origin the transcript's own segment offsets are measured from.

## Efficiency goals

ScribeKit is intended for multi-hour meetings on battery: event-driven work
instead of polling, minimal timers, bounded and roughly stable memory over long
sessions, coalesced UI updates, batched persistence, no retained audio unless
enabled, and minimal work while the interface is hidden. No screen or video
processing.

## Requirements

- macOS 26 or later
- Xcode 26 or later

## Build

```bash
xcodebuild -project ScribeKit.xcodeproj -scheme ScribeKit -destination 'platform=macOS' build
```

Or open `ScribeKit.xcodeproj` in Xcode and run the `ScribeKit` scheme.

## Test

```bash
xcodebuild -project ScribeKit.xcodeproj -scheme ScribeKit -destination 'platform=macOS' test
```

Unit tests use [Swift Testing](https://developer.apple.com/documentation/testing).

## Architecture

```
ScribeKit/
  App/                    App entry point
  Capture/                Application source discovery and audio capture
  Features/History/       SwiftUI history screen and its state
  Features/MeetingSetup/  SwiftUI configuration screen and its state
  Features/MenuBar/       Menu bar item and the state it presents
  History/                Reading past sessions back, and searching them
  Meeting/                The application-scoped active meeting and its runtime
  Models/                 Domain value types (no I/O)
  Persistence/            Save-location storage and session layout policy
  Transcription/          On-device speech recognition behind its own boundary
ScribeKitTests/           Swift Testing unit tests
```

The active meeting is owned by `MeetingRuntime`, created by the application
delegate and handed to both the window and the menu bar. Its lifetime is the
application's, so a window that is hidden, closed or built again neither ends a
meeting nor starts a second one, and the two interfaces read one derived
`MeetingRuntimeStatus` rather than tracking the meeting separately. What the
setup screen owns is the configuration for the *next* meeting; the running one
holds a `MeetingSnapshot` taken when it started.

Domain models are plain value types with no capture, transcription or
persistence behaviour. Session lifecycle is a single `MeetingState` enum with
explicit transition rules, so contradictory states are unrepresentable.
Capture, speech, persistence and session coordination are separate layers
behind that model: source discovery sits behind the `CaptureSourceProviding`
protocol, capture behind `AudioCapturing` and recognition behind
`SpeechTranscribing`, and ScreenCaptureKit and Speech types are adapted at
those boundaries rather than reaching the UI. Audio buffers are copied,
converted and queued on the capture system's own queue and never cross the main
actor; the interface sees coalesced summaries and transcription events only.
Save-location storage sits behind `SaveLocationPersisting`, so security-scoped
bookmark data never reaches the setup screen, and session directory naming is a
pure policy separate from any filesystem work.

A session is laid out as a directory named from its date and title, holding
`transcript.md`, a hidden `.scribekit/session.json`, and an `audio.caf` or
`audio.m4a` when audio retention is on. Durable writing sits behind
`TranscriptPersisting`, retained audio behind `AudioRetaining` — a consumer of
captured buffers rather than a queue in front of one, so audio is written where
it arrives and no backlog can build up — with Markdown formatting separated from
filesystem work and an actor owning one session's folder lease, open file and
position in the document. Recovery is built on the same separation:
`SessionRecoveryStoring` is the filesystem, `SessionRecoveryMetadata` is the
versioned record, and `SessionRecoveryService` is the policy that decides what
counts as an unfinished meeting — so the setup screen displays recovery rather
than implementing it.

History asks a different question of the same folder and keeps its own layer for
it. `HistoryStoring` is a read-only filesystem boundary — it has no method that
creates, replaces, appends to or deletes anything — `TranscriptDocument` reads a
written transcript back into its header fields and its finalised spans,
`HistoryService` is the policy that decides what counts as a meeting, and
`TranscriptSearch` is a pure matcher over what a load produced. Recovery keeps
its own store because recording an interruption is a write, and history never
writes.

## Roadmap

1. **Foundation** — domain models, configuration UI, tests, CI, docs.
2. **Application audio source discovery and selection**.
3. Durable save location and session configuration.
4. **Audio capture from the selected applications**.
5. **On-device transcription**.
6. **Timestamped Markdown persistence and autosave**.
7. **Crash and session recovery**.
8. **Optional audio retention**.
9. **Background and menu bar operation**.
10. **Transcript history and local search** *(current)*.
11. Uncertainty review against the retained audio, and derived notes.

## Known limitations

- Recovery preserves what was already durable and no more. ScribeKit detects
  unfinished sessions and preserves finalised transcript content that reached
  durable storage before the interruption; audio still in a system buffer, a
  partial hypothesis that was never finalised, and speech that happened while
  ScribeKit was not running are not recovered, because they were never written.
- A finalised span reaches the file as soon as it is recognised, so it survives
  the app exiting. Surviving a power loss depends on the flush that happens
  every 25 appends and at Stop, so an abrupt power cut can cost the appends
  since the last one. ScribeKit does not claim to be crash-proof.
- Recovery never resumes a meeting. It records the interruption and leaves the
  transcript closed; continuing into the same session is a later interval.
- A meeting that ended because its transcript stopped being saved is recorded
  as failed rather than offered for recovery: ScribeKit was running and said so
  at the time.
- A session directory written by an earlier ScribeKit has no session record, so
  it is not recognised as unfinished. Its transcript is unaffected.
- A damaged or newer-format session record is reported and left exactly as it
  is. ScribeKit never repairs, rewrites or deletes one, and never deletes a
  transcript.
- Audio retention writes a file; it does not play one. There is no playback,
  waveform or scrubber in ScribeKit, and a retained recording is reviewed in
  another application.
- A recording is not encrypted. It is an ordinary audio file in the folder you
  chose, and it is as private as that folder is.
- A recording left behind by a crash is a different thing in each format: a
  partly written `audio.caf` opens and plays up to the moment ScribeKit
  stopped, while a partly written `audio.m4a` does not open at all, because an
  MPEG-4 container is only completed when the file is closed. ScribeKit reports
  the file's size and does not repair either one.
- A recording that fails mid-meeting ends the meeting. ScribeKit will not keep
  transcribing while quietly leaving a hole in a file the user asked for.
- Audio arriving in a different format from the one capture was asked for is
  refused rather than resampled, because a file's format is fixed when it is
  created. On this Mac ScreenCaptureKit has always delivered the format that
  was requested.
- A start that fails after the transcript was created leaves that session
  folder behind, holding a transcript with a header and no speech. ScribeKit
  does not delete folders it created.
- Recognition needs an installed on-device language model. Languages whose
  model is absent are listed but cannot be selected, and ScribeKit does not
  install them.
- The recognition language is fixed for a run and is never detected
  automatically; a meeting that changes language is transcribed in the language
  that was chosen.
- Recognition consumes 16 kHz audio, so 48 kHz capture is resampled on the
  capture queue before it reaches the recogniser.
- If recognition falls more than about three seconds behind capture, the oldest
  audio is dropped to keep memory bounded and the lost time is reported as a
  gap in the transcript.
- A recogniser that stops by itself is restarted at most twice; audio arriving
  during a restart is not transcribed and is counted as a gap.
- ScreenCaptureKit has no audio-only stream, so the capture filter names a
  display as well as the selected applications. No screen output is added, so
  no frame is delivered or processed, but the permission macOS asks for is the
  screen recording one.
- The captured set is fixed when capture starts. Changing the selection while
  capture is running does not change what is being captured; stop and start
  again. The title, save folder, language and retention mode are fixed the same
  way, and their controls are disabled while a meeting runs.
- There is no Pause. A meeting runs until it is stopped, and the menu bar does
  not offer a control ScribeKit has not built.
- Quitting waits for the meeting to be finished properly rather than racing it
  against a deadline, so a quit takes as long as closing the transcript and the
  audio file takes. A force quit or a crash is still a crash, and startup
  recovery is what handles those.
- ScribeKit keeps running when its last window is closed, so quitting is
  explicit — from the menu bar item, the application menu, or ⌘Q.
- If a captured application quits mid-capture, ScreenCaptureKit keeps the
  stream alive and delivers silence for it. ScribeKit does not substitute
  another source, and the next start reports the application as unavailable.
- Only applications owning an ordinary on-screen window are listed, so a
  menu-bar-only or windowless application is not offered as a source.
- The application list is refreshed on appearance and on demand, not
  automatically as applications start and quit.
- Access to the chosen folder is held for exactly as long as a meeting is
  being written and released when its transcript is closed; outside a meeting
  it is taken only while the folder is being validated or scanned for
  unfinished sessions.
- The scan for unfinished sessions looks only at the immediate children of the
  chosen save folder, when the app launches or when a folder is chosen. There
  is no recursive walk, no timer and no filesystem watcher.
- If the save folder cannot be restored or opened, ScribeKit says it could not
  check for an unfinished meeting rather than looking anywhere else.
- The transcript's timeline starts when the meeting starts, and audio offsets
  are measured from the first captured frame, which arrives a moment later, so
  a timestamp can be under a second early.
- Clock times in the transcript use a fixed twelve-hour English format and the
  Mac's current time zone; neither follows the system locale, so a transcript
  reads the same wherever it is opened.
- A moved folder is followed only when macOS reports its bookmark as stale; a
  folder that was deleted, or whose disk is absent, has to be chosen again.
- History lists only the save folder you chose, one level deep. It does not
  search your Mac for transcripts, does not follow a folder you moved a session
  out of, and does not remember meetings from a folder you have since replaced.
- History reads the folder when it opens, when you refresh, and when a meeting
  finishes. There is no filesystem watcher, so a session added by something else
  while History is open appears on the next refresh.
- Search is plain substring matching. There is no fuzzy matching, no stemming
  and no synonyms, so a search for `closures` does not find `closure`, and a
  recogniser's misheard word is found only by searching for what it actually
  wrote. Searching for a phrase does not find it if it was split across two
  finalised spans.
- Search does not match ScribeKit's own writing in a transcript — the header,
  minute headings, gap markers, the interruption notice and the footer — so a
  query for `Transcription gap` finds nothing. Titles and application names are
  searched as metadata.
- Whole transcripts are held in memory while History is open, so its cost grows
  with the folder. Measured on this Mac in a debug build, 200 one-hour meetings
  — 48,000 spans, 7.9 MB of transcript — load in 0.82 s and search in 100–160 ms
  per query, for a 17 MB memory increase. A folder several times larger would
  justify an on-disk index; nothing smaller does.
- History shows a meeting that is running as In Progress and reads its transcript
  as it grows. It never writes to that transcript, and cannot start or stop the
  meeting.
- Transcript history is read-only. ScribeKit has no editor, no rename, no delete
  and no export; the files are yours to manage in the Finder.
- CI runs build and unit tests only — no linting, formatting, coverage or UI tests.

## License

MIT — see [LICENSE](LICENSE).
