# Review & Playback

After a meeting, its detail pane in History lists the passages worth a second
listen: the recognised wording exactly as the transcript has it, the timestamp
it was written under, a High, Medium or Low priority, and the reason it was
flagged.

## The two reasons

They are different kinds of thing, and ScribeKit keeps them distinct:

- **Recognition confidence was low** — Apple's own judgement, read from the
  confidence the recogniser attaches to each word it finalises. ScribeKit uses
  it to decide whether a passage is flagged and never shows it as a number or a
  percentage, because Apple documents no scale for it.
- **Near audio that was not transcribed** — ScribeKit's observation of its own
  pipeline: the passage is the first one finalised after a stretch of audio
  recognition never covered.

## Playback

When the meeting kept a recording, each passage offers **Play Audio**, which
seeks to that passage's own position in the recording — a couple of seconds
before it, stopping shortly after — with pause and stop beside it. This seek is
direct because transcript offsets and the recording share one origin; see
[Two-clock Timeline](../internals/two-clock-timeline.md).

The recording is read from disk as it plays, so a multi-hour file costs what a
short one does, and it is never modified.

A meeting that kept no recording still lists its passages and says there is no
audio to play. A recording from a meeting that was killed before it could be
finalised is reported as one that will not open, rather than quietly skipped.

## Review never changes the transcript

Nothing is corrected, replaced, rewritten or suggested. `transcript.md` carries
no confidence annotation, and listening to a passage leaves every file in the
session folder byte-identical. Meetings recorded before review existed simply
have no review information and work exactly as they did.

## Marking a passage

Each passage carries **Mark Reviewed** and **Mark Unreviewed**, recording that
you have dealt with it. The mark is your own disposition, not a claim about the
words: it is written the moment you make it, to a separate file, and
`review.json` — what the recogniser observed — is never touched. See
[Meeting Notes](meeting-notes.md) and
[Derived Metadata](../reference/derived-metadata.md).
