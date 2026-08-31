# Diagnostics & Support

When ScribeKit fails on a Mac that is not the developer's, two things can
explain it: the macOS unified log, which is already on that Mac, and a
diagnostic report, which the user creates deliberately and sends to whoever is
helping them. Neither contains a word of what was said.

## Exporting a report

**Help ▸ Export Diagnostics…**, or the *Export Diagnostics…* button that
appears beside a failed or interrupted meeting's explanation.

A system save panel opens, states what a report contains and what it does not,
and asks where to put it. Nothing is written until you choose a destination, and
cancelling writes nothing at all. The report is a single `.json` file, a few
kilobytes, saved only where you said.

ScribeKit does not upload it, does not attach it to anything, and cannot: the
app ships without the network client entitlement. See
[Network Policy](network-policy.md).

## What a report contains

| Section | Fields |
| --- | --- |
| `application` | ScribeKit's own bundle identifier, version and build |
| `system` | macOS version, processor architecture |
| `runtime` | The lifecycle status, the four subsystem states, the recognition locale, whether an on-device model is available, how many locales have one |
| `readiness` | Each of the four prerequisites and its status, whether a meeting could start, which prerequisite is blocking, and how many applications were discovered, selected and no longer running |
| `storage` | Whether a save folder was chosen, whether access to it resolved, whether the choice survived relaunch, whether capture access was available |
| `recovery` | Whether an unfinished-session scan has run, how many sessions it found unfinished, how many records it could not read and why, and the schema versions this build writes |
| `session` | Safe metadata about the current or most recent meeting: retention mode, recognition locale, source count, start time, wall and captured durations, pauses, recogniser restarts, transcript spans, gaps, untranscribed seconds, whether a recording was opened, and the sample rate and channel count capture asked for |
| `lastOutcome` | How the last meeting ended, the support category of the failure when there was one, and whether capture ran at all |

Every timestamp is ISO 8601, keys are sorted, and the file is pretty-printed:
two reports of the same state are the same bytes.

The structure is versioned. `schemaVersion` is `1`, and a reader that does not
know a version should say so rather than guess.

## What a report never contains

By design, and enforced by tests that run a meeting with deliberately
identifiable material in every field and search the exported bytes for it:

- Transcript text, partial recognition, or anything the recogniser heard.
- Audio, encoded audio, or any sample.
- Notes, review passages, or marks.
- Search queries or clipboard contents.
- The meeting's title, which is prose you wrote and may itself be sensitive.
- The names or bundle identifiers of the applications being captured, or any
  window title. Counts only.
- Your save folder, the session folder, any absolute path, your user name, or
  the bytes of a security-scoped bookmark.
- The sentences the readiness rows show, which quote folders and applications.
  The status word is carried; the explanation is not.
- Framework error text. A failure is named by ScribeKit's own stable category
  instead, because a localised sentence can quote a file and changes between
  releases.

It is not a claim that a report holds no personal information. A macOS version,
an application version, a recognition locale and a meeting's duration are still
facts about your Mac and your day. It is a claim about what is *not* in it, and
that list is above.

## Failure categories

A report names a failure with one of these, and so does the log. They are
stable across rewordings and localisations:

`captureAccess`, `captureDiscovery`, `captureStart`, `captureInterrupted`,
`recognitionAvailability`, `recognitionStart`, `recognitionRestartExhausted`,
`saveLocation`, `transcriptPersistence`, `audioPersistence`,
`sessionMetadata`, `recoveryMetadata`.

They exist for support conversations. ScribeKit's subsystems keep their own
richer errors for deciding what to do; see
[Failure Semantics](../reliability/failure-semantics.md).

## Watching ScribeKit in Console

ScribeKit logs to the macOS unified logging system — the local facility every
application on a Mac uses. It is not telemetry: nothing is sent anywhere, and
what is written stays on that Mac under the system's own retention.

Filter on the subsystem in Console.app, or stream it:

```bash
log stream --predicate 'subsystem == "quang.ScribeKit"' --level debug
```

To read back what already happened:

```bash
log show --last 30m --predicate 'subsystem == "quang.ScribeKit"' --info --debug
```

The categories are concerns rather than types:

| Category | What it records |
| --- | --- |
| `lifecycle` | Start requested, meeting active, pause, resume, intentional stop, and the ending finalisation recorded |
| `capture` | Source discovery, capture started with its format, capture stopped, a stream that ended unexpectedly |
| `recognition` | A run starting and stopping, an automatic restart attempted and its result, a restart budget exhausted |
| `persistence` | Session directory created, transcript opened, a transcript that stopped being written |
| `audio` | Retention disabled or a recording opened with its format, a recording finalised, a write or finalisation failure |
| `recovery` | What an unfinished-session scan found, a record it refused, an interruption recorded |
| `history` | Reading past meetings back |
| `diagnostics` | A report written, refused, or an export cancelled |

Nothing runs per audio buffer, per partial hypothesis, per transcript span or
per interface update. The log describes transitions and failures, so a
multi-hour meeting produces a readable handful of lines rather than a stream.

## Limitations

- A report describes ScribeKit's current state, not its history. It is
  assembled when you ask for one and is not stored, so it says nothing about a
  meeting that ended before the last one, and nothing about a previous launch
  beyond what an unfinished-session scan found.
- `readiness` and `storage` are absent when the main window has not been open
  in this launch. That is not the same claim as "nothing is ready" — ScribeKit
  simply has not evaluated it.
- The report carries no transcript or recording byte counts. Reading them would
  mean opening security-scoped access to your folder to stat a canonical
  artifact, which is more than a support field is worth.
- Exporting a report never reads, writes or repairs a transcript, a recording,
  a session record or a sidecar.
- ScribeKit does not read, collect or attach the unified log, and does not
  harvest crash reports. Console and `log` are the tools for those, and they
  are the system's.
