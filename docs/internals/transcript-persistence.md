# Transcript Persistence

`transcript.md` is the canonical transcript: plain Markdown, owned by the user,
readable and useful without ScribeKit, and never dependent on ScribeKit
metadata. Losing or failing to parse anything else in a session directory must
not make the transcript unusable.

## Append-only, no timer

Starting a meeting creates the dated session folder and `transcript.md` inside
it. Each finalised span is appended to that file as it is recognised, so the
file is readable in any editor while the meeting is still running, and there is
no autosave timer.

The document is append-only by design: `Ended` is not known while the meeting
runs, so it is a footer rather than a header field that would have to be
rewritten.

The file is flushed to the storage device every 25 appends, and Stop flushes
and closes the transcript before it reports the meeting finished.

## Nothing accepted is dropped

Once the writer has accepted a finalised segment, ScribeKit does not drop it. A
queue between recognition and the writer that cannot hold an entry fails the
meeting rather than evicting transcript material.

A persistence failure is reported as one — never papered over with a claim that
the transcript was saved, and never left running so that recognised speech
accumulates with nowhere to go. A meeting whose transcript stops being writable
is stopped.

## Ordering

Persisted session completion never precedes successful finalisation of every
durable artifact the meeting enabled:

1. Capture stops.
2. The recogniser finalises what it has.
3. The retained recording, if any, is closed.
4. The footer is written; the transcript is flushed and closed.
5. Only then is the session recorded as completed.

A completion that cannot be recorded leaves the session recorded as unfinished
rather than falsely as finished. A start that fails after the transcript was
created closes it as a failure, not a completion: a meeting that never captured
a second did not finish — it never began.

## Layers

Durable writing sits behind `TranscriptPersisting` and retained audio behind
`AudioRetaining`, with Markdown formatting separated from filesystem work and
an actor owning one session's folder lease, open file and position in the
document.

See [Transcript Format](../reference/transcript-format.md) for what the file
looks like.
