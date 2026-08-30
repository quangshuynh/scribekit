# AGENTS.md

Durable engineering contract for ScribeKit. Read this before changing the repository.

## Project identity

ScribeKit is a native macOS app (Swift + SwiftUI) for background-first meeting
transcription. It is local-first, Markdown-first, battery-conscious, and built
for multi-hour meetings. No accounts, no cloud database, no telemetry, no
analytics, no stealth capture.

## Architectural principles

- Keep domain models as small, testable value types, free of I/O.
- Model mutually exclusive state with enums, not sets of booleans.
- Separate capture, transcription, persistence and presentation concerns.
- Adapt system-framework types at the subsystem boundary. Frameworks such as
  ScreenCaptureKit stay inside their provider; domain models, state owners and
  views work with ScribeKit's own value types, so behaviour stays testable
  without system permission.
- Reach the filesystem only through a location the user chose in a system
  panel, persisted as a security-scoped bookmark, with access started for the
  work that needs it and stopped afterwards. Never weaken or disable App
  Sandbox to reach a path, and never write to a location the user did not pick.
- Prefer Apple platform frameworks over third-party dependencies.
- Add a dependency only when the platform genuinely cannot do the job, and say
  why in the pull request.

## Transcript integrity

Partial recognition is ephemeral. Only text the recogniser has finalised may
become transcript material; a partial hypothesis is displayed, replaced by the
next one and discarded, never appended to a transcript or persisted.

Speech recognition is local. It runs against a model installed on the user's
Mac, and an unavailable or uninstalled model is reported so the user can act on
it. Nothing may fall back to network or server-backed recognition, silently or
otherwise.

Gaps are reported. When audio is not transcribed — a full buffer, a recogniser
being restarted — the lost time is surfaced rather than closed over, and the
timeline of what was transcribed keeps its real offsets.

The raw transcript is source material and is never silently rewritten — not by
AI, LLMs, summarisation, grammar cleanup, inferred substitutions or semantic
rewriting. Derived artifacts (notes, key concepts, summaries) must be:

1. explicitly requested by the user,
2. stored separately from the raw transcript,
3. incapable of overwriting the raw transcript,
4. clearly distinguishable from captured transcription in the interface.

Transcription uncertainty is surfaced, not hidden.

`transcript.md` is the canonical transcript. It is plain Markdown, owned by
the user, readable and useful without ScribeKit, and never dependent on
ScribeKit metadata: losing or failing to parse anything else in a session
directory must not make the transcript unusable.

Metadata about a transcript is not transcript material. Anything ScribeKit
records *about* what was said — how sure the recogniser was, which passages
deserve a second listen, and whatever later intervals add — lives in a
versioned sidecar under `.scribekit/`, never in recognised prose and never in a
form that rewrites, annotates or reorders the Markdown. Such a sidecar is
optional by construction: it points at spans by position rather than copying
their words, a session without one behaves exactly as it did before the sidecar
existed, and failing to write one never fails a meeting whose durable artifacts
closed cleanly. Nothing derived from it may be presented with more precision
than the thing it was derived from actually has.

A meeting has two clocks and they are not interchangeable. Captured media time
advances only while capture is running; wall-clock time does not stop when
capture does. Transcript offsets, retained audio and anything that seeks into
that audio are measured in captured time, so an offset names the same second of
the recording however often a meeting was suspended, and no suspension is ever
padded into the file as silence or held in a buffer. Human-readable timestamps
are wall-clock and must account for the time capture was not running; a
timestamp already written is never recomputed to do so. Suspending capture is
the user's act, recorded as ScribeKit's own structural remark and never
described as lost audio or as a recognition failure.

Reading a meeting back is a read. History, search and any later feature that
lists or inspects past sessions are views over user-owned artifacts: listing,
indexing, previewing or searching a session must leave its transcript, its
recording and its session record byte-identical, and must not repair a damaged
one. A disposable index may accelerate search, but the Markdown and the session
record stay authoritative — anything derived from them is rebuilt on demand,
never written beside them and never trusted over them.

