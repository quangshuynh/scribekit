# Microphone Transcription

!!! note "Unreleased"

    Microphone transcription is new since v0.1.0 and is not part of any
    release yet. It exists on `main` and is built from source like everything
    else.

ScribeKit has two ways to get the audio it transcribes, and a meeting uses
exactly one of them:

| | App Audio | Microphone |
| --- | --- | --- |
| **Listens to** | The applications you select, through ScreenCaptureKit | The Mac's current sound input |
| **Permission** | Screen & System Audio Recording | Microphone |
| **Audio kept** | Only if you choose raw or compressed retention | Never — only the transcript is written |
| **Good for** | A call or a video playing on this Mac | Your own voice, or a room, while you work in other apps |

Choose between them with **Transcribe from** at the top of the setup screen.
The choice is remembered between launches. It cannot be changed while a
meeting runs, and there is no way to capture both at once.

## Starting a Microphone meeting

1. Choose **Microphone** under **Transcribe from**.
2. Check the **Microphone** section: it names the input ScribeKit would listen
   to and says whether macOS allows it.
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

ScribeKit listens to **the Mac's current sound input** — whichever device is
selected in System Settings › Sound › Input — and names it on the setup
screen. There is no microphone picker in ScribeKit. To use a different
microphone, choose it in System Settings before you start, then **Check
Again**.

The input is fixed when the meeting starts. ScribeKit never follows the system
to a different microphone during a meeting:

- If the input changes, is disconnected or changes format while a meeting is
  listening, the meeting ends and is recorded as **interrupted**. Everything
  transcribed up to that point is kept, and the transcript says where capture
  ended.
- If the input has changed while a meeting is paused, **Resume** is refused
  and says why; the meeting stays paused and resumable. Put the original input
  back, or stop.
- If the input shown on the setup screen is no longer the current one when
  you press Start, the start is refused. **Check Again** reads it afresh.

Nothing about the device is remembered between launches, and its identifier is
never written into a transcript or a session record.

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
| Input changed or disconnected | Meeting ends as interrupted; transcript kept |
| Microphone permission turned off during a meeting | Not verified; see below |
| Sleep, wake or screen lock during a meeting | Not verified; see below |

The first five rows are guaranteed by the ownership design and covered by
automated tests that drive the same runtime without a microphone. They have
**not yet been confirmed on real hardware with a real microphone**; the
checklist for doing so is in [Testing](../development/testing.md#microphone-transcription-on-a-real-mac).

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
| The audio engine will not start | The transcript is closed as a start that never began |
| Input changes or disappears mid-meeting | Interrupted, as above |
| Recognition falls behind | One transcription-gap marker per incident, exactly as for App Audio |

See [Failure Semantics](../reliability/failure-semantics.md) and
[Crash Recovery](../reliability/crash-recovery.md): a Microphone meeting the
process did not survive is found and reported on the next launch the same way,
and its session record says it was a Microphone meeting.
