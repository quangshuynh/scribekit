# Review Metadata

`.scribekit/review.json`, beside `session.json`. Schema-versioned from its first
release and probed for its version before anything else is interpreted.

## What it holds

The session's identity, whether the recogniser reported any confidence at all
in this meeting, and one entry per flagged span carrying:

- that span's **position in the document** (its index),
- its audio-relative start and end,
- its confidence,
- its reasons.

It holds **no transcript text**. The words shown for review are read back from
`transcript.md` by index, so the sidecar cannot drift from the document or
become a second copy of it, and a candidate naming a span the transcript does
not have is dropped rather than shown against the wrong words.

The index is exact rather than approximate: a candidate is recorded only after
the span has actually reached the file, and numbered by how many spans were
written before it — which is the index the transcript reader gives that span
when the file is read back.

## When it is written

After the transcript has been flushed and closed, and before the session record
is updated. Writing it is **best effort by design**: a failure does not fail the
meeting, because a transcript and a recording that both closed cleanly are not
thrown away over a file that only makes a later convenience possible.

A session with no sidecar has no review information — which is exactly the state
every session recorded before review existed is in — and History says so
plainly.

## Reading it back

Reading it is on the read-only side. A missing, unreadable, damaged or
newer-format sidecar yields nothing and is not even reported as a problem,
because review metadata is never load-bearing.

## Confidence is not a number

Confidence is Apple's own judgement about words it finalised. ScribeKit uses it
to decide whether a passage is flagged and never shows it as a number or a
percentage, because Apple documents no scale for it. Nothing derived from this
sidecar is presented with more precision than the thing it was derived from
actually has.

See [Review & Playback](../using/review-and-playback.md).
