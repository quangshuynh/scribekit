# CONTEXT.md

Current working state of the repository. Keep this short and current; see
`README.md` for the project and `AGENTS.md` for the engineering rules.

## Current milestone

Interval 2 — application source discovery and selection. Complete.

## Current implementation

- Domain value types in `ScribeKit/Models/`: `MeetingState`,
  `AudioRetentionMode`, `CaptureSource`, `MeetingSession`. `CaptureSource` is
  unchanged from Interval 1; an application source is identified by its bundle
  identifier, which survives relaunch.
- `ScribeKit/Capture/`: `CaptureSourceProviding` (discovery abstraction) with
  `CaptureSourceDiscoveryError`, `DiscoveredApplication` (framework-neutral
  description of one running application), `CaptureSourceCatalog` (pure
  filtering/mapping policy) and `ScreenCaptureKitSourceProvider` (reads
  `SCShareableContent`; no `SCStream`, no capture, no window content).
- `ScribeKit/Features/MeetingSetup/MeetingSetupSourcesModel.swift`: `@Observable`
  main-actor state owner holding discovery state (idle/loading/loaded/failed),
  the selected identifiers, and the names dropped by the last refresh.
- `MeetingSetupView` renders those states, one checkbox per application,
  a Refresh button, and keeps Start Meeting disabled.
- `ScribeKitTests/`: Swift Testing suites for the four models, the catalog and
  the sources model (33 tests, 6 suites).

No capture, transcription, persistence, recovery or background behaviour exists.

## Established decisions

- Interval 1 decisions still hold (macOS 26.5 target, Swift Testing, single
  lifecycle enum, no `failed` state, metadata-only `MeetingSession`, ad-hoc CI
  signing, no third-party dependencies).
- ScreenCaptureKit types never leave `ScreenCaptureKitSourceProvider`; the
  state owner and view see only `CaptureSource` values.
- Filtering policy: an application is offered only when it owns an ordinary
  on-screen window (`windowLayer == 0`), has a non-empty bundle identifier and
  name, and is not ScribeKit itself. Results are de-duplicated by bundle
  identifier and sorted by name for deterministic ordering.
- Refresh is manual plus once on appearance. There is no timer and no polling.
- A successful refresh keeps selections that still exist, drops the rest, and
  names the dropped ones once. A failed refresh leaves the selection untouched,
  because failure says nothing about which applications are running.
- Selection state is exposed as checkboxes, so it is conveyed by control state
  and to accessibility rather than by colour.

## Known limitations

- Discovery needs Screen Recording permission. When it is missing,
  `SCShareableContent` fails with `SCStreamError.userDeclined` and the screen
  shows a permission message; ScribeKit does not prompt or open System Settings
  itself yet.
- Windowless and menu-bar-only applications are not offered as sources; the
  discovery API gives no reliable way to tell a useful background application
  from a helper process.
- The list does not update as applications launch or quit; the user refreshes.
- `ScreenCaptureKitSourceProvider` itself is not unit tested — it is a thin
  adapter, and its mapping and filtering are tested through
  `CaptureSourceCatalog`.
- Save location is still not persisted; no security-scoped bookmark.

## Validation status

`xcodebuild ... build` and `xcodebuild ... test` pass locally on Xcode 26.6
(33 tests, 6 suites). The app was launched and the setup screen listed real
running applications with checkboxes and a Refresh button, excluding ScribeKit
itself, with Start Meeting disabled. Selection and refresh reconciliation are
covered by unit tests rather than by UI automation.

## Next interval

Interval 3: audio capture from the selected applications — an `SCStream`-backed
capture layer wired to the existing selection, with explicit start/stop and
still no transcription or persistence.
