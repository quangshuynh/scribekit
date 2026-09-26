# Live Transcription

Audio captured from your selected applications is transcribed on this Mac while
the meeting runs.

## On screen

During a meeting the transcript takes the Meeting screen: each finalised
passage beside the time it began, measured from the start of the meeting, in a
column kept to a comfortable reading width however wide the window is. The
status, elapsed time and controls sit above it, and the file being written
below it.

## Partial and final

Partial recognition is an ephemeral guess. It is displayed, replaced by the
next one, and discarded — it is never appended to a transcript and never
persisted. Only text the recogniser has **finalised** becomes transcript
material, so a sentence heard word by word leaves one entry rather than one per
word. On screen the guess is the last line, in grey italic and with no time
beside it, and it is no longer shown once the meeting has ended.

If audio goes untranscribed during the meeting, a notice above the transcript
says how many seconds were lost, so the gap is visible before the meeting is
over.

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

## One incident, one marker

A recogniser that has fallen behind does not lose audio once. It keeps losing
it for as long as it stays behind, and the pipeline sees that as a loss every
half second or so. Those observations are summarised into one **incident**
rather than written out one by one, so a meeting that spent four minutes behind
capture leaves one marker instead of several hundred:

```
> **Transcription gap:** approximately 215.0 seconds of audio was not transcribed between 11:38:00 AM and 11:41:23 AM; recognition fell behind capture.
```

Read that sentence as two separate facts. The **range** is how long the meeting
was in trouble; the **seconds** are how much audio that cost. They are not the
same number, and the range does not mean that everything inside it is missing:
recognition goes on transcribing between the losses, so speech from inside the
range is usually in the transcript above and below the marker. An incident
narrower than a second keeps the concise wording that names the moment instead.

Nothing is merged that ScribeKit cannot show belongs together. A new incident
is started whenever the backlog demonstrably caught up in between, and a pause,
a recogniser restart, capture ending or the meeting stopping all close the
incident that was open — so two separate spells of trouble stay two markers.

The marker is written when the incident ends, which is the first moment its
range is known. While one is going on, the session record beside the transcript
notes that it started, so a ScribeKit that never gets to finish still leaves
evidence of it: see [Recovery](recovery.md).

## When recognition cannot be brought back

A recogniser that has used up its restarts ends the meeting: capture stops, the
transcript and the recording are closed and kept, and the session is recorded
as failed rather than left capturing audio that nothing transcribes.

## Uncertainty

Passages the recogniser was unsure about are collected while the meeting runs
and surfaced afterwards in History, against the retained audio where there is
any. Nothing is corrected or rewritten. See
[Review & Playback](review-and-playback.md).
