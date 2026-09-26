# Keyboard & Accessibility

ScribeKit is a native macOS app, so most of its controls are ordinary AppKit
controls that VoiceOver and full keyboard access already understand. This page
covers the parts ScribeKit had to state for itself, and the places where it
still falls short.

## Menu commands

The application menus are the keyboard route to everything the menu bar item
offers, and they read the same running meeting.

| Command | Menu | Shortcut |
|---|---|---|
| Meeting screen | View | ⌘1 |
| History screen | View | ⌘2 |
| Search History | Edit | ⌘F |
| Next Match in a transcript | — (History detail) | ⌘G, or Return in the find field |
| Previous Match in a transcript | — (History detail) | ⇧⌘G |
| Pause Meeting | Meeting | ⌃⌘P |
| Resume Meeting | Meeting | ⌃⌘R |
| Stop Meeting | Meeting | — |
| Show Transcript in Finder | Meeting | — |
| Show Audio in Finder | Meeting | — |
| Quit ScribeKit | ScribeKit | ⌘Q |

**Stop Meeting has no shortcut on purpose.** It ends the meeting and finalises
its files, and that is not an action to leave one mistyped keystroke away.

Every item disables itself when it cannot do anything: the Meeting items when
no meeting is running or the meeting is in a state that cannot take them, and
**Search History** when the History screen is not on screen. The items are
derived from the same value the menu bar item is, so the window, the menu bar
and the menus cannot disagree about what is currently possible.

## Getting around without a mouse

- **⌘1** and **⌘2** move between the Meeting and History screens. The tab bar
  itself is a click target; the View menu is how the same move is made from the
  keyboard.
- **⌘F** on the History screen puts the keyboard in the search field. The
  **All / App Audio / Microphone** filter below it is a segmented control:
  VoiceOver reports which segment is selected, and with Keyboard navigation on
  it is reached with Tab and changed with the arrow keys.
- The History list is a standard list: arrow keys move the selection, and the
  detail follows it.
- In a meeting's details, the find field at the top keeps the keyboard
  while you step through matches: Return and ⌘G go to the next match, ⇧⌘G to
  the previous one, Escape clears the field. Each step is announced — "Match 3
  of 12 for deployment, at 10:14:05 AM" — so the preview moving is not
  something only a sighted user learns about.
- **Show in Transcript** on a flagged review passage moves the preview to it
  and moves VoiceOver to that passage.
- On the Meeting screen, the microphone **Input** is a standard pop-up button.
  While a meeting runs the screen shows the meeting instead of the setup form,
  and its source — including the microphone it is bound to — is read out with
  its status and elapsed time.
- **Return** starts a meeting when the Start Meeting button is available, since
  it is the window's default button.
- Text fields, pop-up buttons, checkboxes and the notes editor behave as any
  macOS control does. Turn on **Keyboard navigation** in System Settings ›
  Keyboard to reach buttons with Tab as well.

## What VoiceOver is told

Most of ScribeKit is native controls that describe themselves. Three places are
composed out of several pieces and would otherwise be read as unrelated
fragments, so each is published as one item that states everything the screen
shows:

- **A readiness row** reads as the prerequisite, its status in words and the
  detail — "Audio source. Action needed. …". The icon beside it carries no
  meaning of its own. Only prerequisites that still need something are listed.
- **A flagged review passage** reads as its time, its priority, whether it has
  been marked reviewed, the recognised words, why it was flagged, and whether
  there is audio to play. Its Play Audio and Mark Reviewed buttons stay
  separate, because they are separate actions.
- **A History row** reads as the meeting's title, status, date, capture mode
  when it is known, and — for a match in speech — the match's time, the excerpt
  verbatim and how many matches the transcript has. The emphasis and the
  ellipses drawn around the excerpt are not read out.
- **A transcript preview passage** reads as its time and words, and says when
  it holds find matches and when it holds the current one. The highlight itself
  is drawing, not content.
- **The find field's count** reads as "Match 3 of 12 for deployment" or "No
  matches for …"; the Previous and Next buttons are named as such rather than by
  their chevrons.

Nothing in ScribeKit signals a state with colour alone. Every status that has
an icon has the same status in words beside it — a review passage's priority,
a History row's Interrupted or Failed, the meeting's Listening or Paused — and
the app uses macOS's own semantic colours rather than a palette of its own, so
it follows the system's light, dark and increased-contrast settings. A passage
shown from Review is marked by a bar at its edge as well as a tint.

ScribeKit does not animate anything decorative, so there is nothing for Reduce
Motion to turn off. The only movement on screen is the standard progress
indicator macOS draws while discovery or a folder scan is running.

## Text size and window size

The window opens at a comfortable size and can be resized down to about
680 by 560 points. Detail text wraps rather than truncating, the live
transcript fills the space the window has and scrolls, and long meeting
titles, long folder paths and long error messages wrap or truncate in the
middle inside the window rather than pushing controls out of reach.

Every piece of text is set in one of a small number of roles built on the
system's text styles, so the interface follows the text size macOS applies to
it; see [Visual Design](../development/visual-design.md).

## Known gaps

- **There is no Help content.** The Help menu carries *Export Diagnostics…*
  and nothing else. ScribeKit has no network entitlement and does not open
  external links, so it does not link to this site from inside the app; the
  documentation is read here instead.
- **VoiceOver has been driven by hand along a representative path, not through
  every flow.** In Interval 25 a person turned VoiceOver on and worked through
  the readiness rows, source selection, Start, an active meeting, Pause, Resume,
  Stop, History rows, a session's status, playback and review controls, the
  notes editor and Save. The readiness rows read out their state, a session row
  carries its status and date, Pause was announced, and Start reads as *dimmed*
  while blocked and loses that once a source is chosen. Flows outside that path
  remain unheard, and ScribeKit claims no conformance to any accessibility
  standard. The microphone picker, the History filter and transcript find added
  since then have automated checks of what they tell VoiceOver and were
  included in the keyboard and VoiceOver pass run on an M1 Mac before v0.2.0.
  See
  [Limitations](../reference/limitations.md).
- **The tab bar is not itself in the Tab-key order.** ⌘1 and ⌘2 are the
  keyboard route between screens.
