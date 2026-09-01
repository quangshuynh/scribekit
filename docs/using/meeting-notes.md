# Meeting Notes

A meeting's detail pane in History has a notes area you can type into. It is
plain Markdown source, kept verbatim: ScribeKit does not render it, reflow it,
trim it or generate a word of it, and there is no AI here. Notes stay on your
Mac and go nowhere.

## Saving

Notes are saved when you press **Save**, and ScribeKit says *Saved* only after
the file was actually written. Until then it says *Unsaved changes*; if a save
fails it says why and your text stays in the editor. Selecting a different
meeting before saving discards the text you had not saved — there is no draft
that follows you to another meeting, and the pane says so.

Text you have typed survives History rebuilding its listing. Returning to the
History tab, pressing **Refresh** and a meeting finishing elsewhere all re-read
the save folder, and none of them is you leaving the meeting: the same meeting
stays selected and your unsaved text stays in the editor. If the notes file
changed on disk in the meantime, the editor shows what is now on disk instead,
because that is the version a save would have to land on.

A reviewed mark, by contrast, is a discrete decision and is written the moment
you make it. Marking a passage writes the notes already on disk, not the draft;
saving notes carries the marks already on disk through unchanged. Neither
action can revise the other. Writes are atomic, so there is no half-written
file.

## Where they live

Your notes and your reviewed marks are the only things ScribeKit writes on your
behalf after a meeting has closed, and they go to one file of their own:
`.scribekit/derived.json` in the meeting's folder.

`transcript.md`, the recording, `session.json` and `review.json` are source
material and stay byte-identical however much you write. Delete `derived.json`
and you lose your notes and your marks; the meeting itself is exactly as it
was.

See [Derived Metadata](../reference/derived-metadata.md) for the file's shape
and the conditions under which ScribeKit refuses to write it.

## Limits

- Notes are not searchable. History's search runs over titles, transcripts and
  source names; what you write in the notes area does not match a query.
- Notes and reviewed marks need a meeting with a ScribeKit session record. A
  transcript from before session records existed has no identity to attach them
  to, so its notes area is unavailable.
