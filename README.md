<p align="center">
  <img src="docs/images/scribekit-logo2.png" alt="ScribeKit app icon" width="256">
</p>

# ScribeKit

[![CI](https://github.com/quangshuynh/scribekit/actions/workflows/ci.yml/badge.svg)](https://github.com/quangshuynh/scribekit/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-5-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-26%2B-blue.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A native macOS app for background-first meeting transcription. ScribeKit runs
quietly while you work in other applications and writes timestamped Markdown
transcripts to a folder you choose, on your machine.

**Status: early development.** Audio capture from selected applications and
live on-device transcription work; transcript writing is not implemented yet.

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
- Discovery of running applications through ScreenCaptureKit, with selection of
  one or several of them as intended audio sources, and a manual Refresh.
- Audio capture from the selected applications, started and stopped explicitly,
  with the selection resolved against the applications running at that moment
  and a clear failure when one of them has quit. Capture reports the format and
  level it is actually receiving.
- Live speech transcription of that audio, recognised on this Mac with Apple's
  `SpeechAnalyzer` and an installed on-device language model. Partial text is
  shown as an ephemeral guess and finalised text accumulates as transcript
  segments, so a sentence heard word by word leaves one entry rather than one
  per word.
- An explicit recognition language, chosen from the locales the recogniser
  supports, with the ones whose model is not installed listed and disabled
  rather than silently unavailable.
- Honest reporting of a missing model, an unsupported language, a recogniser
  that stops by itself, and audio that recognition fell too far behind to
  transcribe.
- A save folder chosen in the system open panel and remembered across launches
  with a security-scoped bookmark, with honest reporting when the folder has
  been moved, deleted or had its access revoked, and controls to replace or
  forget it.
- Remembered setup choices: the audio retention mode and the applications last
  selected, matched against a fresh discovery on each launch.
- Domain models for the session lifecycle, audio retention, capture sources and
  session metadata, with unit tests.
- Shared Xcode scheme and a macOS CI workflow that builds and runs unit tests.

The transcript exists only in memory: no transcript, audio file or session
directory is written. Choosing a save folder only remembers the folder. The
Start Meeting control is intentionally disabled, because a meeting implies a
transcript ScribeKit cannot yet produce.

Listing applications and capturing their audio require Screen & System Audio
Recording permission, which macOS asks for the first time ScribeKit looks for
sources. Without it the screen reports the missing permission instead of a list
or a capture. Transcription itself asks for no permission at all, because it
runs against a speech model on this Mac rather than through a service.

## On-device recognition

Speech recognition uses `SpeechAnalyzer` and `SpeechTranscriber`, Apple's
on-device speech APIs, against a language model installed on this Mac.
ScribeKit checks that the model for the selected language is installed and
refuses to start when it is not; it never downloads one on your behalf and
never falls back to network recognition. It does not use `SFSpeechRecognizer`,
the older API that can send audio to Apple's servers. The app ships without the
network client entitlement, so the sandbox does not permit it to open a network
connection at all.

## Planned

All of the following are *planned*, not available:

- Meeting lifecycle with background operation and a menu bar presence.
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
  Capture/                Application source discovery and audio capture
  Features/MeetingSetup/  SwiftUI configuration screen and its state
  Models/                 Domain value types (no I/O)
  Persistence/            Save-location storage and session layout policy
  Transcription/          On-device speech recognition behind its own boundary
ScribeKitTests/           Swift Testing unit tests
```

Domain models are plain value types with no capture, transcription or
persistence behaviour. Session lifecycle is a single `MeetingState` enum with
explicit transition rules, so contradictory states are unrepresentable.
Capture, speech, persistence and session coordination are separate layers
behind that model: source discovery sits behind the `CaptureSourceProviding`
protocol, capture behind `AudioCapturing` and recognition behind
`SpeechTranscribing`, and ScreenCaptureKit and Speech types are adapted at
those boundaries rather than reaching the UI. Audio buffers are copied,
converted and queued on the capture system's own queue and never cross the main
actor; the interface sees coalesced summaries and transcription events only.
Save-location storage sits behind `SaveLocationPersisting`, so security-scoped
bookmark data never reaches the setup screen, and session directory naming is a
pure policy separate from any filesystem work.

A future session will be laid out as a directory named from its date and title,
holding `transcript.md` with ScribeKit's own metadata in a hidden `.scribekit`
subdirectory, so a transcript stays readable without this app.

## Roadmap

1. **Foundation** — domain models, configuration UI, tests, CI, docs.
2. **Application audio source discovery and selection**.
3. Durable save location and session configuration.
4. **Audio capture from the selected applications**.
5. **On-device transcription** *(current)*.
6. Timestamped Markdown persistence, autosave and recovery.
7. Background and menu bar operation.
8. Transcript history, search and uncertainty review.
9. Optional audio retention and, separately, derived notes.

## Known limitations

- No transcript writing or recovery yet. The transcript is held in memory for
  the length of a run and lost when it ends; no audio is kept, played back or
  written anywhere.
- Start Meeting is a disabled placeholder; capture and transcription have their
  own control.
- Recognition needs an installed on-device language model. Languages whose
  model is absent are listed but cannot be selected, and ScribeKit does not
  install them.
- The recognition language is fixed for a run and is never detected
  automatically; a meeting that changes language is transcribed in the language
  that was chosen.
- Recognition consumes 16 kHz audio, so 48 kHz capture is resampled on the
  capture queue before it reaches the recogniser.
- If recognition falls more than about three seconds behind capture, the oldest
  audio is dropped to keep memory bounded and the lost time is reported as a
  gap in the transcript.
- A recogniser that stops by itself is restarted at most twice; audio arriving
  during a restart is not transcribed and is counted as a gap.
- ScreenCaptureKit has no audio-only stream, so the capture filter names a
  display as well as the selected applications. No screen output is added, so
  no frame is delivered or processed, but the permission macOS asks for is the
  screen recording one.
- The captured set is fixed when capture starts. Changing the selection while
  capture is running does not change what is being captured; stop and start
  again.
- If a captured application quits mid-capture, ScreenCaptureKit keeps the
  stream alive and delivers silence for it. ScribeKit does not substitute
  another source, and the next start reports the application as unavailable.
- Only applications owning an ordinary on-screen window are listed, so a
  menu-bar-only or windowless application is not offered as a source.
- The application list is refreshed on appearance and on demand, not
  automatically as applications start and quit.
- Nothing is written to the chosen folder yet; ScribeKit only remembers it and
  checks it is still reachable at launch.
- Access to the folder is held only while it is being validated. A session-long
  lease arrives with the code that writes transcripts.
- A moved folder is followed only when macOS reports its bookmark as stale; a
  folder that was deleted, or whose disk is absent, has to be chosen again.
- CI runs build and unit tests only — no linting, formatting, coverage or UI tests.

## License

MIT — see [LICENSE](LICENSE).
