# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Fixed

- Long meetings no longer die between twenty and twenty-six minutes. The
  capture activity summary was published through an observer stored as a bare
  function inside a `Mutex`; copying a function back out of the lock
  re-abstracted it, and the thunk it gained was left behind in the stored
  value. Every published snapshot therefore added two frames to the chain the
  next one would call through, and after roughly 2,770 updates — twice a
  second, so a little over twenty minutes — the chain overran the audio
  delivery queue's 512 KB stack and the process took `SIGBUS` against its
  guard page, losing the unfinalised recording with it. The observer is now
  held inside a value, so a publish costs the same stack on a meeting's last
  buffer as on its first. This is the crash `docs/PERFORMANCE.md` recorded as
  open.
- A meeting no longer creates a main-actor task on ScreenCaptureKit's audio
  delivery queue. The capture activity summary was published by a handler that
  runs on that queue, and the handler created an unstructured `Task` to hop to
  the main actor — twice a second, for the length of a meeting, to refresh a
  value only the interface reads. Routing a high-frequency audio callback into
  the main actor is the one thing the capture pipeline may not do. The summary
  now crosses through a single long-lived consumer of a stream that keeps only
  the newest snapshot, so the delivery queue creates nothing and no snapshot
  can accumulate. This is a correctness fix against the pipeline's own rules,
  and was never a fix for the crash above, which had a separate cause.
- An explicit Resume now gives the recogniser its restart budget back. The
  bound on automatic self-restarts belongs to a capture run rather than to the
  whole meeting: a person choosing to carry on is not an automatic retry, and
  the resumed run has just proved the recogniser starts. A meeting that
  stumbled twice in its first hour is no longer unable to recover for the rest
  of the day. Each run is still bounded to the same number of self-restarts,
  and only a person can reset it.
- A recogniser that restarts itself no longer restarts the transcript's
  timeline with it. A new recognition run counts its own offsets from its own
  first frame, and those offsets were being written to the transcript as they
  arrived, so every span after a mid-meeting restart claimed a position near
  the start of the meeting: offsets went backwards, wall-clock timestamps went
  backwards with them, and review playback would have sought to the wrong
  second of the recording. The run's offsets are now rebased onto the meeting's
  own media timeline, and the base changes only once every event the previous
  run published has been handled, so a report the old run made on its way out
  is not moved onto the new run's timeline.
- A recogniser that cannot be brought back now ends the meeting. Recognition
  that stopped for good left capture running, the transcript and the recording
  open and the App Nap assertion held, indefinitely and with nothing in the
  transcript accounting for the untranscribed stretch; because the runtime
  still considered a meeting active, no further meeting could be started in
  that process. Capture is stopped, the artifacts are closed and kept, and the
  session is recorded as failed.
- A start that fails after the transcript was created is recorded as failed
  rather than completed. A meeting that could not start recognition or capture
  never captured a second, and History listed its empty transcript under the
  same status as a meeting that ran and finished.
- A pause whose marker cannot be written now closes the retained recording.
  The transcript failure already ended the meeting, but because capture and
  recognition had already stopped at the pause boundary, the recording's writer
  was left open for the life of the process, the activity assertion was never
  released, and the runtime never returned to idle.

### Added

- User-derived meeting state in `.scribekit/derived.json`: local Markdown notes
  the user writes about a meeting, and a Reviewed mark per review candidate.
  Schema-versioned, probed for its version before anything else is interpreted,
  and holding only what the user decided — no transcript text, no confidence, no
  review reasons, no audio metadata.
- `DerivedSessionStoring`, a write boundary of its own. `HistoryStoring` stays
  read-only by construction; the new protocol can address `derived.json` and
  nothing else, so a failed derived write cannot damage `transcript.md`, the
  retained recording, `session.json` or `review.json`. `DerivedSessionService`
  opens security-scoped access for the length of one read or write and closes it
  again.
- Mark Reviewed and Mark Unreviewed on each review candidate, written as the
  decision is made and identified by the span index `review.json` already uses.
  A mark whose index no longer names a candidate resolves to nothing rather than
  attaching to another passage, and is kept rather than discarded.
