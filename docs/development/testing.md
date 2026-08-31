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

## What tests do not cover

Behaviour that only exists against real ScreenCaptureKit streams, real speech
models and multi-hour runs is validated by measurement rather than by unit
tests. Those results are recorded in
[Performance & Energy](../PERFORMANCE.md), which is the canonical record of
what has actually been observed on hardware — including the long-session soaks,
the retention-mode measurements, the pause behaviour and the crash found and
resolved through profiling.

CI runs build and unit tests only. There is no linting, formatting, coverage or
UI test job.
