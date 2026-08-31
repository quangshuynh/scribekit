# Architecture Boundaries

The rules a change to ScribeKit is expected to preserve. The durable contract
is `AGENTS.md` in the repository; this page is the readable version of the
boundaries it enforces.

## Domain models

Keep domain models small, testable value types, free of I/O. Model mutually
exclusive state with enums rather than sets of booleans, so contradictory
states are unrepresentable.

## Adapt frameworks at the subsystem boundary

Frameworks such as ScreenCaptureKit stay inside their provider. Domain models,
state owners and views work with ScribeKit's own value types, so behaviour
stays testable without system permission.

Capture, transcription, persistence and presentation are separate concerns and
stay separate.

## Filesystem

Reach the filesystem only through a location the user chose in a system panel,
persisted as a security-scoped bookmark, with access started for the work that
needs it and stopped afterwards. Never weaken or disable the App Sandbox to
reach a path, and never write to a location the user did not pick.

## Read and write are different types

`HistoryStoring` has no method that creates, replaces, appends to or deletes
anything. The protocol that writes derived state can address no source
artifact, so a failed derived write cannot damage one. Recovery keeps its own
store, because recording an interruption is a write and History never writes.

## The meeting is not the window

An active meeting's lifetime is application-scoped. Nothing that ends, pauses,
finalises or observes a meeting lives in a view hierarchy, and no presentation
object may be what keeps a meeting alive. See
[Presentation Lifecycle](../internals/presentation-lifecycle.md).

## The audio path

Bounded memory, no high-frequency audio callback through the main actor, every
producer/consumer queue bounded with overflow measured and reported, and
nothing on the delivery path — memory or stack — growing with the length of a
meeting. See [Audio Capture](../internals/audio-capture.md).

Design for event-driven work rather than polling: minimal timers, coalesced UI
updates, lazy rendering, batched persistence, appropriate task priorities, and
minimal work while the UI is hidden. Do not prematurely optimise; do not
knowingly introduce a hot loop either.

## No fake features

An unimplemented control is disabled or absent — never simulated, stubbed with
fabricated output, or described as working. Never simulate unimplemented
behaviour, and never rewrite raw transcripts.

## Documentation comments

Use native Swift `///` comments on non-trivial public and internal types,
protocols, methods, functions and important properties. Document parameters,
return values and thrown errors where applicable. Do not restate a symbol name,
and keep comments synchronised with the implementation.
