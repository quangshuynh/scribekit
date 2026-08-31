# Meeting Lifecycle

An active meeting's lifetime is application-scoped and does not depend on
SwiftUI view lifetime. There is at most one active meeting, and `MeetingRuntime`
enforces that — not whichever window happens to be open. Views request a start
or a stop and observe what happens; a view appearing, disappearing, being
rebuilt or having its window closed never starts, stops or duplicates a
meeting.

## Four lifetimes

| Lifetime | What it is |
| --- | --- |
| Process | `ScribeKitAppDelegate`, and the one `MeetingRuntime` it holds. |
| Meeting | From Start to whichever ending arrives; always inside a process. |
| Window | The single `Window` scene's `NSWindow`, closable and reopenable. |
| View hierarchy | The interface inside that window. |

Only the first two have anything to do with whether a meeting runs. See
[Presentation Lifecycle](presentation-lifecycle.md).

## Configuration immutability

A meeting's configuration is fixed when it starts. Title, sources,
destination, retention mode and recognition locale are copied at the start and
read from that copy for the rest of the run — so editing the setup screen
configures the next meeting and cannot reach the one that is running.

## One lifecycle answer

`MeetingRuntimeStatus` is computed from `captureState`, `transcriptionState`,
`persistenceState` and `audioRetentionState`: idle, preparing, transcribing,
stopping, completed, or failed with a message. It is a derivation, not a second
state machine — nothing assigns it, so the menu bar and the window cannot
disagree.

Failure is reported by artifact first (transcript, then recording, then
capture, then recognition) and as soon as it exists, including while the
teardown it triggered is still running, because a meeting that has lost an
artifact is not "stopping normally".

`MeetingState` remains the persisted domain lifecycle in `MeetingSession` and
in the session record. The runtime's status is a presentation answer that needs
a `failed` case the persisted enum does not have.

## Endings

Not every ending is the same ending, and no path that ends a meeting reaches
the writer without stating which one it is:

- **Completed** — someone stopped it, and every durable artifact closed
  cleanly.
- **Interrupted** — a subsystem died under the meeting. Artifacts are finalised
  as far as they can be and everything that reached them is kept, but this is
  not a completion.
- **Failed** — a durable artifact or a subsystem could not be brought back.

Closing a transcript and a recording cleanly is a claim about *files*.
Recording a meeting as completed is additionally a claim that the meeting ended
because someone ended it. See
[Failure Semantics](../reliability/failure-semantics.md).
