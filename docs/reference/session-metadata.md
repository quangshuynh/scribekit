# Session Metadata

`.scribekit/session.json`, beside the transcript. It is ScribeKit's
bookkeeping: the transcript is the user's document, and losing or failing to
parse this record never makes the transcript unusable.

## Lifetime

Written **before** a meeting begins, and updated **only after** its transcript
has been flushed and closed — and after any retained recording has been
finalised. That ordering is the durability guarantee: a record saying a meeting
completed is a claim about files that have already closed.

A completion that cannot be recorded leaves the session recorded as unfinished
rather than falsely as finished.

## What it records

Where the session stands: its identity, its `MeetingState`, its times, the
applications captured, and the recognition language. It holds no transcript
text.

It also records where the meeting's audio came from, as `captureMode`:
`"applications"` for App Audio, `"microphone"` for a
[Microphone meeting](../using/microphone-transcription.md). For a Microphone
meeting the source name is written as `Microphone (<input name>)`; the input
device's identifier is never written. `captureMode` is additive and optional,
like every field added after the first release of the record: a record written
before it existed — every v0.1.0 session — decodes with it absent and is read
exactly as before, and the schema version is unchanged.

`MeetingState` is the persisted domain lifecycle, with explicit transition
rules. The runtime's `MeetingRuntimeStatus` — which has a `failed` case the
persisted enum does not — is a presentation derivation and is not what is
stored. See [Meeting Lifecycle](../internals/meeting-lifecycle.md).

The distinction the states carry matters: an unexpected capture termination is
recorded as **interrupted**, not completed, because a completion additionally
claims that the meeting ended because someone ended it. See
[Failure Semantics](../reliability/failure-semantics.md).

## Transcript seal

`transcriptSeal` is evidence about the transcript, recorded once, when the
meeting closes:

```json
"transcriptSeal" : {
  "algorithm" : "sha256",
  "byteCount" : 4182,
  "digest" : "9f2c…"
}
```

It is written after the transcript has been flushed and closed — and after any
recording has been finalised — by reading the closed file back in 64 KB chunks,
and it goes into the same atomic replacement of `session.json` that records how
the meeting ended. There is therefore no moment at which a record says a
meeting closed while carrying a checksum for some other version of its file.
It holds no transcript text, and nothing is added to the Markdown.

It is additive and optional, like `captureMode`: records written by v0.1.0 and
v0.2.0 decode with it absent and are read as unverified, and an earlier build
ignores it. The schema version is unchanged. It is absent, too, while a meeting
is still open, when ScribeKit stopped before the meeting closed and recovery
marked it interrupted, and when the closed file could not be read back — in
which case the completion is still recorded and the meeting is not failed for
it. Absence is never treated as damage.

ScribeKit never updates a seal to match a transcript that has changed, never
rewrites a transcript to match its seal, and never sends either anywhere. See
[Transcript integrity](../using/history-and-search.md#transcript-integrity)
for what the check guarantees.

## Reading it back

- A session marked in progress at launch is offered for
  [recovery](../using/recovery.md).
- A damaged or newer-format record is reported and left exactly as it is.
  ScribeKit never repairs, rewrites or deletes one.
- A directory with a ScribeKit transcript and no record is listed as a legacy
  meeting, with only the facts the transcript itself states.
- A record must exist for a meeting to have an identity that notes and reviewed
  marks can attach to.

None of that is load-bearing for the transcript, which reads perfectly on its
own.
