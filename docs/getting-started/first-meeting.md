# First Meeting

## Before you start

A meeting needs four things. Whenever one of them is missing or needs a look,
the setup screen lists it under **Before You Start**, below the source, with its
state in words as well as an icon and the control that resolves it. When all
four are satisfied the section is not shown, and the line beside **Start
Meeting** says what the meeting will do instead:

| Prerequisite | What it means | How to resolve it |
| --- | --- | --- |
| Save location | The folder every meeting is written to. ScribeKit saves nowhere else. | **Choose Folder…** |
| Screen & System Audio Recording | macOS access to list and record this Mac's applications. | Grant it in System Settings, then **Refresh** |
| Speech recognition | An on-device model installed for the selected language. | Install it in System Settings, then **Check Again** |
| Audio source | At least one running application selected. | Pick one from the list, or **Refresh** |

That is the list for **App Audio**. With **Transcribe from** set to
**Microphone**, the two capture rows become **Microphone access** and
**Microphone input** instead, and Screen & System Audio Recording is not asked
for; see [Microphone Transcription](../using/microphone-transcription.md).

**Start Meeting** is disabled only while one of these is genuinely missing, and
the reason is shown beside the button. When several are missing you are asked
for one at a time, in the order above, which is the order they depend on each
other: without a folder there is nothing to write, and without capture access
there is no list to select a source from.

A prerequisite stops being reported the moment the state behind it becomes
healthy — grant the permission and refresh, install the model and check again,
choose a folder — so no warning outlives its cause.

## Set the meeting up

![ScribeKit's setup form in Microphone mode, with the Input set to MacBook Air Microphone, access shown as Allowed, the meeting title and the save folder.](../images/meeting-setup.png)

The setup screen holds the configuration for the *next* meeting, top to
bottom in the order the choices are made:

- **Source** — **Transcribe from: App Audio / Microphone**, and under it what
  that mode listens to: one or several running applications, each shown with
  its icon and discovered through ScreenCaptureKit with a manual **Refresh**,
  or the microphone input. See
  [Capturing App Audio](../using/capturing-app-audio.md) and
  [Microphone Transcription](../using/microphone-transcription.md).
- **Meeting** — the **Title**, which becomes the transcript's heading and part
  of the session folder name, and the recognition **Language**, fixed for the
  run and never detected automatically.
- **Recording** — for App Audio, whether audio is kept: none, raw or
  compressed. See [Audio Retention](audio-retention.md).
- **Save Location** — the folder the session directory is created in, shown by
  name with its location below it. See [Save Location](save-location.md).

The audio retention mode and the applications last selected are remembered
across launches and matched against a fresh discovery each time.

## Start

Starting a meeting resolves your selection against the applications running at
that moment, creates a dated session folder in the save location, and creates
`transcript.md` inside it before capture begins. A selected application that
has quit produces a clear failure rather than a substitution.

From that point the configuration is fixed, and the Meeting screen changes
from the setup form to the meeting itself.

## While it runs

The top of the screen names the meeting and says what it is doing —
**Listening** for a Microphone meeting, **Capturing** for App Audio,
**Paused**, **Finishing** — with the elapsed time, the source and the language,
and the **Pause** / **Resume** and **Stop** buttons. The transcript fills the
rest of the window. The footer names the file being written and has **Show in
Finder**; **Details** opens the state of capture, recognition and the files,
including the captured-audio figures, for when something needs checking.

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

The finished meeting stays on screen with its transcript and a summary of how
it ended — finished, interrupted, or stopped by a failure, with what that means
for its files. **New Meeting** returns to the setup form; nothing on disk
changes. A meeting that could not start at all is reported at the top of the
setup form instead, where the setting that stopped it can be corrected.

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
