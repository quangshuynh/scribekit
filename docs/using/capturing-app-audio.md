# Capturing App Audio

ScribeKit captures audio from the applications you select, through
ScreenCaptureKit. It is not a system-wide tap and it is not a microphone
recorder.

## Discovery and selection

Running applications are discovered through ScreenCaptureKit and listed on the
setup screen, with a manual **Refresh**. Only applications owning an ordinary
on-screen window are listed, so a menu-bar-only or windowless application is
not offered as a source. The list is refreshed on appearance and on demand —
there is no watcher tracking applications as they start and quit.

You may select one application or several. The selection is remembered across
launches and matched against a fresh discovery each time.

## What starting does

Starting resolves the selection against the applications running at that
moment. If one of them has quit, the start fails clearly; nothing is
substituted. Capture then reports the format and level it is actually
receiving.

The captured set is fixed when capture starts. Changing the selection while a
meeting runs does not change what is being captured — stop and start again.

## Why the permission is the screen one

ScreenCaptureKit has no audio-only stream, so the capture filter has to name a
display as well as the selected applications. No screen output is added, so no
frame is delivered or processed and no video or screen content is ever
examined — but the permission macOS asks for is the screen recording one. See
[Permissions](../privacy/permissions.md).

## A source that quits mid-capture

If a captured application quits while capture is running, ScreenCaptureKit
keeps the stream alive and delivers silence for it. ScribeKit does not
substitute another source, and the next start reports the application as
unavailable.

An unexpected end of the capture stream itself is a different thing: the
meeting is finalised as far as it can be and recorded as **interrupted**, not
completed. See [Failure Semantics](../reliability/failure-semantics.md).
