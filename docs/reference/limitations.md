# Limitations

What ScribeKit does not do, stated plainly. Nothing here is a bug report; these
are consequences of decisions, and several of them are deliberate.

## Not built

- **No continuation of an interrupted meeting.** An unfinished meeting is
  preserved and can be marked as interrupted; ScribeKit does not append a
  later capture run to it. Start a new meeting to carry on recording and
  transcribing. This is a decision, not an omission: a retained recording
  cannot be reopened and written to without replacing it, a meeting killed
  while capturing has recorded no captured length for a later run to continue
  its offsets from, and continuing honestly would mean a second audio file per
  session — which changes what a session directory is, what `session.json`
  names and how review playback finds the audio for an offset. See
  [Recovery](../using/recovery.md).
- **No editing, renaming, deleting or exporting.** Transcript history is
  read-only; the files are yours to manage in the Finder.
- **No search over your notes.** History's search runs over titles,
  transcripts and source names.
- **No filesystem watcher.** History reads the folder when it opens, when you
  refresh, and when a meeting finishes.

## Security and durability

- **Nothing is encrypted.** The transcript, the session record and any retained
  recording are ordinary files in the folder you chose, as private as that
  folder is.
- **Not crash-proof.** A finalised span reaches the file as soon as it is
  recognised, so it survives the app exiting; surviving a power loss depends on
  the flush that happens every 25 appends and at Stop, so an abrupt power cut
  can cost the appends since the last flush.
- **A start that fails after the transcript was created leaves the folder
  behind**, holding a transcript with a header and no speech. ScribeKit does
  not delete folders it created.
- **A damaged or newer-format record is left exactly as it is.** ScribeKit
  never repairs, rewrites or deletes one.
- **A session written by an earlier ScribeKit has no record**, so it is not
  recognised as unfinished, and it has no identity for notes or marks to attach
  to. Its transcript is unaffected.

## Capture

- **The captured set is fixed when capture starts.** So are the title, save
  folder, language and retention mode; their controls are disabled while a
  meeting runs.
- **The permission is the screen recording one.** ScreenCaptureKit has no
  audio-only stream, so the filter names a display. No screen output is added,
  so no frame is delivered or processed.
- **A captured application that quits mid-capture** leaves the stream alive
  delivering silence for it. Nothing is substituted, and the next start reports
  it as unavailable.
- **Only applications owning an ordinary on-screen window are listed**, so a
  menu-bar-only or windowless application is not offered as a source.
- **The application list is refreshed on appearance and on demand**, not as
  applications start and quit.
- **Audio in an unexpected format is refused rather than resampled**, because a
  file's format is fixed when it is created.
- **There is no button that opens the System Settings pane.** macOS exposes no
  supported API for opening a specific privacy pane, so ScribeKit names the
  path in words rather than hard-coding an undocumented URL.
- **Nothing watches for the permission to be granted.** ScribeKit checks when
  you press **Refresh** and not otherwise; there is no polling and no
  notification to subscribe to.
- **A permission never asked for and one refused look the same.** ScribeKit
  reports that access is unavailable rather than claiming which it was.

## Recognition

- **An on-device language model must be installed.** Languages whose model is
  absent are listed but cannot be selected, and ScribeKit does not install
  them.
- **The language is fixed for a run** and is never detected automatically.
- **Recognition consumes 16 kHz audio**, so 48 kHz capture is resampled on the
  capture queue.
- **Falling more than about three seconds behind capture drops the oldest
  audio** to keep memory bounded, and the lost time is reported as a gap.
- **A recogniser that stops by itself is restarted at most twice.** Audio
  arriving during a restart is counted as a gap. One that cannot be brought
  back ends the meeting.

## Timing

- **The transcript's timeline starts when the meeting starts**, and audio
  offsets are measured from the first captured frame, which arrives a moment
  later — so a timestamp can be under a second early.
- **Clock times use a fixed twelve-hour English format** and the Mac's current
  time zone; neither follows the system locale, so a transcript reads the same
  wherever it is opened.
- **A pause is a boundary in the recording, not a silence in it.** The moment a
  pause ended is audible as a cut, and the recording alone does not tell you how
  long the pause lasted. The transcript does.
- **`Duration` and `Captured` are not derived from each other.** One is the
  meeting's wall-clock length, the other the length of the recording.

