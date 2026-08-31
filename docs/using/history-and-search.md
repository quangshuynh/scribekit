# History & Search

The History screen lists the meetings in your save folder — completed, failed,
interrupted, and the one running right now — newest first.

Each entry shows its status, times, captured applications, recognition
language, transcript size, and whether a recording is beside it. Selecting one
shows its details and a preview of its transcript, and reveals the transcript
or the recording in the Finder, or opens the transcript in whichever
application you use for Markdown.

## Search

Search is plain, case-insensitive substring matching over meeting titles,
recognised speech and captured application names, with a short excerpt of the
matching passage and the transcript timestamp it came from.

It is deterministic text matching, not semantic or AI search: no embeddings, no
vector database, no cloud service, and no index file written anywhere near your
transcripts. Consequently there is no fuzzy matching, no stemming and no
synonyms — a search for `closures` does not find `closure`, a misheard word is
found only by searching for what the recogniser actually wrote, and a phrase
split across two finalised spans is not matched.

Search does not match ScribeKit's own writing in a transcript — the header,
minute headings, gap markers, the interruption notice and the footer — so a
query for `Transcription gap` finds nothing. Titles and application names are
searched as metadata.

## History never writes

Listing, previewing, refreshing and searching leave every transcript,
recording, session record and review sidecar byte-identical, including their
modification dates. The boundary is a type: the protocol History reads through
has no method that creates, replaces, appends to or deletes anything.

- A meeting whose session record is damaged, missing or written by a newer
  ScribeKit is reported as such and left exactly as it is, and never stops the
  rest of the folder from listing.
- A directory holding a ScribeKit transcript with no session record — written
  before session records existed — is listed as a legacy meeting with only the
  facts its transcript actually states. Markdown ScribeKit did not write is not
  listed as a meeting.
- A meeting that is running shows as **In Progress**, and its transcript is
  read as it grows. History cannot start or stop it.

## Scope and freshness

History lists the save folder you chose, one level deep. It does not search
your Mac for transcripts, does not follow a folder you moved a session out of,
and does not remember meetings from a folder you have since replaced.

It reads the folder when it opens, when you refresh, and when a meeting
finishes. There is no filesystem watcher, so a session added by something else
while History is open appears on the next refresh.

Whole transcripts are held in memory while History is open, so its cost grows
with the folder. Measured on this Mac in a debug build: 200 one-hour meetings —
48,000 spans, 7.9 MB of transcript — load in 0.82 s and search in 100–160 ms
per query, for a 17 MB memory increase.

There is no editor, no rename, no delete and no export. The files are yours to
manage in the Finder.