- A Notes editor in the History detail pane: plain Markdown source, empty by
  default, explicit Save, and a status line that says *Saved* only after the
  write succeeded. A failed save keeps the user's text and says why.
- Last-writer-refused conflict handling. Every derived record carries a revision
  token; a save reads what is on disk and refuses unless the revision is the one
  the editor loaded. Damaged, newer-format and foreign sidecars are refused the
  same way and never overwritten.

- Pausing and resuming a running meeting, from the main window and from the
  menu bar, which drive the same `MeetingRuntime` actions. Pause tears down the
  capture stream, finalises the audio the recogniser already holds and leaves
  the meeting open; Resume rebuilds the stream for the sources the meeting was
  started with and continues the same session, transcript and recording. No
  second session directory, no second transcript, no second audio file.
- Two explicit timelines. Captured media time advances only while capture runs
  and is what transcript offsets, retained audio and review playback are
  measured in, so a passage at offset *t* is still second *t* of the audio file
  after any number of pauses. Wall-clock time keeps running while paused and is
  what the transcript's timestamps, the elapsed display and the footer's
  `**Duration:**` state.
- Structural pause and resume markers in the transcript, written as
  blockquotes beside the existing gap markers. They state what the user did and
  claim nothing about missed speech, and recognised text is untouched.
- `**Captured:**` in the transcript footer, written only for a meeting that was
  paused, so a reader is told the recording's length as well as the meeting's.
- `pausedAt` and `capturedDuration` in the session record, added additively at
  schema version 1 the way `audioRetention` and `audioPath` were. A ScribeKit
  that stops while a meeting is paused leaves a record saying so, and the
  recovery screen says so too. Nothing resumes capture by itself.

### Changed

- The retained recording holds captured audio only. A pause inserts no silence
  and buffers nothing: the audio after a resume continues from the frame before
  the pause, so a five-minute pause adds nothing to the file.
- A resume that fails leaves the meeting paused with its artifacts untouched
  and reports why. A source that has quit is named rather than substituted, and
  the resume can be retried when it comes back.

- Post-meeting review of uncertain recognition. A finished meeting records the
  passages worth a second listen, and History's detail pane lists them in
  transcript order with the recognised wording exactly as the transcript has
  it, its timestamp, a High/Medium/Low priority and the reason it was flagged.
  Nothing is corrected, replaced or rewritten, and there is no editor.
- Recognition confidence, as the recogniser itself reports it.
  `SpeechTranscriber` is now asked for its `transcriptionConfidence` attribute
  and a finalised span carries the lowest confidence any of its words reported.
  ScribeKit never shows the value, or anything derived from it, as a number or
  a percentage: it decides whether a passage is flagged, and nothing else.
- A review sidecar, `.scribekit/review.json`, versioned from its first release.
  It holds span positions, audio-relative offsets and the evidence behind them,
  never transcript text — so `transcript.md` is written exactly as the
  recogniser produced it and carries no confidence annotation of any kind. A
  session without a sidecar, or with one this build cannot read, is listed,
  opened and searched exactly as it would be otherwise.
- Playback of retained audio from a review passage. `AVPlayer` over an
  `AVURLAsset`, so a recording is read from disk as it plays rather than loaded
  into memory, with play, pause and stop, and a seek to the passage's own audio
  offset with a couple of seconds either side. CAF and finalised M4A both play;
  an M4A that was never finalised is reported as unopenable rather than
  repaired, and a meeting that kept no recording offers no playback.
- An explicitly owned security-scoped claim for playback. The player takes a
  `SecurityScopedLease` when it starts and releases it when it stops, fails or
  is released, so access is held for exactly as long as a recording is being
  read and never longer.
- Local transcript history. A History tab beside the meeting screen lists the
  meetings in the save folder — completed, failed, interrupted and the one
  running now — newest first, with a detail pane giving each meeting's status,
  times, applications, language, transcript size, audio state and a bounded
  preview of its transcript, plus Show Transcript in Finder, Open Transcript and
  Show Audio in Finder when a recording is actually there.
- Local search across those transcripts. Plain, case-insensitive, locale-
  independent substring matching over meeting titles, recognised speech and
  captured application names, ranked by why a session matched and by how often
  and how early the query occurs, with a bounded verbatim excerpt carrying the
  transcript timestamp of the span it came from. No fuzzy matching, no
  embeddings, no vector database, no cloud service and no database on disk.
