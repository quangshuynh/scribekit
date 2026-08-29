# CONTEXT.md

Current working state of the repository. Keep this short and current; see
`README.md` for the project and `AGENTS.md` for the engineering rules.

## Current milestone

Interval 3 — durable save location and session configuration. Complete.

## Current implementation

- Domain value types in `ScribeKit/Models/`: `MeetingState`,
  `AudioRetentionMode`, `CaptureSource`, `MeetingSession`, unchanged apart from
  `AudioRetentionMode.default` becoming `nonisolated`.
- `ScribeKit/Capture/`: unchanged from Interval 2 — `CaptureSourceProviding`,
  `DiscoveredApplication`, `CaptureSourceCatalog`,
  `ScreenCaptureKitSourceProvider`.
- `ScribeKit/Persistence/`: `SaveLocationPersisting` (save/restore/clear) with
  `SaveLocationError`; `SecurityScopedSaveLocationStore`, the only type that
  handles bookmark data; `SecurityScopedAccess`, which scopes
  start/stopAccessingSecurityScopedResource around a piece of work;
  `MeetingSetupPreferencesStoring` with a `UserDefaults` implementation;
  `SessionDirectoryName` (pure naming policy) and `SessionArtifactLayout` (pure
  URL arithmetic).
- `ScribeKit/Features/MeetingSetup/`: `MeetingSetupDestinationModel` owns the
  save-location state; `MeetingSetupSourcesModel` additionally seeds its
  selection from remembered bundle identifiers; `MeetingSetupView` renders the
  folder, its warnings, and Choose / Forget controls, and keeps Start Meeting
  disabled.
- `ScribeKit.entitlements` adds `com.apple.security.files.bookmarks.app-scope`;
  the target keeps `ENABLE_APP_SANDBOX` and now grants read-write access to
  user-selected files.
- `ScribeKitTests/`: Swift Testing suites (68 tests, 10 suites).

No capture, transcription, transcript writing, recovery or background behaviour
exists. Nothing is written to the chosen folder.

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

## Known limitations

- Interval 2 limitations still hold (Screen Recording permission, windowless
  applications, manual refresh, untested ScreenCaptureKit adapter).
- Creating and resolving real security-scoped bookmarks needs a folder picked in
  an open panel, so that boundary is covered by running the app rather than by
  unit tests; absent, malformed and unresolvable stored data are unit tested.
- A moved folder is only followed when macOS reports the bookmark as stale. A
  deleted folder, or one on a disconnected disk, must be chosen again.
- The folder is remembered but never written to; no session directory is
  created yet.

## Validation status

`xcodebuild ... build` and `xcodebuild ... test` pass locally on Xcode 26.6 (68
tests, 10 suites, no warnings). The signed app carries
`com.apple.security.app-sandbox`,
`com.apple.security.files.bookmarks.app-scope` and
`com.apple.security.files.user-selected.read-write`.

The app was launched with a deliberately invalid bookmark stored: the setup
screen showed "No folder selected" with the explanation that the saved folder
could not be found, offered Choose Folder… and Forget Folder, listed running
applications, restored the remembered application selection, and kept Start
Meeting disabled. Choosing a folder in the open panel and confirming that it
returns after a relaunch needs a human click and has not been automated here.

## Next interval

Interval 4: audio capture from the selected applications — an `SCStream`-backed
capture layer wired to the existing selection and save location, with explicit
start/stop, and still no transcription or transcript writing.
