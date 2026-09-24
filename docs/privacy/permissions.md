# Permissions

## Screen & System Audio Recording

Listing applications and capturing their audio require Screen & System Audio
Recording permission, which macOS asks for the first time ScribeKit looks for
sources. Without it, the setup screen reports the missing permission instead of
a list or a capture.

ScribeKit does not pre-check the permission in order to avoid asking for it:
the first discovery attempt is what makes macOS ask, exactly as the normal
permission flow expects. When an attempt fails, ScribeKit asks macOS through
`CGPreflightScreenCaptureAccess` whether the access exists, so it can say that
access is missing rather than repeat a framework error. That check never
prompts, and nothing polls for the permission to change.

Because a permission that has never been asked for and one that was refused
look the same from here, ScribeKit says the access is *not available* rather
than claiming you denied it. Grant it in System Settings › Privacy & Security ›
Screen & System Audio Recording, then choose **Refresh** on the setup screen.
ScribeKit does not claim a relaunch is needed.

ScreenCaptureKit has no audio-only stream, so the capture filter names a
display as well as the selected applications, and the permission macOS asks for
is therefore the screen recording one. **No screen output is added to the
stream**, so no frame is delivered and no video or screen content is ever
processed. See [Capturing App Audio](../using/capturing-app-audio.md).

App Audio meetings need this permission; Microphone meetings do not, and in
Microphone mode ScribeKit does not look for applications, so it is not asked
for.

## Microphone

A [Microphone meeting](../using/microphone-transcription.md) needs microphone
access, and nothing else does. macOS asks the first time a Microphone meeting
starts — or when you choose **Allow Microphone Access…** on the setup screen
beforehand — with this explanation:

> ScribeKit listens to your microphone only while a Microphone meeting is
> running, to transcribe your speech on this Mac. The audio is not saved and
> never leaves your Mac.

The question is asked before a meeting creates anything, so refusing leaves no
empty session behind. An App Audio meeting never reads, asks for or needs this
permission.

What the setup screen shows is macOS's own answer, read from `AVCaptureDevice`
each time the screen appears or you press **Check Again**; ScribeKit keeps no
permission state of its own beside it. Reading it never prompts.

| macOS says | Setup screen | What to do |
| --- | --- | --- |
| Not asked yet | *Note* — macOS asks when you start | Start, or **Allow Microphone Access…** |
| Allowed | *Ready* | Nothing |
| Denied | *Action needed* | macOS will not ask again. Turn ScribeKit on in System Settings › Privacy & Security › Microphone, then **Check Again** |
| Restricted | *Action needed* | Set by device management or parental controls; ScribeKit cannot ask for it |

Listing the Mac's microphones for the **Input** picker asks for nothing:
naming a device is not listening to it, and the list is read from Core Audio
without microphone access. Choosing a microphone there does not change the
Mac's own input setting.

ScribeKit asks for the microphone only when a meeting is being started, never
during a resume: a resume that finds access turned off is refused and the
meeting stays paused.

The app carries the sandbox's audio-input entitlement
(`com.apple.security.device.audio-input`) and a microphone usage description,
and nothing else was added for it.

## Speech recognition: none

Transcription asks for no permission at all, because it runs against a speech
model on this Mac rather than through a service.

What it does need is the model itself. ScribeKit lists the languages the
recogniser supports, marks the ones whose model is not installed, and refuses
to start in a language it cannot transcribe — it never downloads a model, never
substitutes another language, and never falls back to network recognition. Use
**Check Again** on the setup screen after installing one. A Mac that cannot run
the recogniser at all is reported as that, rather than as a list with no
languages in it. See [On-device Speech](../internals/on-device-speech.md).

## Files: the folder you picked

ScribeKit reaches the filesystem only through a location you chose in a system
panel, persisted as a security-scoped bookmark. Access is started for the work
that needs it and stopped afterwards. The App Sandbox is never weakened or
disabled to reach a path, and ScribeKit never writes to a location you did not
pick. See [Save Location](../getting-started/save-location.md).

## Network: no entitlement

The app ships without the network client entitlement, so the sandbox does not
permit it to open a network connection at all. See
[Network Policy](network-policy.md).

## What a real Mac reported

On a development Mac that had already granted Screen & System Audio Recording,
had an installed `en-US` speech model and had a save folder remembered from an
earlier launch, the running app reported all four prerequisites as **Ready**
before any application had been selected, and the process held no network
sockets at all while it ran.

That is the satisfied path, observed. Refusal has still never been reproduced
on a real machine: no permission has been denied, no disk pulled and no speech
model uninstalled to see what ScribeKit says. Those states are reached through
injected failures in the test suite, and are listed in
[Limitations](../reference/limitations.md).
