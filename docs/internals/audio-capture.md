# Audio Capture

## Two sources, one pipeline

A meeting's audio comes from one of two capturers, both behind
`AudioCapturing`:

| | App Audio | Microphone |
| --- | --- | --- |
| Capturer | `ScreenCaptureKitAudioCapturer` | `MicrophoneAudioCapturer` |
| Framework | ScreenCaptureKit, `SCStream` | `AVAudioEngine`, a tap on its input node |
| Delivers | 48 kHz mono float, as requested | The input device's own rate, mixed to mono float |
| Ends by itself when | The stream stops | Its input is disconnected, rerouted, reformatted or stopped |

`CaptureModeRouter` holds both and sends each start to the one for the
meeting's `CaptureMode`. It holds no meeting state — a stop goes to both,
each of which treats a stop with nothing running as a no-op — so the runtime
stays the one owner of which meeting is running. Both capturers hand
`CapturedPCMBuffer` values to the same broadcasting consumer on their own
thread, and report a stream that ended by itself through `interruptions`;
from there on, recognition, persistence, gap incidents, pause and resume and
the session record run the same code for either.

`AudioCapturing.prepare(configuration:)` runs before a meeting creates
anything. The microphone capturer asks macOS for access there the first time,
and confirms the input the meeting was set up with is connected; application
capture has nothing to check. A start never prompts, so a resume
cannot put a permission dialog in front of someone who did not ask for a
meeting.

Nothing touches the audio engine until a Microphone meeting starts. The
application creates both capturers at launch; creating the microphone one asks
macOS for nothing, which is what keeps App Audio free of the microphone
permission.

## The microphone path

The engine calls the tap on its own thread with buffers of roughly a tenth of a
second or more. `MicrophonePCMBufferAdapter` copies each one out while the
callback is on the stack, averages its channels into one, and cuts it into
pieces of at most 20 ms — the size application capture delivers — so the
recogniser's bounded backlog holds the same length of audio from either source
and a transcription-gap incident is judged the same way. The device's sample
rate is kept; the recogniser's converter resamples whatever arrives, and every
consumer reads each buffer's own rate. Only 32-bit float audio is read;
anything else is counted as unreadable rather than reinterpreted.

### Choosing the device

`CoreAudioInputDevices` lists what System Settings › Sound › Input offers:
Core Audio's devices (hidden ones are not listed there at all) that have input
streams, are alive, and may be the default input. Every call is a read; nothing
sets the Mac's default input. The setup screen resolves the user's choice with
`MicrophoneChoice` — System Default becomes the Mac's default device at that
moment, and a remembered device that is absent falls back to the default with
the fallback stated — and the meeting starts with that device's Core Audio UID
as its source.

At a start, `MicrophoneAudioCapturer` binds the engine's input node to that
device through its own audio unit's `kAudioOutputUnitProperty_CurrentDevice`,
the property Technical Note TN2091 documents for choosing a HAL unit's input,
and reads it back. This happens for System Default too, so every meeting is
bound to one device and none follows the Mac's default afterwards.

Binding is not enough by itself, which was found by trying it on a Mac rather
than by reading about it. With a 24 kHz Bluetooth headset as the default input,
an input node bound to the 48 kHz built-in microphone reported 48 kHz on its
device side and still 24 kHz on the side a tap reads — the format it had been
created with. The HAL unit does not convert sample rates on input, so the
capturer sets the unit's output format to the device's own rate and channel
count and checks that the node now reports it before installing the tap.
Verified for a built-in, a Bluetooth and a USB input, without starting the
engine; the Mac's default input and output were unchanged afterwards.

The UID is Core Audio's persistent identifier, which Apple documents as stable
across boots on one Mac and not meaningful on another. ScribeKit keeps it in
its own preferences to remember an explicit choice, and nowhere a transcript,
a session record or a diagnostic report could carry it.

### When the audio configuration changes

The engine posts one `AVAudioEngineConfigurationChange` for a headphone plugged
in, a microphone unplugged and a sample rate changed alike, so the notification
is treated as a cue to look rather than as a verdict. `MicrophoneRouteMonitor`
also listens to the bound device's alive property and to Core Audio's device
list and default input, and on any of them reads the evidence on one serial
queue: is the device present and alive, is the unit still bound to it, does it
deliver the format the tap was built for, is the engine running, and what is
the default input now. `MicrophoneRouteAssessment` decides:

| Evidence | Outcome |
| --- | --- |
| The device is gone or not alive | Lost: `inputDisconnected` |
| The unit reports another device, or cannot say | Lost: `inputChanged` |
| The device side's format differs, or cannot be read | Lost: `formatChanged` |
| The engine is not running | Lost: `engineStopped` |
| All of the above hold, and the default input moved | Unaffected: `systemDefaultChanged` |
| All of the above hold | Unaffected: `unrelated` — an output change, or nothing |

A loss stops the tap where it is seen, before the actor hears of it, so nothing
from a different microphone can reach the meeting; the capturer then tears the
session down and reports the stream as ended, which the runtime records as an
interruption with its transcript kept. It never restarts, on the same device or
another: the stretch in between would be audio with no marker for it. An
unaffected change is logged by its reason and nothing else happens.

No microphone audio is retained: a Microphone meeting's request with a
retention mode other than none is refused before anything is created, and the
retainer, which only writes while a recording is open, receives buffers and
writes nothing.

## Format and path

ScreenCaptureKit delivers 48 kHz mono 32-bit float audio. Buffers are copied,
converted and queued on the capture system's own queue and never cross the main
actor; the interface sees coalesced summaries and transcription events only.

Audio arriving in a different format from the one capture was asked for is
refused rather than resampled, because a file's format is fixed when it is
created. On this Mac ScreenCaptureKit has always delivered the format that was
requested.

Recognition consumes 16 kHz audio, so the 48 kHz capture is resampled on the
capture queue before it reaches the recogniser. Microphone audio is resampled
the same way from whatever rate the input device runs at, on the engine's tap
thread.

## One producer, two consumers

Captured buffers are broadcast to two consumers: the transcription input and,
when retention is on, the audio retainer. Both are started before capture
begins, so both see the same first buffer — which is why a transcript offset
and a position in the recording name the same frame. See
[Two-clock Timeline](two-clock-timeline.md).

Retained audio is a consumer of captured buffers rather than a queue in front
of one, so audio is written where it arrives and no backlog can build up.

## Bounded by construction

A live capture pipeline uses bounded memory and never routes high-frequency
audio callbacks through the main actor:

- No part of the pipeline accumulates a meeting's audio in memory. Retained
  audio is streamed to disk as it is captured.
- Every queue between a producer of audio and a consumer of it is bounded, and
  overflow is measured and reported. An unbounded stream between capture and a
  slower consumer is a memory leak with a delay on it.
- Nothing on the delivery path grows with the length of a meeting — not memory,
  and not stack. The last buffer of a meeting reaches every consumer through
  the same call depth as the first.

Recognised text may grow with the meeting. Raw audio may not.

## Backpressure

If recognition falls more than about three seconds behind capture, the oldest
audio is dropped to keep memory bounded, and the lost time is reported as a gap
in the transcript. Evicted buffers still reach the recording when retention is
on — the recording is then the only place that audio exists.

No screen or video content is processed at any point.
