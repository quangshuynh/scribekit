# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Added

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
- Bounded capture accounting: delivered buffers are described on the capture
  queue and discarded, and the interface shows coalesced counts, duration,
  the format actually received and a peak level.
- Start and stop capture controls in the meeting setup screen, with capture
  state, honest permission and unavailable-source failures, and interruption
  reporting when the system stops a running stream. Start Meeting remains
  disabled.
- App sandbox entitlement for app-scoped bookmarks, and read-write access to
  user-selected folders.
- GitHub Actions workflow that builds and tests on macOS.
- Project documentation: `README.md`, `AGENTS.md`, `CLAUDE.md`, `CONTEXT.md`,
  `CONTRIBUTING.md`.
