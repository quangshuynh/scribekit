# ScribeKit

ScribeKit is a native macOS app for background-first meeting transcription. It
captures audio from the applications you select, transcribes it on your Mac,
and writes a timestamped Markdown transcript into a folder you chose.

Nothing leaves the machine. There are no accounts, no cloud database, no
telemetry and no analytics, and the app ships without the network client
entitlement, so the sandbox does not permit it to open a network connection at
all.

!!! note "Status: v0.1.0 — source release"

    ScribeKit's first release is **v0.1.0**. Audio capture from
    selected applications, live on-device transcription, durable Markdown
    transcripts, pause and resume, crash recovery, optional audio retention,
    background operation with a menu bar item, transcript history and search,
    uncertainty review with playback, local meeting notes and diagnostic export
    all work end to end.

    **There is no prebuilt signed or notarized download.** v0.1.0 is
    published as source and is
    [built from source](getting-started/build-and-run.md). See
    [Releases](reference/releases.md) for why, and
    [Limitations](reference/limitations.md) for what is not built.

## What it does

<div class="grid cards" markdown>

- **Captures the apps you pick.** Audio comes from the applications you select
  through ScreenCaptureKit, not from the whole system and not from a
  microphone. See [Capturing App Audio](using/capturing-app-audio.md).

- **Transcribes on this Mac.** Apple's `SpeechAnalyzer` and
  `SpeechTranscriber` against a language model installed locally. There is no
  network fallback. See [On-device Speech](internals/on-device-speech.md).

- **Writes Markdown you own.** `transcript.md` is appended to as speech is
  finalised and is readable in any editor while the meeting is still running.
  See [Transcript Format](reference/transcript-format.md).

- **Keeps running behind the window.** The meeting belongs to the application,
  not the window. Closing the window keeps capturing and releases the
  interface. See [Background Operation](using/background-operation.md).

</div>

## What it will not do

- It will not rewrite your transcript. Recognised speech is source material:
  no AI cleanup, no summarisation, no grammar correction, no inferred
  substitutions. Notes and reviewed marks are derived artifacts kept in a
  separate file that cannot reach the transcript.
- It will not hide the fact that it is recording. Capture is always visible.
- It will not claim a meeting finished when it did not. A capture stream that
  dies under a meeting is recorded as an interruption, not as a completion.
- It will not pretend to be more certain than the recogniser was. Passages the
  recogniser was unsure about, and audio that was never transcribed, are
  surfaced rather than smoothed over.

## Start here

- New to the app: [Requirements](getting-started/requirements.md) →
  [Build & Run](getting-started/build-and-run.md) →
  [First Meeting](getting-started/first-meeting.md)
- Curious how it holds together: [Architecture](internals/architecture.md)
- Worried about your data: [Local-first Model](privacy/local-first.md)
- Measured evidence for the efficiency claims:
  [Performance & Energy](PERFORMANCE.md)
