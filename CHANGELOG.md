# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Added

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
