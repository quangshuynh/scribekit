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
- **⌘F** on the History screen puts the keyboard in the search field.
- The History list is a standard list: arrow keys move the selection, and the
  detail follows it.
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
  detail — "Save location. Ready. …" or "Audio source. Action needed. …". The
  icon beside it carries no meaning of its own.
- **A flagged review passage** reads as its time, its priority, whether it has
  been marked reviewed, the recognised words, why it was flagged, and whether
  there is audio to play. Its Play Audio and Mark Reviewed buttons stay
  separate, because they are separate actions.
- **A History row** reads as the meeting's title, status, date and the matching
  excerpt together.

Nothing in ScribeKit signals a state with colour alone. Every status that has
an icon has the same status in words beside it, and the app uses macOS's own
semantic colours rather than a palette of its own, so it follows the system's
light, dark and increased-contrast settings.

ScribeKit does not animate anything decorative, so there is nothing for Reduce
Motion to turn off. The only movement on screen is the standard progress
indicator macOS draws while discovery or a folder scan is running.

## Text size and window size

The window opens at a comfortable size and can be resized down to about
620 points wide. Detail text wraps rather than truncating, the live transcript
grows with its content up to a scrollable maximum, and long meeting titles,
long folder paths and long error messages wrap inside the window rather than
pushing controls out of reach.

## Known gaps

- **There is no Help content.** The Help menu is empty rather than carrying an
  item that reports that help is unavailable. ScribeKit has no network
  entitlement and does not open external links, so it does not link to this
  site from inside the app; the documentation is read here instead.
- **VoiceOver has not been driven by hand through every flow.** The
  accessibility tree was inspected on a running build and the semantics below
  it are covered by tests, but a full VoiceOver pass is a person's job and has
  not been recorded. See
  [Limitations](../reference/limitations.md).
- **The tab bar is not itself in the Tab-key order.** ⌘1 and ⌘2 are the
  keyboard route between screens.
