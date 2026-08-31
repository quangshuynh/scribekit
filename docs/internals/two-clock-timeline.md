# Two-clock Timeline

A meeting has two clocks and they are not interchangeable.

| Clock | Advances | Measures |
| --- | --- | --- |
| Captured media time | Only while capture is running | Transcript offsets, retained audio, and anything that seeks into that audio |
| Wall-clock time | Always, including while paused | Human-readable timestamps, elapsed time, `**Duration:**` |

An offset names the same second of the recording however often a meeting was
suspended, and no suspension is ever padded into the file as silence or held in
a buffer. Human-readable timestamps account for the time capture was not
running — but a timestamp already written is never recomputed to do so.

## One origin, two consumers

A retained recording's time zero is the first captured frame that reached the
retainer, and a transcript segment's offset is measured from the first captured
frame that reached the transcription input. Those are the same frame: both are
consumers of the same broadcasting sample consumer, both are started before
capture starts, and both therefore see the same buffer first.

Segment offset *t* is second *t* of the audio file, frame for frame, with no
synchronisation machinery and nothing to keep in step. That is what makes
[review playback](../using/review-and-playback.md) a direct seek.

Pausing does not move that. Media time advances only while capture runs, so a
pause adds nothing to a segment's offset and nothing to the recording: the
audio after a resume continues from the frame before the pause, with no
synthetic silence and nothing buffered across it.

## Timestamp derivation

A segment's wall-clock time is:

```
epoch wall start + (segment.startTime - epoch media start)
```

For a meeting that was never paused there is one epoch — media zero at the
session start — so this reduces to `session start + segment.startTime`. Each
resume appends an epoch, and a segment uses the last epoch whose media start it
is at or past.

## Where it is inexact, honestly

- The session starts a moment before the first frame arrives, so a stated
  wall-clock time can be under a second early. The precise relationship is
  between the offsets and the file, not between the clock and the file.
- The transcription input does not advance its elapsed clock for a buffer whose
  conversion to the recogniser's format fails, while the recording still holds
  that buffer's frames — so a conversion failure would slide the two apart by
  the length of the buffers it lost. No conversion has been observed to fail.
  Buffers evicted under backpressure do not have this problem: the clock
  advances for them and they stay in the recording.
- The transcript's `**Duration:**` is the meeting's wall-clock length, and
  `**Captured:**`, written only for a meeting that was paused, is the length of
  the recording. Neither is derived from the other.
- A pause is a boundary in the recording, not a silence in it, so the moment a
  pause ended is audible as a cut and the recording alone does not tell you how
  long the pause lasted. The transcript does.
