# Releases

ScribeKit's first release, **v0.1.0**, is a **source release**. No signed or
notarized application is published with it, so running ScribeKit means
[building it from source](../getting-started/build-and-run.md). That is a
distribution limitation and nothing else: a build made from this source runs
entirely on your Mac, with no account and no network.

## v0.1.0

The application's release identity is frozen. It builds as version **0.1.0**,
build **1**, bundle identifier **`quang.ScribeKit`**, requiring **macOS 26.5 or
later** and tested on Apple Silicon; the identifier is the one every existing
sandbox container and security-scoped bookmark on a developer's Mac already
uses, and it was kept rather than changed on the eve of a first release. A
Release archive carries the App Sandbox, app-scoped bookmarks and user-selected
read/write entitlements and nothing else — no network client — with the
hardened runtime enabled and `get-task-allow` absent.

**There is no signed disk image.** Publishing a macOS application outside the
App Store means a Developer ID Application certificate and Apple notarization,
and neither is available for this release. The release therefore stops at a
verified archive: the export, the notarization, the stapling, the Gatekeeper
assessment and a packaged first install are all unevidenced, and none of them
is claimed. Signed distribution is deferred, not abandoned; see
[Building](../development/building.md) for the sequence that runs once a
certificate exists.

## Changelog

Notable changes are recorded in
[`CHANGELOG.md`](https://github.com/quangshuynh/scribekit/blob/main/CHANGELOG.md)
in the repository.

## Development history

Work proceeds in numbered intervals, each one a milestone that is either
implemented or not — nothing is described here as working before it is.

| # | Interval | State |
| --- | --- | --- |
| 1 | Foundation — domain models, configuration UI, tests, CI | Done |
| 2 | Application audio source discovery and selection | Done |
| 3 | Durable save location and session configuration | Done |
| 4 | Audio capture from the selected applications | Done |
| 5 | On-device transcription | Done |
| 6 | Timestamped Markdown persistence and autosave | Done |
| 7 | Crash and session recovery | Done |
| 8 | Optional audio retention | Done |
| 9 | Background and menu bar lifecycle | Done |
| 10 | Transcript history and local search | Done |
| 11 | Uncertainty review against the retained audio | Done |
| 12 | Pausing and resuming a meeting | Done |
| 13 | Derived notes that never modify the raw transcript | Done |
| 14 | Reliability | Done |
| 15 | Performance and energy measurement | Done |
| 16 | Capture crash | Done |
| 17 | Soak and interface performance | Done |
| 18 | Runtime-truth profiling | Done |
| 19 | Presentation lifecycle, and explicit AM/PM in transcript times | Done |
| 20 | Start readiness, and endings described rather than implied | Done |
| 21 | Application menus, keyboard routes and accessible presentation | Done |
| 22 | Local diagnostics and supportability | Done |
| 23 | Interrupted-session continuation: investigated, deferred | Decided |
| 24 | History and notes usability assessment | Done |
| 25 | Release hardening and manual evidence | Done |
| 26 | Application identity, icon and macOS distribution | Done — distribution deferred |
| 27 | v0.1.0 source-release presentation | Done |

## Not planned for the first release

- **Continuing an interrupted meeting into the same session.** Investigated in
  Interval 23 and deferred: it cannot be done without a second recording file
  per session, and a meeting killed while capturing has recorded no captured
  length to continue its offsets from. An interrupted meeting is preserved and
  a new meeting is started instead. See
  [Limitations](limitations.md) and [Recovery](../using/recovery.md).

Measured evidence gathered along the way — long-session soaks, retention-mode
costs, profiling results and the crash they surfaced — is recorded in
[Performance & Energy](../PERFORMANCE.md).
