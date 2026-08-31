# Presentation Lifecycle

A window that is not on screen owns no interface.

A closed SwiftUI window scene is not an idle one: the scene outlives the
window, so a view graph left installed behind a closed window keeps observing
the runtime, keeps having its bodies evaluated, and keeps being laid out on the
display cycle. Measurement showed exactly that — hiding the window saved two to
three points of one core out of eighteen, while taking the hosting view down
returned the process to its headless floor, and profiling attributed about 30%
of the process's CPU to SwiftUI layout, most of it the live transcript's scroll
view.

## The mechanism

The window scene holds `MainPresentationScene`, a shell that costs nothing and
contains two things: a zero-size `NSViewRepresentable` that reports which window
it is in, and a branch that builds `ScribeKitRootView` only while that window is
on screen. Closing the window releases the interface; opening it builds a new
one.

`MainWindowPresence` is the whole of the mechanism. It key-value-observes the
window's `visible` and `miniaturized` properties — rather than the
notifications that usually accompany them, because a window can be ordered on
screen without becoming key, and an interface that missed that would leave an
empty window in front of the user — and re-reads the window on the next turn of
the main loop, so the answer is always the window's own.

The reporter lives in the shell rather than in the interface deliberately: the
thing that notices the window coming back cannot be part of what goes away when
the window leaves.

## What this does not touch

Nothing about the meeting lives in either. `MainPresentationScene` never reads
the runtime, so rebuilding the interface cannot invalidate the shell and
detaching cannot pause, stop or duplicate anything. Capture, recognition, the
transcript and audio writers, both clocks, the activity assertion, pause,
resume, stop, interruption handling and the menu bar are untouched by whether a
window exists.

Nothing that ends, pauses, finalises or observes a meeting lives in that
hierarchy, and no presentation object is what keeps a meeting alive.

Presentation may skip any number of intermediate render states it was not there
for. Canonical meeting state and durable artifacts may skip nothing.

## Reopening

A reopened window prepares itself the way any first open does and reads current
runtime state: the running meeting's title and elapsed time, its active or
paused status, capture activity, every finalised span, the current partial
hypothesis, and whatever failure or interruption is standing. There is no
UI-state cache, because there is nothing to cache — the meeting is the state.

What the window's own state still owns is the configuration for the *next*
meeting, restored from the preference store.

## Measured

On an M1 across two Release soaks: a detached meeting costs about 6.3–7.9% of
one core against 21.3–26.3% with the window open, which is the headless floor.
The full method and numbers are in
[Performance & Energy](../PERFORMANCE.md).