- A read-only filesystem boundary for history. `HistoryStoring` has no method
  that creates, replaces, appends to or deletes anything, so listing, previewing,
  refreshing and searching leave every transcript, recording and session record
  byte-identical — modification dates included — by construction rather than by
  convention.
- A parser for ScribeKit's own Markdown, `TranscriptDocument`, which reads a
  written transcript back into its header fields and its finalised spans.
  Structure is never inferred from the shape of a line: the paragraph after a
  timestamp is consumed positionally, so recognised speech that reads like
  Markdown stays speech, and ScribeKit's own header, minute headings, gap
  blockquotes, interruption notice and footer never become searchable text.
- Legacy transcripts in history. A directory holding a ScribeKit transcript with
  no session record is listed as a legacy meeting, with only the facts its
  transcript states and no invented start time. Markdown ScribeKit did not write
  is not listed. Recovery is unchanged: a session with no record is still not an
  unfinished meeting.
- A disposable in-memory search index. It precomputes the lower-cased ASCII bytes
  of each span when History loads, is rebuilt on every refresh, and is never
  written to disk. Measured in a debug build, it took a query over 200 one-hour
  meetings from 1.1 s to 100–160 ms.

- Background meeting operation. A meeting now keeps capturing, recognising,
  writing its transcript and writing its retained recording while the main
  window is hidden, minimised, covered or closed. Closing the window no longer
  ends anything, and ScribeKit stays running with its menu bar item when its
  last window closes.
- A menu bar item. It shows the meeting's title, state, elapsed time, the
  applications it is capturing and what it is keeping of its audio, and offers
  Stop Meeting, Show Transcript in Finder, Show Audio in Finder, Open ScribeKit
  and Quit ScribeKit. Stop is the same stop the window performs, with the same
  finalisation order. There is no Pause item, because pause is not implemented.
- A process activity assertion held for exactly the length of a meeting, so
  macOS does not put a hidden ScribeKit into App Nap while it is transcribing.
  It uses the narrowest option that addresses that — the Mac is still free to
  sleep when the user leaves it idle — and it is released on every path a
  meeting can end by, including failure.
- Quitting during a meeting asks first. Choosing to quit stops the meeting the
  ordinary way — capture, recogniser, drained events, recording closed,
  transcript closed, completion recorded — and termination continues only once
  that is done. Cancelling leaves the meeting exactly as it was.
- One elapsed-time clock for the whole application, ticking once a second only
  while a meeting runs. It writes nothing: the transcript and the session
  record remain the account of when a meeting ran.

### Changed

- The main window now has two tabs, Meeting and History, in place of the single
  meeting screen. Both read the same application-scoped `MeetingRuntime` and
  neither owns it, so moving between them starts, stops and duplicates nothing.
- The active meeting is owned by the application rather than by the meeting
  screen. `MeetingSetupCaptureModel` is now `MeetingRuntime`, created by the
  application delegate and handed to the views, and the screen no longer stops
  the meeting when it disappears. There is at most one active meeting, enforced
  by the runtime rather than by whichever window is open, and the menu bar and
  the main window read one derived status instead of two.
- The main window is a single `Window` scene, so Open ScribeKit reopens or
  fronts the window that exists instead of adding another.
- Setup controls that a running meeting has already fixed — its title, its
  applications, its save folder — are disabled while it runs, alongside the
  language and retention pickers that already were. A meeting keeps the
  settings it started with.
- Unfinished-session recovery controls are unavailable while a meeting is
  running, because the meeting being written right now is legitimately recorded
  as in progress.

- Optional audio retention. A meeting can now keep its captured audio beside
  the transcript: `audio.caf` (linear PCM in a CAF container, in exactly the
  48 kHz mono float the capture system delivers, measured at 691 MB an hour) or
  `audio.m4a` (AAC at 64 kbit/s, measured at 31 MB an hour). The default is
  still to keep none, and no audio file is created in that mode.
- Streaming audio writing behind an `AudioRetaining` boundary. The retainer is
  a consumer of captured buffers rather than a queue in front of one: each
  buffer is written on the capture system's delivery queue before the call
  returns, so there is no backlog to bound, no audio is dropped to keep up, and
  a multi-hour meeting costs the same memory as a one-minute one.
