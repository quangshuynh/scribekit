# Live Transcription

Audio captured from your selected applications is transcribed on this Mac while
the meeting runs.

## Partial and final

Partial recognition is an ephemeral guess. It is displayed, replaced by the
next one, and discarded — it is never appended to a transcript and never
persisted. Only text the recogniser has **finalised** becomes transcript
material, so a sentence heard word by word leaves one entry rather than one per
word.

## Language

The recognition language is chosen explicitly from the locales the recogniser
supports, and locales whose on-device model is not installed are listed and
disabled. The language is fixed for a run and is never detected automatically:
a meeting that changes language is transcribed in the language that was chosen.

## Gaps are reported, not closed over

When audio is not transcribed, the lost time is written into the transcript as
a structural remark rather than silently skipped:

```
> **Transcription gap:** approximately 0.8 seconds of audio around 10:01:41 AM was not transcribed; recognition fell behind capture.
```

Two things produce a gap:

- **Backpressure.** If recognition falls more than about three seconds behind
  capture, the oldest audio is dropped to keep memory bounded, and the lost
  time is reported.
- **A recogniser restart.** A recogniser that stops by itself is restarted at
  most twice; audio arriving during a restart is not transcribed and is counted
  as a gap.

A gap is positioned where the audio fell when the pipeline knows where that
was, and is honest about the length alone when it does not.

## When recognition cannot be brought back

A recogniser that has used up its restarts ends the meeting: capture stops, the
transcript and the recording are closed and kept, and the session is recorded
as failed rather than left capturing audio that nothing transcribes.

## Uncertainty

Passages the recogniser was unsure about are collected while the meeting runs
and surfaced afterwards in History, against the retained audio where there is
any. Nothing is corrected or rewritten. See
[Review & Playback](review-and-playback.md).
