# Releases

ScribeKit is in early development and has no tagged release yet. There is no
signed distributable build; running it means
[building from source](../getting-started/build-and-run.md).

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

## Planned, not available

- Continuing an interrupted meeting into the same session.

Measured evidence gathered along the way — long-session soaks, retention-mode
costs, profiling results and the crash they surfaced — is recorded in
[Performance & Energy](../PERFORMANCE.md).
