# Microphone Transcription

!!! note "New in v0.2.0"

    Microphone transcription and microphone input selection were added in
    v0.2.0, which is built from source like every ScribeKit release.

ScribeKit has two ways to get the audio it transcribes, and a meeting uses
exactly one of them:

| | App Audio | Microphone |
| --- | --- | --- |
| **Listens to** | The applications you select, through ScreenCaptureKit | One sound input: the Mac's default, or one you choose |
| **Permission** | Screen & System Audio Recording | Microphone |
| **Audio kept** | Only if you choose raw or compressed retention | Never — only the transcript is written |
| **Good for** | A call or a video playing on this Mac | Your own voice, or a room, while you work in other apps |

Choose between them with **Transcribe from** at the top of the setup screen.
The choice is remembered between launches. It cannot be changed while a
meeting runs, and there is no way to capture both at once.

## Starting a Microphone meeting

1. Choose **Microphone** under **Transcribe from**.
2. Under it, choose the **Input** — System Default, or a particular
   microphone — and check that **Access** says **Allowed**.
3. Press **Start Meeting**. The first time, macOS asks whether ScribeKit may
   use the microphone. The question is asked before anything is written, so
   refusing leaves no empty meeting behind.
4. Speak. Switch to Safari, Xcode, Notes or anything else, hide or minimise
   ScribeKit, close its window — the meeting keeps listening and writing. The
   menu bar item shows it, can pause it and can stop it.
5. **Stop** from the window or the menu bar. The transcript is finished,
   closed and listed in [History](history-and-search.md) like any other.

Everything after the microphone is the same pipeline App Audio uses: on-device
recognition, the append-only `transcript.md`, pause and resume on the
[two clocks](../internals/two-clock-timeline.md), transcription-gap incidents,
the session record, recovery and diagnostics.

## Which microphone

**Input** lists the Mac's sound inputs — the same devices System Settings ›
Sound › Input offers, such as the built-in microphone, AirPods, a USB
microphone or a webcam — with **System Default** first:

- **System Default — MacBook Air Microphone** uses whichever input the Mac is
  set to *when the meeting starts*, and names it. Change the Mac's input in
  System Settings or Control Center and the next meeting follows it.
- **A named device** uses that microphone whatever the Mac's default is.
  Choosing it changes nothing outside ScribeKit: the Mac's own input setting,
  and every other app, stay as they were.

The list follows the hardware while the Meeting screen is open: plug in a
microphone and it appears; unplug it and it goes.

Your choice is remembered between launches. A device is remembered by the
identifier macOS gives it on this Mac, which Apple documents as stable across
restarts, together with its name. If the remembered device is not connected
when you next set up a meeting, the picker shows it as **not connected**, the
readiness row says the next meeting will use System Default instead and names
that device, and Start still works. Nothing is forgotten: once the device is
back, ScribeKit uses it again. The device's identifier is kept only in
ScribeKit's preferences on this Mac — never in a transcript, a session record
or a diagnostic report.

### During a meeting

A meeting keeps the microphone it started with until it ends. ScribeKit never
switches microphones in the middle of a transcript, and it tells real changes
to the input apart from the many audio-configuration notices macOS sends for
other reasons, by checking what the audio system reports rather than which
notice arrived:

| What happens | What the meeting does |
| --- | --- |
| Headphones or speakers connected, disconnected or switched (output only) | Keeps listening |
| The Mac's default input changes to another device | Keeps listening to its own microphone — System Default was resolved when it started |
| Another input is connected or disconnected | Keeps listening |
| The meeting's microphone is disconnected | Ends as **interrupted**; everything transcribed is kept |
| The audio input moves to a different microphone | Ends as interrupted, rather than transcribe a microphone nobody chose |
| The microphone changes sample rate or channel count | Ends as interrupted |
| macOS stops the audio input | Ends as interrupted |

An interrupted meeting's transcript is complete up to the moment capture
ended and says so; nothing heard after the change reaches it. Reconnecting the
microphone afterwards does not revive the meeting or change its record — start
a new one.

While a meeting is **paused**, its microphone may be unplugged. **Resume** is
then refused and says the microphone is not connected; the meeting stays
paused and resumable. Reconnect it and resume, or stop. A Mac whose default
input changed during the pause resumes on the meeting's own microphone.

## What is and is not kept

The microphone is listened to only while a Microphone meeting is running, and
only to be transcribed on this Mac. Audio passes through the recogniser and is
released; **no microphone audio is written to disk**, whatever the App Audio
retention setting says, and nothing is sent anywhere. The transcript's header
names the source as `Microphone (<input name>)` so the file says where its
speech came from without ScribeKit.

## Behaviour when ScribeKit is not in front

The meeting belongs to the application, not to the window, a tab or whether
ScribeKit is the active app: nothing in the running meeting observes focus,
activation, hiding, minimising, Spaces, window closing or which tab is
showing. See [Background Operation](background-operation.md).

| Situation | Designed behaviour |
| --- | --- |
| Another app is in front, or you switch Spaces | Keeps listening and writing |
| ScribeKit hidden (⌘H) or its window minimised | Keeps listening and writing |
| Window closed | Keeps listening and writing; ScribeKit stays running with its menu bar item |
| Switching between Meeting and History | Keeps listening and writing |
| Quit | Asks first, then stops the meeting properly before quitting |
| Meeting's microphone disconnected | Meeting ends as interrupted; transcript kept |
| Output device connected or changed | Keeps listening |
| Microphone permission turned off during a meeting | Not verified; see below |
| Sleep, wake or screen lock during a meeting | Not verified; see below |

The first five rows are guaranteed by the ownership design and covered by
automated tests that drive the same runtime without a microphone, and they were
checked by hand on an M1 Mac. The rows about devices are decided by one
tested rule, and the manual checklist in
[Testing](../development/testing.md#transcription-workflow-and-history-on-a-real-mac)
was run on an M1 Mac before v0.2.0 — one Mac and the devices it had, not every
kind of hardware.

What macOS does to a listening audio engine across sleep and wake, a locked
screen, or a permission revoked in System Settings has not been observed. If
the system stops the engine, ScribeKit reports it as the input ending and
records the meeting as interrupted; it does not restart listening on its own.

## When something goes wrong

| What happened | What ScribeKit does |
| --- | --- |
| Permission refused, now or earlier | Start is refused before anything is created; the setup screen names System Settings › Privacy & Security › Microphone |
| Access restricted on this Mac | Start is refused; App Audio meetings are unaffected |
| No input device | Start is refused until one is present |
| The chosen microphone was unplugged before Start | The next meeting uses System Default, and the setup screen says so beforehand |
| The audio engine will not start | The transcript is closed as a start that never began |
| The meeting's microphone disappears mid-meeting | Interrupted, as above |
| Recognition falls behind | One transcription-gap marker per incident, exactly as for App Audio |

See [Failure Semantics](../reliability/failure-semantics.md) and
[Crash Recovery](../reliability/crash-recovery.md): a Microphone meeting the
process did not survive is found and reported on the next launch the same way,
and its session record says it was a Microphone meeting.
