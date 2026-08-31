# First Meeting

## Set the meeting up

The setup screen holds the configuration for the *next* meeting:

- **Title** — becomes the transcript's heading and part of the session folder
  name.
- **Save location** — the folder the session directory is created in. See
  [Save Location](save-location.md).
- **Audio retention** — none, raw or compressed. See
  [Audio Retention](audio-retention.md).
- **Recognition language** — fixed for the run; it is never detected
  automatically.
- **Sources** — one or several running applications, discovered through
  ScreenCaptureKit with a manual **Refresh**. See
  [Capturing App Audio](../using/capturing-app-audio.md).

The audio retention mode and the applications last selected are remembered
across launches and matched against a fresh discovery each time.

## Start

Starting a meeting resolves your selection against the applications running at
that moment, creates a dated session folder in the save location, and creates
`transcript.md` inside it before capture begins. A selected application that
has quit produces a clear failure rather than a substitution.

From that point the configuration is fixed. Editing the setup screen while a
meeting runs configures the next meeting and cannot reach the running one; its
controls are disabled for the duration.

## While it runs

Partial recognition appears as an ephemeral guess and is replaced by the next
one. Finalised text accumulates as transcript spans, so a sentence heard word
by word leaves one entry rather than one per word — and only finalised text
reaches the file. See [Live Transcription](../using/live-transcription.md).

Each finalised span is appended to `transcript.md` as it is recognised, so the
file is readable in another editor while the meeting is still running.

You can [pause and resume](../using/pause-and-resume.md), close the window, or
work in other applications; the meeting keeps going. See
[Background Operation](../using/background-operation.md).

## Stop

Stop ends capture, lets the recogniser finalise the audio it already has,
closes the audio file if there is one, then flushes and closes the transcript,
and only then records the session as completed. Stop from the menu bar is the
same stop.

Quitting during a meeting asks first, and stopping from that prompt finishes
the transcript and the audio file before the application exits — quitting is
not a crash, and does not leave a meeting for the next launch to discover.
