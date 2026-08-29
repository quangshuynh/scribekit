# CONTEXT.md

Current working state of the repository. Keep this short and current; see
`README.md` for the project and `AGENTS.md` for the engineering rules.

## Current milestone

Interval 4 — selected-application audio capture. Complete.

## Current implementation

- Domain value types in `ScribeKit/Models/`: `MeetingState`,
  `AudioRetentionMode`, `CaptureSource`, `MeetingSession`, unchanged apart from
  being declared `nonisolated`, since the project defaults to main-actor
  isolation and value types have no reason to be bound to it.
- `ScribeKit/Capture/`: discovery unchanged from Interval 2
  (`CaptureSourceProviding`, `DiscoveredApplication`, `CaptureSourceCatalog`,
  `ScreenCaptureKitSourceProvider`). Capture added: `AudioCapturing` with
  `AudioCaptureError`, `AudioCaptureConfiguration`, `AudioSampleConsuming`,
  `CapturedAudioSample` / `CapturedAudioFormat`, `CaptureSourceReconciliation`
  (pure identity matching), `AudioCaptureActivityMonitor` with
  `AudioCaptureActivity`, `CapturedAudioSampleAdapter` (the only reader of
  `CMSampleBuffer`), and `ScreenCaptureKitAudioCapturer`, an actor owning the
  `SCStream`.
- `ScribeKit/Persistence/`: `SaveLocationPersisting` (save/restore/clear) with
  `SaveLocationError`; `SecurityScopedSaveLocationStore`, the only type that
  handles bookmark data; `SecurityScopedAccess`, which scopes
  start/stopAccessingSecurityScopedResource around a piece of work;
  `MeetingSetupPreferencesStoring` with a `UserDefaults` implementation;
  `SessionDirectoryName` (pure naming policy) and `SessionArtifactLayout` (pure
  URL arithmetic).
- `ScribeKit/Models/`: `AudioCaptureState` (idle / preparing / capturing /
  stopping / failed) is the capture subsystem's lifecycle, separate from
  `MeetingState`, which covers a whole session.
- `ScribeKit/Features/MeetingSetup/`: `MeetingSetupDestinationModel` owns the
  save-location state; `MeetingSetupSourcesModel` additionally seeds its
  selection from remembered bundle identifiers; `MeetingSetupCaptureModel` owns
  capture state and the coalesced activity summary; `MeetingSetupView` renders
  the folder, its warnings, Choose / Forget, and Start / Stop Capture, and keeps
  Start Meeting disabled.
- `ScribeKit.entitlements` adds `com.apple.security.files.bookmarks.app-scope`;
  the target keeps `ENABLE_APP_SANDBOX` and now grants read-write access to
  user-selected files.
- `ScribeKitTests/`: Swift Testing suites (100 tests, 15 suites).

No transcription, transcript writing, recovery or background behaviour exists.
Captured audio is described and discarded. Nothing is written to the chosen
folder, and no Speech framework code exists.

## Capture architecture

Selected `CaptureSource` values → `AudioCaptureConfiguration` →
`ScreenCaptureKitAudioCapturer` → `SCStream` audio output →
`CapturedAudioSampleAdapter` → `AudioSampleConsuming` →
`AudioCaptureActivityMonitor` → coalesced snapshots →
`MeetingSetupCaptureModel` on the main actor.

Buffers are adapted and consumed on a dedicated serial `userInitiated` queue
and are never retained past the callback; the main actor sees only summaries,
published at most twice a second. There is no queue, ring buffer or backlog
between capture and its consumer, so nothing can grow with meeting length.
Unreadable buffers are counted rather than dropped silently.

## Established decisions

- Interval 1 and 2 decisions still hold.
- The save location is stored as a security-scoped bookmark in `UserDefaults`.
  Restoration validates the directory with access held and releases it again;
  stale bookmark data is renewed in place. A missing, inaccessible or malformed
  entry is reported to the user — ScribeKit never substitutes a folder of its
  own.
- Security-scoped access is acquired per piece of work. Nothing owns a
  session-length lease yet; the type writing transcripts will hold its own.
- Save-location state is one enum (`none` / `available` with an origin /
  `unavailable` / `persistenceFailed`), so "remembered but broken" and "usable
  but not remembered" stay distinct.
- Persisted setup configuration is limited to the audio retention mode and the
  selected bundle identifiers. Remembered identifiers are preferences: they are
  matched against fresh discovery, never assumed to be running, and are
  rewritten only when the user changes the selection, so an application that is
  merely closed today stays remembered. Meeting titles are per-session and the
  title is not remembered. No PIDs or runtime state are persisted.
- Session directory names are `yyyy-MM-dd-title-slug`, from the Gregorian
  calendar and fixed digits, with diacritics folded, non-alphanumerics turned
  into hyphens, a 60-character limit on a word boundary and an
  `untitled-meeting` fallback. Collision handling is a predicate, so the policy
  is tested without touching disk.
