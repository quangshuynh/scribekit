# Audio Capture

## Format and path

ScreenCaptureKit delivers 48 kHz mono 32-bit float audio. Buffers are copied,
converted and queued on the capture system's own queue and never cross the main
actor; the interface sees coalesced summaries and transcription events only.

Audio arriving in a different format from the one capture was asked for is
refused rather than resampled, because a file's format is fixed when it is
created. On this Mac ScreenCaptureKit has always delivered the format that was
requested.

Recognition consumes 16 kHz audio, so the 48 kHz capture is resampled on the
capture queue before it reaches the recogniser.

## One producer, two consumers

Captured buffers are broadcast to two consumers: the transcription input and,
when retention is on, the audio retainer. Both are started before capture
begins, so both see the same first buffer — which is why a transcript offset
and a position in the recording name the same frame. See
[Two-clock Timeline](two-clock-timeline.md).

Retained audio is a consumer of captured buffers rather than a queue in front
of one, so audio is written where it arrives and no backlog can build up.

## Bounded by construction

A live capture pipeline uses bounded memory and never routes high-frequency
audio callbacks through the main actor:

- No part of the pipeline accumulates a meeting's audio in memory. Retained
  audio is streamed to disk as it is captured.
- Every queue between a producer of audio and a consumer of it is bounded, and
  overflow is measured and reported. An unbounded stream between capture and a
  slower consumer is a memory leak with a delay on it.
- Nothing on the delivery path grows with the length of a meeting — not memory,
  and not stack. The last buffer of a meeting reaches every consumer through
  the same call depth as the first.

Recognised text may grow with the meeting. Raw audio may not.

## Backpressure

If recognition falls more than about three seconds behind capture, the oldest
audio is dropped to keep memory bounded, and the lost time is reported as a gap
in the transcript. Evicted buffers still reach the recording when retention is
on — the recording is then the only place that audio exists.

No screen or video content is processed at any point.
