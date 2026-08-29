# ScribeKit

[![CI](https://github.com/quangshuynh/scribekit/actions/workflows/ci.yml/badge.svg)](https://github.com/quangshuynh/scribekit/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-5-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-26%2B-blue.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A native macOS app for background-first meeting transcription. ScribeKit runs
quietly while you work in other applications and writes timestamped Markdown
transcripts to a folder you choose, on your machine.

**Status: early development.** The foundation is in place; audio capture and
transcription are not implemented yet.

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
- Domain models for the session lifecycle, audio retention, capture sources and
  session metadata, with unit tests.
- Shared Xcode scheme and a macOS CI workflow that builds and runs unit tests.

Nothing is captured, transcribed or written to disk yet. The Start Meeting
control is intentionally disabled.

## Planned

All of the following are *planned*, not available:

- Selecting one or more macOS application audio sources.
- Start / Pause / Resume / Stop, with background operation and a menu bar presence.
- Timestamped Markdown transcripts with autosave and crash/session recovery.
- Transcript search and history.
- Post-meeting review of uncertain passages.
- Optional audio retention (none / raw / compressed).
- Optional derived notes that never modify the raw transcript.

## Audio retention modes

| Mode | Behaviour |
| --- | --- |
| No Audio File | Default. Only the transcript is kept; no audio touches disk. |
| Raw | Lossless audio kept alongside the transcript. Largest files. |
| Compressed | Lossy audio kept as a smaller reviewable record. |

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
  Features/MeetingSetup/  SwiftUI configuration screen
  Models/                 Domain value types (no I/O)
ScribeKitTests/           Swift Testing unit tests
```

Domain models are plain value types with no capture, transcription or
persistence behaviour. Session lifecycle is a single `MeetingState` enum with
explicit transition rules, so contradictory states are unrepresentable.
Capture, speech, persistence and session coordination will be added as separate
layers behind that model.

## Roadmap

1. **Foundation** *(current)* — domain models, configuration UI, tests, CI, docs.
2. Application audio source discovery and selection.
3. Audio capture and on-device transcription.
4. Timestamped Markdown persistence, autosave and recovery.
5. Background and menu bar operation.
6. Transcript history, search and uncertainty review.
7. Optional audio retention and, separately, derived notes.

## Known limitations

- No audio capture, transcription, persistence or recovery yet.
- Source selection and Start Meeting are disabled placeholders.
- The chosen save location is held in memory only and is not persisted.
- CI runs build and unit tests only — no linting, formatting, coverage or UI tests.

## License

MIT — see [LICENSE](LICENSE).