- Audio retention in the session lifecycle. The audio file is opened after the
  transcript and before recognition, so a meeting that cannot keep the audio it
  was told to keep never captures anything, and it is closed before the
  transcript, so a session is never recorded as completed while one of its
  artifacts is still open. A recording that fails or cannot be finalised ends
  the meeting as failed, and the partial file is closed and left where it is.
- Retention state in the session record. `session.json` now carries the
  meeting's retention mode and, when there is one, the recording's name. Both
  are optional additions at schema version 1: a record written before they
  existed still reads, which is why the version was not raised.
- Retained recordings in startup recovery. An unfinished meeting that was
  recording is reported with its recording's size, stated as a file that was
  still being written rather than as one that is known to play. Discovery reads
  attributes and changes nothing.
- An audio file status, path and Show Audio in Finder control on the meeting
  screen, and a retention picker disabled while a meeting runs, since the
  choice is fixed for a run.

- Session recovery. Each session directory now carries
  `.scribekit/session.json`, a schema-versioned record of where the session
  stands: in progress, completed, failed, or interrupted. It is written before
  a meeting begins — a meeting that cannot establish one does not start — and
  updated only after the transcript has been flushed and closed, so a session
  is never recorded as completed ahead of the file it describes.
- Startup discovery of meetings that never finished. ScribeKit scans the
  immediate children of the chosen save folder once, when it launches or when a
  folder is chosen, holding security-scoped access only for the length of the
  scan. Damaged and newer-format records are reported and left untouched; a
  folder that cannot be opened is reported rather than replaced with another.
- A recovery section on the meeting screen showing what is known about an
  unfinished meeting — its title, when it started, when its transcript was last
  written — with controls to reveal the transcript, record the interruption, or
  leave the finding for the next launch. Nothing about recovery starts capture
  or speech recognition.
- An interruption note appended to a recovered transcript, stating that
  ScribeKit stopped before the meeting finished and that when it stopped is not
  known. It invents no crash time and no gap duration, is a blockquote like the
  existing gap markers, and is appended once. Recognised speech is untouched.

- Durable Markdown transcripts. Starting a meeting creates a dated session
  directory in the chosen save folder and a `transcript.md` inside it, with a
  deterministic header, per-minute headings, one timestamped entry per
  finalised span and a footer written when the meeting ends.
- Wall-clock timestamps derived from the session start plus each span's own
  audio-relative offset, formatted by fixed rule rather than by system locale.
- Explicit transcript gap markers for audio that was never transcribed, carrying
  the position of the loss when the pipeline knows it and its length alone when
  it does not. Dropped audio now reports where in the run it fell.
- Durable writing behind a `TranscriptPersisting` boundary, with Markdown
  formatting separated from filesystem work, an actor owning one session's
  file, folder lease and document position, and append-only writing so the
  transcript is readable while the meeting runs and never rewritten.
- Incremental autosave: finalised speech reaches the file as it is recognised,
  the file is flushed to the storage device every 25 appends, and Stop flushes
  and closes it before reporting the meeting finished. No timers.
- Session-length security-scoped access as an owned `SecurityScopedLease`,
  taken when a session's directory is created and released when its transcript
  is closed.
- A real Start Meeting control, replacing the separate Start Transcribing
  control and the disabled placeholder, with a status line for the transcript
  file and a control to reveal it in the Finder once it is closed.
- Accounting for every transcription event published, so a stop can wait for
  work still in flight and an overflowing event buffer fails the meeting
  instead of silently losing finalised speech.
- Meeting domain models: `MeetingState`, `AudioRetentionMode`, `CaptureSource`
  and `MeetingSession`.
- Meeting configuration screen with title, audio retention and save location.
- Application source discovery behind a `CaptureSourceProviding` abstraction,
  with a ScreenCaptureKit-backed provider that enumerates shareable
  applications without creating a capture stream.
- Filtering policy that hides ScribeKit itself, unnamed or unidentified
  entries, background processes without an ordinary on-screen window, and
  duplicate processes of one application.
