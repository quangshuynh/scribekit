# Audio Retention

Audio retention is opt-in and off by default. When it is on, one file is
written into the session directory beside `transcript.md`, incrementally, while
the meeting runs.

| Mode | File | Behaviour |
| --- | --- | --- |
| No Audio File | none | Default. Only the transcript is kept; no audio touches disk. |
| Raw (Lossless) | `audio.caf` | Linear PCM in a CAF container, in exactly the 48 kHz mono 32-bit float audio ScreenCaptureKit delivered. Measured at 691 MB an hour. |
| Compressed | `audio.m4a` | AAC at 64 kbit/s in an MPEG-4 container. Measured at 31 MB an hour — about a twentieth of the raw size. |

Both files open in QuickTime Player and anything else that reads standard macOS
audio.

## What retention does and does not change

- The recording's time zero is the first captured audio frame, which is the
  same origin the transcript's segment offsets are measured from. Offset *t* is
  second *t* of the file, before and after any number of pauses. See
  [Two-clock Timeline](../internals/two-clock-timeline.md).
- Audio is streamed to disk buffer by buffer as it is captured, never
  accumulated in memory, so a multi-hour meeting costs what a short one does.
- No retention mode changes a word of the transcript.
- A retained recording is what makes [review playback](../using/review-and-playback.md)
  possible. A meeting that kept no audio still lists its uncertain passages and
  says there is nothing to play.

## Honesty about the file

- The file stays on your Mac. Nothing is uploaded.
- **Nothing is encrypted.** It is an ordinary audio file in the folder you
  chose, and it is as private as that folder is. Anyone who can read the folder
  can play the recording.
- A recording that fails or cannot be finalised ends the meeting and is
  reported. Whatever reached the file is closed and left on disk rather than
  deleted or quietly completed — meeting audio cannot be captured again.
- A recording left behind by a crash differs by format: a partly written
  `audio.caf` plays up to the moment ScribeKit stopped, while a partly written
  `audio.m4a` does not open at all, because an MPEG-4 container is completed
  only when the file is closed. ScribeKit reports the file's size and repairs
  neither.
