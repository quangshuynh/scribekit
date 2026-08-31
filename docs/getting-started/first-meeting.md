# First Meeting

## Before you start

The top of the setup screen lists the four things a meeting needs, each with
its state in words as well as an icon, and each with the control that resolves
it:

| Prerequisite | What it means | How to resolve it |
| --- | --- | --- |
| Save location | The folder every meeting is written to. ScribeKit saves nowhere else. | **Choose Folder…** |
| Screen & System Audio Recording | macOS access to list and record this Mac's applications. | Grant it in System Settings, then **Refresh** |
| Speech recognition | An on-device model installed for the selected language. | Install it in System Settings, then **Check Again** |
| Audio source | At least one running application selected. | Pick one from the list, or **Refresh** |

**Start Meeting** is disabled only while one of these is genuinely missing, and
the reason is shown beside the button. When several are missing you are asked
for one at a time, in the order above, which is the order they depend on each
other: without a folder there is nothing to write, and without capture access
there is no list to select a source from.

A prerequisite stops being reported the moment the state behind it becomes
healthy — grant the permission and refresh, install the model and check again,
choose a folder — so no warning outlives its cause.

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

## How a meeting can end

Three endings, and ScribeKit keeps them apart:

- **Finished** — you stopped it. Every artifact was flushed and closed.
- **Interrupted** — capture stopped without being asked to, so ScribeKit ended
  the meeting. Everything captured up to that moment reached the transcript and
  any recording, and both were closed. It is never described as finished, and
  ScribeKit does not continue it: start a new meeting.
- **Failed** — a durable artifact stopped being written: the transcript, the
  retained recording, or a recogniser that could not be brought back. The
  meeting was stopped rather than left running with nothing saving what it
  heard.

Whichever it was, the setup screen shows what happened, what it means for this
meeting's files, and what you can do next, with a **Show in Finder** button for
the transcript. See [Failure Semantics](../reliability/failure-semantics.md).

Quitting during a meeting asks first, and stopping from that prompt finishes
the transcript and the audio file before the application exits — quitting is
not a crash, and does not leave a meeting for the next launch to discover.
