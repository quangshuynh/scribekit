# Permissions

## Screen & System Audio Recording

Listing applications and capturing their audio require Screen & System Audio
Recording permission, which macOS asks for the first time ScribeKit looks for
sources. Without it, the setup screen reports the missing permission instead of
a list or a capture.

ScreenCaptureKit has no audio-only stream, so the capture filter names a
display as well as the selected applications, and the permission macOS asks for
is therefore the screen recording one. **No screen output is added to the
stream**, so no frame is delivered and no video or screen content is ever
processed. See [Capturing App Audio](../using/capturing-app-audio.md).

## Speech recognition: none

Transcription asks for no permission at all, because it runs against a speech
model on this Mac rather than through a service.

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
