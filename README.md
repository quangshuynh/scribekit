<p align="center">
  <img src="docs/images/scribekit-logo2.png" alt="ScribeKit app icon" width="256">
</p>

# ScribeKit

[![CI](https://github.com/quangshuynh/scribekit/actions/workflows/ci.yml/badge.svg)](https://github.com/quangshuynh/scribekit/actions/workflows/ci.yml)
[![Docs](https://github.com/quangshuynh/scribekit/actions/workflows/docs.yml/badge.svg)](https://github.com/quangshuynh/scribekit/actions/workflows/docs.yml)
[![Swift](https://img.shields.io/badge/Swift-5-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-26%2B-blue.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A native macOS app for background-first meeting transcription. ScribeKit runs
quietly while you work in other applications, captures audio from the apps you
select, transcribes it on your Mac, and writes timestamped Markdown transcripts
into a folder you chose.

**📖 [Documentation](https://quangshuynh.github.io/scribekit/)** — guides,
architecture, reliability semantics, privacy model and reference.

**Status: early development.** Audio capture from selected applications, live
on-device transcription, durable Markdown transcripts, pause and resume, crash
recovery, optional audio retention, background operation with a menu bar item,
transcript history and search, uncertainty review with playback, and local
meeting notes all work end to end.

## What it does

- **Captures the apps you pick**, through ScreenCaptureKit — not the whole
  system, and not a microphone.
  [Details](https://quangshuynh.github.io/scribekit/using/capturing-app-audio/)
- **Transcribes on this Mac** with Apple's `SpeechAnalyzer` and
  `SpeechTranscriber`, against a locally installed model, with no network
  fallback.
  [Details](https://quangshuynh.github.io/scribekit/internals/on-device-speech/)
- **Writes Markdown you own.** `transcript.md` is appended to as speech is
  finalised, so it is readable in any editor while the meeting is still
  running.
  [Details](https://quangshuynh.github.io/scribekit/reference/transcript-format/)
- **Keeps running behind the window.** The meeting belongs to the application,
  not the window; closing the window keeps capturing and releases the
  interface.
  [Details](https://quangshuynh.github.io/scribekit/using/background-operation/)
- **Pauses and resumes**, with separate wall-clock and captured-media clocks so
  an offset always names the same second of the recording.
  [Details](https://quangshuynh.github.io/scribekit/using/pause-and-resume/)
- **Reads meetings back** through a read-only history, local substring search,
  uncertainty review against retained audio, and Markdown notes kept in a
  sidecar of their own.
  [Details](https://quangshuynh.github.io/scribekit/using/history-and-search/)
- **Retains audio only if you ask.** None by default; optionally raw `.caf` or
  compressed `.m4a`.
  [Details](https://quangshuynh.github.io/scribekit/getting-started/audio-retention/)

## Philosophy

- **Local-first.** Transcription and storage happen on your Mac. No accounts,
  no cloud database, no telemetry, no analytics. The app ships without the
  network client entitlement, so the sandbox does not permit it to open a
  network connection at all.
- **Raw transcripts are source material.** ScribeKit never silently rewrites a
  transcript with AI, summarisation, grammar cleanup or inferred substitutions.
  Notes and reviewed marks are derived, stored separately, and cannot reach the
  transcript.
- **Honest about uncertainty.** Low-confidence recognition and audio that was
  never transcribed are surfaced rather than quietly smoothed over.
- **Honest about endings.** A capture stream that dies under a meeting is
  recorded as an interruption, not as a completion.
- **Never hidden.** Capture is always visible to the user.
- **Not encrypted.** Your transcripts and recordings are ordinary files in the
  folder you chose, as private as that folder is.

See [Privacy & Data](https://quangshuynh.github.io/scribekit/privacy/local-first/).

## Requirements

- macOS 26 or later
- Xcode 26 or later
- An installed on-device speech model for the recognition language

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

## Documentation

The full documentation is at
**<https://quangshuynh.github.io/scribekit/>**, built from `docs/`:

| Section | What is there |
| --- | --- |
| [Getting Started](https://quangshuynh.github.io/scribekit/getting-started/requirements/) | Requirements, building, your first meeting, save location, audio retention |
| [Using ScribeKit](https://quangshuynh.github.io/scribekit/using/capturing-app-audio/) | Capture, live transcription, pause/resume, background operation, history, review, notes, recovery |
| [How It Works](https://quangshuynh.github.io/scribekit/internals/architecture/) | Architecture, meeting lifecycle, audio path, on-device speech, persistence, the two clocks, session artifacts, presentation lifecycle |
| [Reliability](https://quangshuynh.github.io/scribekit/reliability/failure-semantics/) | Failure semantics, crash recovery, and measured performance and energy evidence |
| [Privacy & Data](https://quangshuynh.github.io/scribekit/privacy/local-first/) | Local-first model, what is written where, permissions, network policy |
| [Development](https://quangshuynh.github.io/scribekit/development/building/) | Building, testing, architecture boundaries, docs, contributing |
| [Reference](https://quangshuynh.github.io/scribekit/reference/transcript-format/) | Transcript format, the three sidecars, limitations, releases |

To build the docs locally:

```bash
python3 -m venv .venv && source .venv/bin/activate && pip install -r docs/requirements.txt && mkdocs serve
```

## Known limitations

ScribeKit is deliberately narrow, and a number of things are simply not built:
no continuation of an interrupted meeting, no editing, renaming, deleting or
exporting from History, no encryption, no fuzzy or semantic search, and no
claim to be crash-proof. The full list is in
[Limitations](https://quangshuynh.github.io/scribekit/reference/limitations/).

Engineering rules live in [AGENTS.md](AGENTS.md); notable changes are in
[CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).
