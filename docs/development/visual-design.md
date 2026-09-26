# Visual Design

ScribeKit's interface is meant to read as a native macOS application built
around transcription: calm, precise and quiet, with the words that were said
as the thing on screen that matters most. This page records the choices that
keep it that way and where they live in the code.

## Typography

ScribeKit uses the system faces — **SF Pro** for the interface and speech and
**SF Mono** for identifiers — through SwiftUI's font APIs. No font is bundled.

Two approaches were compared on the redesigned Meeting, session and History
screens, rendered side by side in light and dark appearance: the system faces,
and IBM Plex Sans and Plex Mono as a bundled identity. The system faces were
chosen because:

- **They reach every surface.** A bundled face applies only to text ScribeKit
  sets itself. Segmented controls, pop-up buttons, menus, the tab bar, the
  window title and alerts stay in the system face, so Plex produced two sans
  serif faces side by side on every screen.
- **Native controls keep their own hierarchy.** Setting a custom face for a
  form overrides the weight the system gives its section headers, which then
  read as body text.
- **Readability was not better.** At transcript size both read well; at the
  11–12 point sizes used for metadata, SF's optical sizes kept small text
  compact and crisp where Plex set wider and took more lines.
- **Text size follows the system with nothing extra to maintain.**

The identity Plex offered is carried instead by layout, hierarchy and restraint.

### Roles

Views never pick a font directly. They name a role — `.textRole(.metadata)` —
and the role decides the text style, weight, design and colour. The roles are
defined in `ScribeKit/Features/Design/Typography.swift`:

| Role | Set as | Used for |
| --- | --- | --- |
| Page title | Title 2, semibold | A running or past meeting's name |
| Section title | Title 3, semibold | Details, Review, Notes, Transcript |
| Group title | Body, semibold | A History row's title, a notice's headline |
| Body / emphasised body | Body, regular / medium | Ordinary text; a readiness row's name |
| Secondary body | Callout, secondary | Explanations under a control or section |
| Metadata | Subheadline, secondary | Dates, capture modes, status words |
| Caption | Caption, secondary | Fine print, counts |
| Technical / technical value | Subheadline or callout, SF Mono | Paths, locales, audio figures |
| Timestamp / elapsed | Subheadline or title 3, tabular digits | Transcript times, a meeting's elapsed time |
| Transcript | Title 3, regular | Recognised speech |
| Editor | Body, SF Mono | Markdown notes |

Semibold is kept for titles and nothing is bold. Size, weight and colour work
together: speech is the largest reading text, times and metadata are smaller
and secondary. Every role is built on a system text style, so it scales with
the text size macOS applies. `DesignSystemTests` checks these rules.

## Tokens

`ScribeKit/Features/Design/Metrics.swift` holds the few numbers layout is
built from: a spacing scale (2, 4, 8, 12, 16, 20, 28 points), two corner radii,
the window's minimum and default size, the readable column width that keeps
transcript lines to a comfortable length, and the opacities of tinted
surfaces. A new screen uses these rather than new numbers.

## Status and colour

`StatusTone` maps a state to one of six tones — neutral, positive, live,
attention, warning, critical — drawn in system colours that adapt to light,
dark and increased contrast. A tone is never the whole message: every tone
appears with a word and a symbol of its own, through `StatusBadge` or
`NoticeView`.

Emphasis is proportionate. Live capture is a small red dot beside the word
Listening or Capturing; Stop is an ordinary button with a stop symbol; a Review
passage is at most a warning; only a failure is critical.

## Components

`ScribeKit/Features/Design/Components.swift` has the pieces the screens share:
`StatusBadge`, `NoticeView`, `SectionHeading`, `FactRow` and
`TranscriptPassageRow`, which sets a passage the same way during a meeting and
in History. Native controls — grouped forms, segmented pickers, pop-up buttons,
the split view and `ContentUnavailableView` — are used wherever they do the
job.

## Performance

Nothing is animated for decoration and nothing is drawn with custom paths.
Values that change often — the elapsed clock, the captured-audio summary, the
partial hypothesis — are each read in a small view of their own, so an update
redraws one label rather than the screen, and the captured-audio summary is
observed only while Details is open.