## Audio files

- **A recording that fails mid-meeting ends the meeting.** ScribeKit will not
  keep transcribing while quietly leaving a hole in a file you asked for.
- **A crash leaves a different thing in each format.** A partly written
  `audio.caf` plays up to the moment ScribeKit stopped; a partly written
  `audio.m4a` does not open at all. ScribeKit repairs neither.

## History and search

- **One folder, one level deep.** History does not search your Mac for
  transcripts, does not follow a folder you moved a session out of, and does
  not remember meetings from a folder you have since replaced.
- **Substring matching only.** No fuzzy matching, no stemming, no synonyms: a
  search for `closures` does not find `closure`, a misheard word is found only
  by searching for what the recogniser wrote, and a phrase split across two
  finalised spans is not matched.
- **ScribeKit's own writing is not searched** — the header, minute headings,
  gap markers, the interruption notice and the footer.
- **Whole transcripts are held in memory while History is open**, so its cost
  grows with the folder. Measured in a debug build: 200 one-hour meetings —
  48,000 spans, 7.9 MB — load in 0.82 s and search in 100–160 ms per query, for
  a 17 MB memory increase. A folder several times larger would justify an
  on-disk index; nothing smaller does.

## Save folder

- **A moved folder is followed only when macOS reports its bookmark as stale.**
  A deleted folder, or one whose disk is absent, has to be chosen again.
- **The unfinished-session scan looks only at immediate children** of the save
  folder, at launch or when a folder is chosen. No recursive walk, no timer.
- **If the folder cannot be restored**, ScribeKit says it could not check for
  an unfinished meeting rather than looking anywhere else.
- **Readiness is a snapshot, not a subscription.** It is recomputed when the
  screen appears, when you act on a control, and when the runtime changes — a
  disk reappearing or a model finishing its install is noticed at the next
  **Try Again**, **Refresh** or **Check Again**, not on its own.
- **The readiness and ending copy is proved by tests, not by a real refusal.**
  No permission was actually denied, no disk actually pulled, and no model
  actually uninstalled on this Mac to produce these states; they are reached
  through injected failures. A running build has since been inspected on a Mac
  where all four prerequisites were satisfied, which confirms the satisfied
  path and nothing else.

## Accessibility

- **VoiceOver has been heard along one representative path only.** In
  Interval 25 a person drove setup, an active meeting with Pause and Resume,
  History, review and notes with VoiceOver on and recorded what they heard.
  Anything outside that path is still unheard, and ScribeKit claims no
  conformance to any accessibility standard.
- **Reaching every control by Tab needs macOS Keyboard navigation turned on.**
  That setting is off by default on macOS. Without it, ⌘1, ⌘2, ⌘F and the
  arrow keys still work; with it, Start, Pause, Resume, Stop, the notes editor
  and Save are all reachable.
- **The tab bar is reached with ⌘1 and ⌘2**, not with Tab.
- **The Help menu holds only *Export Diagnostics….*** ScribeKit has no network
  entitlement and does not open external links, so it does not link to its
  documentation site from inside the app.

## Process and CI

- **ScribeKit keeps running when its last window closes**, so quitting is
  explicit — the menu bar item, the application menu, or ⌘Q.
- **Quitting waits for the meeting to finish properly** rather than racing a
  deadline, so a quit takes as long as closing the transcript and audio file
  takes. A force quit is still a crash.
- **CI runs build and unit tests only** — no linting, formatting, coverage or
  UI tests.

## Diagnostics

- **A diagnostic report is a snapshot, not a history.** It describes what is
  true when you ask for one; nothing is stored, so it says nothing about a
  meeting before the last one.
- **`readiness` and `storage` are absent when the main window has not been
  open in this launch.** ScribeKit has not evaluated them, which is not the
  same as their being unready.
- **A report carries no transcript or recording byte counts.** Reading them
  would mean opening access to your folder to stat a canonical artifact, which
  is more than a support field is worth.
- **Application names and window titles are never reported.** A report says how
  many applications were discovered and how many were selected, and nothing
  about which.
- **ScribeKit does not collect the unified log or crash reports.** Console and
  `log` are the tools for those; see
  [Diagnostics & Support](../privacy/diagnostics.md).