- `SessionArtifactLayout` fixes the future layout (`transcript.md` beside a
  hidden `.scribekit/session.json`, optional `audio.caf` / `audio.m4a`) without
  creating anything.

## Capture behaviour

- The filter is `SCContentFilter(display:including:exceptingWindows:)` over the
  first display, because ScreenCaptureKit has no audio-only filter. No screen
  output is added, `capturesAudio` is on, `excludesCurrentProcessAudio` is on,
  `captureMicrophone` is off, and the video side is 2×2 at 1 fps with a queue
  depth of 3 — the smallest valid configuration, never read.
- 48 kHz is requested because it is ScreenCaptureKit's own default, so nothing
  is resampled; one channel is requested because speech is monaural.
- Observed delivered format, live: 48 000 Hz, 1 channel, 32-bit float,
  non-interleaved, in 960-frame (20 ms) buffers. The requested channel count was
  honoured.
- Start while capturing throws `alreadyCapturing`. Stop while idle is a no-op.
  Capture can be started again after a stop, and after a failure.
- A selected application that is not running at start fails the start with
  `sourcesUnavailable`, naming it; ScribeKit never captures a smaller set than
  was chosen.
- A captured application that quits mid-capture leaves the stream running and
  silent, verified live. ScribeKit does not poll for liveness and does not
  substitute another source; the next start reports it as unavailable.
- A stream the system stops by itself arrives as an interruption and moves
  capture to `failed` with the system's reason preserved.

## Validation status

`xcodebuild ... clean test` passes on Xcode 26.6 (100 tests, 15 suites) with no
compiler warnings.

Live capture was validated twice: through a throwaway command-line harness
compiled from the same capture sources, and through the sandboxed app itself,
driven via accessibility. A purpose-built 440 Hz tone application (amplitude
0.05, outside the repository) was the audio source.

- Capturing the tone application: ~50 buffers/second, peak 0.0500, 48 kHz mono
  float32 non-interleaved.
- Capturing a different running application while the tone played: 8.5 s,
  peak 0.0000 — the selected-application filter did not admit the other
  application's audio.
- In the app: start → "Capturing 1 application(s)" with a rising buffer
  count; stop → counters freeze and the state returns to idle; start again →
  a fresh capture from zero; Start Meeting stayed disabled throughout.
- Minimising the captured application's window did not interrupt capture.
- Killing the captured application mid-capture left the stream delivering
  silence, and the next start failed with the application named.
- One run out of roughly ten was stopped by the system 0.2 s in with
  "Failed to find any displays or windows to capture". It was surfaced as an
  interruption and torn down cleanly; it has not been reproduced, and the
  window-minimising and process-quitting tests above did not cause it.

Permission failure was not reproduced: revoking screen recording permission on
this machine would have disturbed the developer's own environment. The
permission path is unit tested through the abstraction, and the discovery path
already reports the same condition.

### Interval 3 checks, still current

The signed app carries `com.apple.security.app-sandbox`,
`com.apple.security.files.bookmarks.app-scope` and
`com.apple.security.files.user-selected.read-write`.

The app was launched with a deliberately invalid bookmark stored: the setup
screen showed "No folder selected" with the explanation that the saved folder
could not be found, offered Choose Folder… and Forget Folder, listed running
applications, restored the remembered application selection, and kept Start
Meeting disabled. Choosing a folder in the open panel and confirming that it
returns after a relaunch needs a human click and has not been automated here.

## Known limitations

- Interval 2 limitations still hold (Screen Recording permission, windowless
  applications, manual refresh).
- Captured audio is described, not carried: `CapturedAudioSample` holds format,
  frame count, timing and peak level, never the samples. A transcription
  consumer will need the boundary extended.
- The captured set is fixed at start; changing the selection mid-capture has no
  effect until capture is restarted.
- Capture is stopped when the setup window disappears; there is no session that
  survives it, because sessions do not exist yet.
- Creating and resolving real security-scoped bookmarks needs a folder picked in
  an open panel, so that boundary is covered by running the app rather than by
  unit tests; absent, malformed and unresolvable stored data are unit tested.
- A moved folder is only followed when macOS reports the bookmark as stale. A
  deleted folder, or one on a disconnected disk, must be chosen again.
- The folder is remembered but never written to; no session directory is
  created yet.

## Next interval

Interval 5: on-device transcription of the captured audio. It needs the sample
adapter extended to carry PCM to a recogniser instead of only describing it,
a transcription boundary alongside `AudioSampleConsuming`, and a decision about
whether the recogniser consumes 48 kHz mono float32 directly. Transcript
writing, autosave and recovery stay out of it.
