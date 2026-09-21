# Transcript Format

`transcript.md` is plain Markdown, append-only, and readable without ScribeKit.

```markdown
# Closures Walkthrough
## Transcript

### 10:01 AM

**10:01:33 AM**

Today, we are learning about closures in Swift.

> **Transcription gap:** approximately 0.8 seconds of audio around 10:01:41 AM was not transcribed; recognition fell behind capture.

---

**Ended:** 10:02 AM
**Duration:** 1 min 4 s
```

## Structure

| Element | Meaning |
| --- | --- |
| `# <title>` | The meeting title, as configured at start. |
| `### <h:mm AM/PM>` | A minute heading, written when the minute bucket changes and never twice for the same minute. Gaps do not open one. |
| `**<h:mm:ss AM/PM>**` | The wall-clock time of the finalised span that follows. |
| Plain paragraphs | Recognised speech, exactly as it was finalised. |
| `> **...:**` blockquotes | ScribeKit's own structural remarks — gaps, pauses, resumes, capture interruptions. |
| `> **Transcription gap:**` | One incident of untranscribed audio, written once when the incident ends. |
| `---` then footer | `**Ended:**`, `**Duration:**`, and `**Captured:**` for a meeting that was paused. |

`**Duration:**` is the meeting's wall-clock length. `**Captured:**` is the
length of the recording. Neither is derived from the other.

## Gap markers

A gap marker takes one of three forms, and which one is written follows from
what the pipeline actually established:

```markdown
> **Transcription gap:** approximately 0.8 seconds of audio around 10:01:41 AM was not transcribed; recognition fell behind capture.
> **Transcription gap:** approximately 215.0 seconds of audio was not transcribed between 11:38:00 AM and 11:41:23 AM; recognition fell behind capture.
> **Transcription gap:** approximately 2.4 seconds of audio was not transcribed; the recogniser was restarted.
```

The first names the moment a short loss fell at. The second is used once the
affected stretch is a second or more wide, and states two different quantities:
the **range** the incident spanned and the **seconds of audio** it cost. The
range is not a claim that everything inside it is missing — recognition carries
on between the losses, so spans from inside the range appear in the document
around the marker. The third states a length and no position, because no audio
clock was running to place it against.

One marker means one incident, however many separate losses the pipeline
observed while it lasted. A marker never opens a minute heading, and one is
never rewritten: the range is known when the incident ends, which is when the
marker is appended.

## Text handling

Recognised text is written exactly as it was finalised, apart from trimming the
whitespace that joins one span to the previous one. Nothing is escaped: a
recogniser emits words, and adding backslashes would put characters in the
transcript that were never spoken.

Only finalised text is written. Partial hypotheses are displayed and discarded.

## Timestamps

Every wall-clock time states `AM` or `PM` — the header's `Started`, the
footer's `Ended`, minute headings, span times, and the pause, resume, gap and
capture-interruption remarks alike. A span's time is read on its own, quoted
out of the document and matched by search, so it does not lean on the heading
above it to supply the period.

Formatting is deterministic and locale-independent: an ISO date and a fixed
twelve-hour English clock, computed from a Gregorian calendar in an explicit
time zone that defaults to the Mac's current one. A transcript therefore reads
the same wherever it is opened.

Transcripts written before this stated the period only on the minute heading.
They are **not** rewritten and not migrated: the reader accepts both shapes,
keeps a span's time exactly as the file states it, and falls back to the
heading's period for a span that carries none.

A span's wall-clock time is derived from its audio offset; see
[Two-clock Timeline](../internals/two-clock-timeline.md), including where that
derivation is inexact.

## Structural remarks

```markdown
> **Paused:** 11:42:10 AM. Capture stopped here; nothing was recorded until the meeting resumed.

> **Resumed:** 11:48:32 AM, after 6 min 22 s paused.
```

These say what happened rather than claiming speech was missed. They are
ScribeKit's writing, not recognised speech, which is why History's search does
not match them.

## Append-only

`Ended` is not known while the meeting runs, so it is a footer rather than a
header field that would have to be rewritten. Nothing already written is ever
recomputed.
