# Background Operation

A meeting keeps capturing, transcribing and writing while the ScribeKit window
is hidden, minimised, covered by other applications or closed altogether. The
meeting belongs to the application, not to the window: the window is somewhere
to watch a meeting rather than something the meeting depends on.

Presentation may be throttled or skipped while the interface is hidden.
Capture, recognition and persistence may not.

## The menu bar item

The menu bar item is always present.

| State | What it offers |
| --- | --- |
| No meeting | Open ScribeKit, Quit ScribeKit. |
| Meeting running | The meeting's name, its state and elapsed time, the applications being captured, what is being kept of the audio, and Stop Meeting, Show Transcript in Finder, Show Audio in Finder, Open ScribeKit, Quit ScribeKit. |

Stop from the menu bar is the same stop the window performs: capture ends, the
recogniser finalises what it has, the audio file is closed, and the transcript
is flushed, closed and recorded as finished.

## Closing the window

Closing the window keeps ScribeKit running, whether or not a meeting is under
way, and **Open ScribeKit** brings the same window back rather than opening
another. A reopened window is built fresh from the meeting that has been
running all along: its title and elapsed time, its state, every finalised span,
the current partial hypothesis, and whatever failure or interruption is
standing.

Closing the window also releases the interface, which is measurably cheaper
than leaving it installed — see
[Presentation Lifecycle](../internals/presentation-lifecycle.md) and the
measurements in [Performance & Energy](../PERFORMANCE.md).

## Quitting

Because the app keeps running when its last window closes, quitting is
explicit: from the menu bar item, the application menu, or ⌘Q. Quitting during
a meeting asks first, and waits for the meeting to be finished properly rather
than racing it against a deadline — so a quit takes as long as closing the
transcript and the audio file takes.

A force quit or a crash is still a crash, and startup
[recovery](recovery.md) is what handles those.
