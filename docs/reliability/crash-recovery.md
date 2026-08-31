# Crash Recovery

## The record

Each session directory carries `.scribekit/session.json`, written before a
meeting begins and updated only after its transcript has been flushed and
closed. That ordering is the whole guarantee: a record saying a meeting
completed is written only once the files it describes have been flushed and
closed.

## Startup discovery

On launch, ScribeKit scans the immediate children of the chosen save folder for
sessions left marked in progress, and offers to reveal the transcript, record
the interruption, or leave the finding for next time. There is no recursive
walk, no timer and no filesystem watcher.

Recovery does not resume capture, does not start recognition, and does not
rewrite recognised speech. Reading a record back may not invent what was never
written: not the moment the process stopped, not the length of a gap, and not a
word of speech.

## What crossed the durability boundary

| Survives | Does not survive |
| --- | --- |
| Finalised spans already appended to `transcript.md` | Audio still in a system buffer |
| A retained `audio.caf` up to the moment ScribeKit stopped | A partial hypothesis that was never finalised |
| The session record itself | Speech that happened while ScribeKit was not running |

A finalised span reaches the file as soon as it is recognised, so it survives
the app exiting. Surviving a **power loss** additionally depends on the flush
that happens every 25 appends and at Stop, so an abrupt power cut can cost the
appends since the last flush. ScribeKit does not claim to be crash-proof.

## Retained audio after an interruption

A partly written `audio.caf` opens and plays up to the moment ScribeKit
stopped. A partly written `audio.m4a` does not open at all, because an MPEG-4
container is completed only when the file is closed. ScribeKit reports the
file's size and repairs neither.

A recording from a meeting that was killed before it could be finalised is
reported in review as one that will not open, rather than quietly skipped.

## Quitting is not a crash

Quitting during a meeting asks first, and waits for the meeting to be finished
properly rather than racing it against a deadline. ScribeKit does not leave a
meeting for the next launch to discover when it can simply finish it.

See [Recovery](../using/recovery.md) for the user-facing behaviour, and
[Failure Semantics](failure-semantics.md) for how each ending is recorded.
