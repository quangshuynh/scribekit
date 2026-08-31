# Failure Semantics

ScribeKit's rule is that a meeting's recorded ending states what actually
happened. No path that ends a meeting reaches the writer without saying which
ending it is.

## Successful finalisation is not a completion

Closing a transcript and a recording cleanly is a claim about files. Recording
a meeting as *completed* is additionally a claim that the meeting ended because
someone ended it.

A subsystem dying under a meeting — capture stopping without being asked to —
still finalises every artifact as far as it can, still keeps everything that
reached them, and is still recorded as something other than a completion. An
unexpected capture termination is **interrupted**, not completed.

## A subsystem that cannot be brought back ends the meeting

A recogniser that has used up its restarts, like a transcript that stopped
being written, is not a state to sit in:

1. Capture is stopped.
2. The durable artifacts are closed and kept.
3. The session is recorded as the failure it was.
4. Every hold on the process — the capture stream, the recording's writer, the
   activity assertion — is released.

Nothing may keep capturing audio that nothing is transcribing, and no meeting
may stay active in a process for want of a teardown, because the next meeting
cannot start while one is.

## Durable artifacts are reported, never hidden or deleted

A retained recording that cannot be written or cannot be finalised ends the
meeting rather than continuing with a silent hole in it. Whatever reached the
file is closed and left where it is — meeting audio cannot be captured again.

A persistence failure is reported as one, never papered over with a claim that
the transcript was saved.

## Ordering

Persisted session completion never precedes successful finalisation of every
durable artifact the meeting enabled. A completion that cannot be recorded
leaves the session recorded as unfinished rather than falsely as finished, and
a start that fails after the transcript was created closes it as a failure.

A start that failed this way leaves the session folder behind, holding a
transcript with a header and no speech. ScribeKit does not delete folders it
created.

## Gaps

Audio that was never transcribed is written into the transcript as an explicit
gap marker, positioned where the audio fell when the pipeline knows and honest
about the length alone when it does not. The timeline of what *was* transcribed
keeps its real offsets. See
[Live Transcription](../using/live-transcription.md).
