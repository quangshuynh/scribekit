# Pause & Resume

Pause stops capturing. It is not a mute, not a hidden window and not a stop:
the capture stream is torn down, the recogniser finalises the audio it has
already been given, and the meeting's transcript, its retained recording, its
session record and the lease on your save folder all stay open.

Pause and Resume are available from the main window and from the menu bar.

## Two clocks

Pausing is where the [two clocks](../internals/two-clock-timeline.md) visibly
diverge:

- **Captured time** advances only while capture runs. Transcript offsets and
  the retained recording are both measured in it, so a passage at offset *t* is
  second *t* of the audio file, before and after a pause alike. A five minute
  pause adds nothing to the recording: no silence is inserted, and the audio
  after the pause continues straight from the last frame before it.
- **Wall-clock time** keeps running while the meeting is paused. It is what the
  transcript's human-readable timestamps state, what the elapsed time in the
  window and the menu bar counts, and what `**Duration:**` in the footer
  reports. A transcript that was paused also states `**Captured:**`, the
  shorter one — the length of the recording.

## What is written

The pause itself is written into the transcript as two structural blockquotes:

```
> **Paused:** 11:42:10 AM. Capture stopped here; nothing was recorded until the meeting resumed.

> **Resumed:** 11:48:32 AM, after 6 min 22 s paused.
```

They are ScribeKit's own remarks, marked the way gap markers are, and they say
what happened rather than claiming speech was missed: you paused, so there was
nothing to miss. Recognised text is untouched, and timestamps already written
are never recomputed.

## Resuming

Resume builds a stream again for the applications the meeting was *started*
with — editing the setup screen while paused configures the next meeting, not
this one — and the same transcript and the same recording carry on.

A resume that fails, because the application you were capturing has quit for
instance, leaves the meeting paused with its artifacts untouched and says why.
You can retry once the source is back.

## Stopping and quitting while paused

Stop works while paused and finishes the meeting normally: recording closed,
footer written, transcript flushed and closed, session recorded as completed,
in that order. Quitting while paused asks to stop the meeting first, exactly as
quitting while transcribing does.

If ScribeKit stops while a meeting is paused, its session record says so, and
the next launch offers the meeting for [recovery](recovery.md) rather than
resuming capture on its own.
