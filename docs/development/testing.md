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
the window. `HistoryWorkflowTests` does the same for a History result row, the
find field's position and a preview passage holding matches. They are tests over values, not over accessibility modifiers: what
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
for macOS's answers about permission and the Mac's inputs. The adapter that
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

1. Launch ScribeKit. Confirm the **Microphone** section's **Input** reads
   *System Default — <the Mac's input>* and **Microphone access** reads *Not
   asked yet*. No Screen & System Audio Recording prompt appears in Microphone
   mode.
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

**Devices.** See the device steps of the consolidated checklist below.

**Not yet characterised.** Sleep and wake, screen lock, and turning microphone
access off in System Settings while a meeting runs. Note what happens; the
documentation claims nothing about them yet.

## Transcription workflow and History on a real Mac

One consolidated pass over both capture modes and the microphone selection,
History search and filtering, and transcript find. Record what was observed,
and what was skipped and why, in [Performance & Energy](../PERFORMANCE.md);
the automated suite covers the rules, and this list covers what only hardware
and a person can show.

**Microphone input.**

1. In Microphone mode, open **Input**. Every microphone System Settings › Sound
   › Input lists is there, System Default first and naming the Mac's input.
2. Choose the built-in microphone explicitly. Start, speak, stop. System
   Settings › Sound › Input still shows whatever it showed before.
3. Start a Microphone meeting, then: bring another app to the front; minimise;
   hide and unhide; pause for ten seconds and resume. Stop. Everything spoken
   outside the pause is in the transcript, in order, and the meeting is in
   History as Microphone.
4. With a second real microphone (USB, AirPods, a webcam), choose it while it
   is *not* the Mac's default. Start and speak: the transcript is that
   microphone's audio. The setup screen names it during the meeting.
5. Quit and relaunch: the chosen microphone is still selected. Unplug it and
   relaunch: it reads *not connected*, the readiness row names System Default's
   device, and Start works.
6. If it can be done safely, disconnect the chosen microphone during a meeting.
   The meeting ends as interrupted with *Capture ended unexpectedly* in the
   transcript and everything before it kept. Reconnect it: the ended meeting is
   unchanged and a new one can start.
7. During a meeting on the built-in microphone, connect or disconnect
   headphones or switch the output device. Note whether the meeting keeps
   listening (the expected result) or ends as interrupted — and if it ends,
   the reason shown.
8. During a meeting on System Default, change the Mac's input in Control
   Center. The meeting keeps listening to the microphone it started with.

**App Audio.**

9. Switch to App Audio, select an application playing speech, start. No
   microphone prompt appears and no microphone access is needed. Stop: the
   transcript and History entry are correct, listed as App Audio.

**History.**

10. With several App Audio and Microphone meetings in the folder, search for a
    word in one meeting's title, then for a word only in its speech. Each
    result shows its date, mode and — for speech — an excerpt.
11. Search for a word in both kinds of meeting, then choose **Microphone**:
    only Microphone meetings remain. Clear the search: the filter stays.
12. Open a result: the detail pane is that meeting's.

**Transcript find.**

13. In a long meeting, find a word that occurs many times. The count is
    right; Return, ⌘G and ⇧⌘G step and wrap; the preview scrolls to and
    highlights the current match, including one past the first 50 passages.
14. Hash `transcript.md` before and after (`shasum -a 256`): it is unchanged.

**Accessibility.**

15. Keyboard only, with Keyboard navigation on: choose a microphone, focus the
    History search (⌘F), change the filter with the arrow keys, open a meeting
    and step through find results — without the pointer.
16. With VoiceOver: the Input pop-up names the microphone; a filter segment
    reports its selected state; a History row reads its title, status, date,
    mode and snippet; each find step is announced; the Previous and Next
    buttons are named; the highlight itself is not read as content.
