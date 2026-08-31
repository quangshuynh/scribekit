# Data Handling

## What ScribeKit writes, and where

Everything ScribeKit writes goes into the folder you chose in the system open
panel, under a directory per meeting. Nothing is written anywhere else.

| Data | File | When |
| --- | --- | --- |
| Recognised speech, timestamps, ScribeKit's structural remarks | `transcript.md` | Appended as the meeting runs |
| Captured audio | `audio.caf` or `audio.m4a` | Only when retention is on |
| Session identity, status, times, sources, language | `.scribekit/session.json` | Before the meeting starts; updated after its artifacts close |
| Which spans the recogniser was unsure about, by position | `.scribekit/review.json` | Once, after the transcript closed |
| Your notes and reviewed marks | `.scribekit/derived.json` | When you save a note or make a mark |

The one file ScribeKit writes outside that folder is a diagnostic report, and
only when you ask for one and pick where it goes. It contains no transcript
text, no audio and no folder path; see
[Diagnostics & Support](diagnostics.md).

Outside that folder, ScribeKit remembers only setup preferences: the save
location as a security-scoped bookmark, the retention mode, the applications
last selected, and the recognition language.

## What ScribeKit never writes

- No copy of your transcript, anywhere else on the Mac.
- No search index file. Search runs over what History already loaded, and
  anything derived from your transcripts is rebuilt on demand.
- No transcript text inside any sidecar. Sidecars point at spans by position;
  the words are read back from `transcript.md`.

## Reading is a read

Listing, indexing, previewing or searching a session leaves its transcript, its
recording and its session record byte-identical — including their modification
dates — and does not repair a damaged one. A disposable index may accelerate
search, but the Markdown and the session record stay authoritative.

## Deleting

ScribeKit has no delete. It never deletes a transcript, a recording, a session
record or a folder it created — not even a session folder left behind by a
start that failed. Deleting a meeting means deleting its directory in the
Finder.

Deleting `.scribekit/derived.json` loses your notes and marks and nothing else.
Deleting `.scribekit/` entirely leaves a transcript that still reads perfectly
and lists as a legacy meeting.
