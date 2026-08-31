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
