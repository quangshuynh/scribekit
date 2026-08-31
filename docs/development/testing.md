# Testing

Unit tests use [Swift Testing](https://developer.apple.com/documentation/testing)
(`import Testing`, `@Test`, `#expect`) and live in `ScribeKitTests`.

```bash
xcodebuild -project ScribeKit.xcodeproj -scheme ScribeKit -destination 'platform=macOS' test
```

## What is worth testing

Tests exercise real behaviour: transition rules, normalisation, encoding
round-trips, equality and identity semantics. Tests that only prove enum cases
or symbols compile are not added.

This is possible because the system frameworks are adapted at subsystem
boundaries. Source discovery sits behind `CaptureSourceProviding`, capture
behind `AudioCapturing`, recognition behind `SpeechTranscribing`, persistence
behind `TranscriptPersisting` and `AudioRetaining`, reading behind
`HistoryStoring` — so domain models, state owners and views work with
ScribeKit's own value types and stay testable without system permission. See
[Architecture Boundaries](architecture-boundaries.md).

## Accessibility semantics

`AccessibilitySemanticsTests` covers the strings ScribeKit publishes for its
own composed rows — readiness rows, flagged review passages — along with which
menu commands a meeting in each state offers, and the two keyboard routes into
the window. They are tests over values, not over accessibility modifiers: what
a modifier does with a string is AppKit's business, and what the string says is
ScribeKit's.

## What tests do not cover

Behaviour that only exists against real ScreenCaptureKit streams, real speech
models and multi-hour runs is validated by measurement rather than by unit
tests. Those results are recorded in
[Performance & Energy](../PERFORMANCE.md), which is the canonical record of
what has actually been observed on hardware — including the long-session soaks,
the retention-mode measurements, the pause behaviour and the crash found and
resolved through profiling.

No VoiceOver behaviour is asserted. What an accessibility modifier makes of a
string is AppKit's, and a test that pinned it would pin the framework rather
than ScribeKit; the accessibility tree of a running build is inspected by hand
instead, and what was found is recorded in
[Limitations](../reference/limitations.md).

CI runs build and unit tests only. There is no linting, formatting, coverage or
UI test job.
