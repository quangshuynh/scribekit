# Derived Metadata

`.scribekit/derived.json`, beside `session.json` and `review.json`. Schema
versioned from its first release and probed for its version before anything
else is interpreted.

This is the only file ScribeKit writes on your behalf after a meeting has
closed, and it is the only one on the writable side of the
[source/derived boundary](../internals/session-artifacts.md).

## Fields

| Field | Meaning |
| --- | --- |
| `schemaVersion` | Probed before anything else is interpreted. |
| `sessionID` | The meeting this state belongs to. |
| `revision` | What the editor loaded, used to refuse a conflicting write. |
| `notes` | Your Markdown source, verbatim. |
| `reviewedSpanIndexes` | Which flagged passages you marked, sorted and deduplicated. |
| `updatedAt` | ISO-8601. |

And nothing else. No transcript text, no confidence, no review reasons, no
audio metadata, no source names: all of that stays in the artifacts that own
it, and this file holds only what you decided. Because marks are stored sorted
and deduplicated and dates are ISO-8601, the same state always serialises to
the same bytes.

## Identity by position

A mark is identified by `spanIndex` — the position `review.json` already
numbers a candidate by, and the same index the transcript reader gives that
span. Nothing is identified by wording.

A mark whose index no longer names a candidate resolves to nothing. It is never
shown against another passage, and it is **left in the file** rather than
discarded: a sidecar that has outlived a review record is not a licence to throw
away what the user marked.

## Four refusals

Each of these leaves the file exactly as it is, disables notes and marks for
that meeting, and never overwrites anything:

1. Bytes that are not a record.
2. A schema version this build does not know.
3. A `sessionID` naming another meeting.
4. A `revision` that is not the one the editor loaded.

None of it is load-bearing. A meeting whose derived state cannot be read still
lists, opens, previews, searches and plays exactly as it would otherwise, and
History reports no problem for it — the detail pane says what was found and
what ScribeKit refused to do about it.

## Writes

Writes are atomic, so there is no partial `derived.json`. A reviewed mark is
written as it is made; notes are written when you press Save — no debounce, no
timer, no write per keystroke. Marking a passage writes the notes already on
disk, not the draft; saving notes carries the marks already on disk through
unchanged. "Saved" is only ever said after a write returned.

See [Meeting Notes](../using/meeting-notes.md).
