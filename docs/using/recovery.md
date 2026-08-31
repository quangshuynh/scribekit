# Recovery

Each session directory carries a small `.scribekit/session.json` recording
where the session stands. It is written before a meeting begins and updated
only after the transcript has been flushed and closed.

On launch, ScribeKit looks in the save folder for sessions left marked in
progress and offers to reveal the transcript, record the interruption, or leave
the finding for next time.

## What recovery does not do

Recovery **does not resume a meeting**. It does not restart capture, does not
start recognition, and does not rewrite recognised speech. Continuing an
interrupted meeting into the same session is a planned feature, not an
implemented one.

Recovery also does not pretend a crashed meeting completed. Reading a record
back may not invent what was never written: not the moment the process stopped,
not the length of a gap, and not a word of speech.

## What survives

ScribeKit preserves finalised transcript content that reached durable storage
before the interruption. A finalised span reaches the file as soon as it is
recognised, so it survives the app exiting.

Not recovered, because they were never written: audio still in a system buffer,
a partial hypothesis that was never finalised, and speech that happened while
ScribeKit was not running.

Surviving a **power loss** additionally depends on the flush that happens every
25 appends and at Stop, so an abrupt power cut can cost the appends since the
last flush. ScribeKit does not claim to be crash-proof.

## What is not offered for recovery

- A meeting that ended because its transcript stopped being saved is recorded
  as **failed** rather than offered for recovery: ScribeKit was running and
  said so at the time.
- A session directory written by an earlier ScribeKit has no session record, so
  it is not recognised as unfinished. Its transcript is unaffected.
- A damaged or newer-format session record is reported and left exactly as it
  is. ScribeKit never repairs, rewrites or deletes one, and never deletes a
  transcript.

## The scan

The scan looks only at the immediate children of the chosen save folder, when
the app launches or when a folder is chosen. There is no recursive walk, no
timer and no filesystem watcher. If the save folder cannot be restored or
opened, ScribeKit says it could not check for an unfinished meeting rather than
looking anywhere else.

See also [Crash Recovery](../reliability/crash-recovery.md) for the ordering
guarantees behind this, and
[Session Metadata](../reference/session-metadata.md) for the record itself.