Finalised segments accepted for persistence are never silently discarded. Once
the writer has accepted one, ScribeKit does not drop it, and a queue between
recognition and the writer that cannot hold an entry fails the meeting rather
than evicting transcript material. A normal Stop flushes and closes durable
transcript output before it reports a finished meeting, and a persistence
failure is reported as one — never papered over with a claim that the
transcript was saved, and never left running so that recognised speech
accumulates with nowhere to go.

Persisted session completion never precedes successful finalisation of every
durable artifact the meeting enabled — the transcript, and a retained audio
file when there is one. A stored record saying a meeting completed is a claim
about files, so it is written only once they have been flushed and closed, and
a completion that cannot be recorded leaves the session recorded as unfinished
rather than falsely as finished. Reading such a record back may not invent what
was never written: not the moment the process stopped, not the length of a gap,
and not a word of speech.

A durable artifact that fails is reported, never hidden and never deleted. A
retained recording that cannot be written or cannot be finalised ends the
meeting rather than continuing with a silent hole in it, and whatever reached
the file is closed and left where it is — meeting audio cannot be captured
again.

## Meeting ownership

An active meeting's lifetime is application-scoped and must not depend on
SwiftUI view lifetime. Views request a start or a stop and observe what
happens; a view appearing, disappearing, being rebuilt or having its window
closed never starts, stops or duplicates a meeting. There is at most one active
meeting, and the owner enforces that, not whichever window happens to be open.

A meeting's configuration is fixed when it starts. Title, sources, destination,
retention mode and recognition locale are copied at the start and read from
that copy for the rest of the run, so editing the setup screen configures the
next meeting and cannot reach the one that is running.

Presentation may be throttled or skipped while the interface is hidden;
capture, recognition and persistence may not. Whatever the window is doing,
audio is captured, speech is recognised, and finalised text and retained audio
reach their files at full reliability.

## Privacy

- Everything stays on the user's machine unless the user explicitly exports it.
- No network calls for telemetry, analytics or crash reporting.
- Audio is retained only when the user opts in; the default retains none.
  Retained audio is an ordinary file in the folder the user chose, never
  encrypted or hidden, and it is never uploaded.
- Capture is always visible to the user. Never add hidden or silent recording.

## Efficiency

Design for event-driven work rather than polling, minimal timers, bounded
memory over multi-hour sessions, coalesced UI updates, lazy rendering, batched
persistence, appropriate task priorities, and minimal work while the UI is
hidden. Do not process video or screen content. Do not prematurely optimise;
do not knowingly introduce a hot loop either.

A live capture pipeline uses bounded memory and never routes high-frequency
audio callbacks through the main actor. Buffers are handled on the capture
system's own queue, whatever the interface shows is a coalesced summary, and no
part of the pipeline accumulates a meeting's audio in memory. Retained audio is
streamed to disk as it is captured, for the same reason: a meeting's audio is
written, never collected.

Every queue between a producer of audio and a consumer of it is bounded, and
overflow is measured and reported. An unbounded `AsyncStream` or array between
capture and a slower consumer is a memory leak with a delay on it. Recognised
text may grow with the meeting; raw audio may not.

## Documentation comments

Use native Swift `///` comments on non-trivial public and internal types,
protocols, methods, functions and important properties. Document parameters,
return values and thrown errors where applicable. Do not restate a symbol name.
Keep comments synchronised with the implementation they describe.

## Testing

- Unit tests use Swift Testing (`import Testing`, `@Test`, `#expect`).
- Test real behaviour: transition rules, normalisation, encoding round-trips,
  equality and identity semantics.
- Do not add tests that only prove that enum cases or symbols compile.

## Build and test

```bash
xcodebuild -project ScribeKit.xcodeproj -scheme ScribeKit -destination 'platform=macOS' build
xcodebuild -project ScribeKit.xcodeproj -scheme ScribeKit -destination 'platform=macOS' test
```

The `ScribeKit` scheme is shared and must stay committed; CI depends on it.

## Working rules

- **Inspect before editing.** Read the relevant code and docs before changing them.
- **Keep changes scoped.** Implement what was asked; do not start later work early.
- **No fake features.** An unimplemented control is disabled or absent — never
  simulated, stubbed with fabricated output, or described as working.
- **Validate before finishing.** Build and run tests; report real results.
- **Do not duplicate documentation.** Each fact lives in one file: identity and
  usage in `README.md`, engineering rules here, current state in `CONTEXT.md`.