- Multi-application selection in the meeting setup screen, with loading, empty
  and error states, a manual Refresh, and removal of selections whose
  application is no longer running.
- Unit tests for the session lifecycle and model semantics, source filtering,
  discovery states and selection reconciliation.
- Save-location persistence behind a `SaveLocationPersisting` abstraction, with
  a security-scoped bookmark implementation that restores the chosen folder on
  later launches, renews stale bookmark data and reports missing, inaccessible
  or malformed storage instead of falling back to a folder of its own.
- Save-location state in the meeting setup screen, covering no destination, a
  restored one, a newly chosen one, an unusable stored one and a failure to
  remember one, with controls to choose, replace and forget the folder.
- Remembered meeting setup choices: audio retention mode and the bundle
  identifiers last selected, reconciled against fresh discovery at launch.
- Deterministic session directory naming (`2026-08-31-ios-training-day-2`) and
  a session artifact layout describing where a transcript, metadata and
  optional audio will live. Nothing is written to disk yet.
- Audio capture from the selected applications behind an `AudioCapturing`
  abstraction, with a ScreenCaptureKit implementation that resolves the
  selected bundle identifiers against the applications running at that moment,
  filters capture to them, and refuses to start when one of them has quit
  rather than capturing a different set.
- Audio-only stream configuration: no screen output is added, the video side is
  reduced to the smallest frame the API accepts, and the microphone and
  ScribeKit's own output are excluded.
- Bounded capture accounting: the interface shows coalesced counts, duration,
  the format actually received and a peak level.
- Live on-device speech transcription behind a `SpeechTranscribing`
  abstraction, with an implementation built on `SpeechAnalyzer` and
  `SpeechTranscriber`. Recognition runs against a language model installed on
  the Mac; a missing model, an unsupported language or an unavailable
  recogniser stops the run from starting and is explained, and nothing falls
  back to network recognition.
- Captured audio is now carried rather than only described: `CapturedPCMBuffer`
  holds one buffer's frames, copied out of the capture system's memory while
  its callback is on the stack, with the format, frame count, timestamp and
  peak level that went with it.
- Framework-independent transcription models: `TranscriptSegment` with an
  explicit partial/final recognition state and audio-relative timing,
  `TranscriptionEvent`, `TranscriptionInterruption`, `TranscriptionState` and
  `SpeechRecognitionAvailability`.
- An explicit recognition locale in `TranscriptionConfiguration`, selectable in
  the setup screen from the locales the recogniser supports, with uninstalled
  models listed and disabled. The language never changes on its own.
- Recognition hints (`contextualStrings`) are carried through to the
  recogniser's analysis context. ScribeKit ships none, so recognition output
  stays the recogniser's own.
- A bounded audio pipeline: captured buffers are resampled to the recogniser's
  16 kHz input on the capture queue and handed to a fixed-capacity queue.
  When recognition falls behind, the oldest audio is dropped, the lost time is
  measured, and it is reported as a gap in the transcript rather than hidden.
- Bounded recovery from a recogniser that stops by itself: it is restarted at
  most twice while capture continues, and the untranscribed time is recorded.
- A live transcript area in the setup screen showing finalised segments with
  their offsets and one ephemeral partial hypothesis, rendered lazily. Repeated
  partials replace one another instead of accumulating as entries.
- Start and stop controls for the whole pipeline in the meeting setup screen,
  with separate capture and recognition state, honest permission,
  unavailable-source and unavailable-model failures, and interruption reporting
  when the system stops a running stream. Start Meeting remains disabled, and
  no transcript, audio or session file is written.
- App sandbox entitlement for app-scoped bookmarks, and read-write access to
  user-selected folders.
- GitHub Actions workflow that builds and tests on macOS.
- Project documentation: `README.md`, `AGENTS.md`, `CLAUDE.md`, `CONTEXT.md`,
  `CONTRIBUTING.md`.

### Changed

- `SessionCompletionOutcome.completed` now means every durable artifact the
  meeting enabled was finished, not the transcript alone. A meeting whose
  recording could not be finalised is recorded as failed.
- `TranscriptPersisting.finishSession` now takes how the meeting ended, so a
  meeting stopped by a save failure is recorded as failed rather than left
  looking like one that vanished.
