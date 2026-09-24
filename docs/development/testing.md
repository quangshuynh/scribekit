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

## Microphone transcription on a real Mac

The automated suite drives Microphone meetings through the real runtime, the
real writer and the real session record, with the microphone itself replaced
at the capture boundary: `FakeCapturer` for the audio, `FakeMicrophoneAccess`
for macOS's answers about permission and the current input. The adapter that
turns the audio engine's buffers into ScribeKit's own, and every refusal the
microphone capturer makes before it builds an engine, run for real. What only a
Mac with a microphone can show — the audio engine listening, the permission
prompt, and the application's own lifecycle — is checked by hand with this
list. Record what was actually observed in
[Performance & Energy](../PERFORMANCE.md); nothing here counts as validated
until it has been run.

**Setup.** A Release build, a save folder chosen, an installed `en-US` model,
and **Transcribe from** set to **Microphone**. Reset the permission first to
see the prompt: `tccutil reset Microphone quang.ScribeKit`.

1. Launch ScribeKit. Confirm the **Microphone** section names the current
   input and **Microphone access** reads *Not asked yet*. No Screen & System
   Audio Recording prompt appears in Microphone mode.
2. **Start Meeting**. macOS asks for the microphone; allow it. The status reads
   *Listening to …*.
3. Say: "Phase one. ScribeKit is in front."
4. Switch to Safari. Say: "Phase two. Safari is in front."
5. Switch to another application (Notes, Xcode). Say: "Phase three. Another
   application is in front."
6. Minimise ScribeKit's window (⌘M). Say: "Phase four. ScribeKit is
   minimised."
7. Restore the window from the Dock. The live transcript shows phases one to
   four.
8. **Pause**. Say: "This sentence was spoken during the pause." Wait ten
   seconds.
9. **Resume**. Say: "Phase five. After resuming."
10. **Stop**.
11. Open **History**, then the meeting. Also open `transcript.md` in a text
    editor.
12. Confirm phases one to five are present, in order, with increasing times;
    the paused sentence is absent; one `Paused` and one `Resumed` marker
    surround the pause; there is no `Transcription gap` marker and no `Capture
    ended unexpectedly` marker; the header reads `**Sources:** Microphone
    (<input name>)`; and there is no `audio.caf` or `audio.m4a` in the session
    folder.
13. In `.scribekit/session.json`, `captureMode` is `"microphone"`, `status` is
    `"completed"` and no device identifier appears.

**Hide.** Start a Microphone meeting, hide ScribeKit with ⌘H, speak for a
minute while using other applications, unhide from the Dock or the menu bar,
stop. The speech from while it was hidden is in the transcript, in order.

**Close the window.** Start a Microphone meeting, close the window (⌘W), speak
for a minute, reopen it with **Open ScribeKit** from the menu bar, stop. The
meeting ran throughout and the reopened window shows the whole transcript.

**Spaces and full screen.** Start a meeting, move to another Space or a
full-screen application, speak, come back, stop.

**Refusal.** Reset the permission, start, choose *Don't Allow*. The start is
refused, the **Microphone access** row reads *Action needed* and names System
Settings › Privacy & Security › Microphone, and no session folder was created.
Allow it there, **Check Again**, start.

**App Audio independence.** With microphone access reset, start an App Audio
meeting. No microphone prompt appears.

**Device change.** With a USB or Bluetooth microphone as the input, start a
meeting, then unplug or switch it. The meeting ends as interrupted, the
transcript keeps what was said and carries a `Capture ended unexpectedly`
marker. Also try connecting or disconnecting headphones (an output change) and
note whether the meeting survives it.

**Not yet characterised.** Sleep and wake, screen lock, and turning microphone
access off in System Settings while a meeting runs. Note what happens; the
documentation claims nothing about them yet.
