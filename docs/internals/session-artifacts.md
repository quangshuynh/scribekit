# Session Artifacts

A session is laid out as a directory named from its date and title:

```
<chosen save folder>/
  2026-08-29-closures-walkthrough/
    transcript.md
    audio.caf         # raw retention only
    audio.m4a         # compressed retention only
    .scribekit/
      session.json
      review.json     # written when there is anything to review
      derived.json    # written when you write a note or a mark
```

The directory name comes from `SessionDirectoryName` — a date prefix plus a
title slug, with a numeric suffix on collision — and the paths from
`SessionArtifactLayout`.

## Source and derived

Source material and user-derived state are separate files, and only one side is
writable.

| File | Side | Written by |
| --- | --- | --- |
| [`transcript.md`](../reference/transcript-format.md) | Source | The meeting, as it runs |
| `audio.caf` / `audio.m4a` | Source | The meeting, as it runs |
| [`.scribekit/session.json`](../reference/session-metadata.md) | Source | The meeting, before it starts and after it closes |
| [`.scribekit/review.json`](../reference/review-metadata.md) | Source | The meeting, once, after the transcript closed |
| [`.scribekit/derived.json`](../reference/derived-metadata.md) | Derived | You, through notes and reviewed marks |

Reading a meeting back never rewrites source material. A feature that lets you
decide something writes its own versioned sidecar under `.scribekit/` instead.
The boundary is a type rather than a rule: the protocol History reads through
has no write method, the protocol that writes derived state can address no
source artifact, and a failed derived write therefore cannot damage one.

## Sidecars are optional by construction

Metadata about a transcript is not transcript material. Anything ScribeKit
records *about* what was said lives in a versioned sidecar, never in recognised
prose and never in a form that rewrites, annotates or reorders the Markdown.

A sidecar points at spans by position rather than copying their words, a
session without one behaves exactly as it did before the sidecar existed, and
failing to write one never fails a meeting whose durable artifacts closed
cleanly.

A sidecar is refused rather than overwritten when it is damaged, announces a
schema this build does not know, names another session, or has changed since it
was loaded. None of that stops the meeting from listing, opening or being
searched.

Nothing derived from a sidecar may be presented with more precision than the
thing it was derived from actually has.

## Access

Access to your folder is opened for the length of one read or one write and
closed again. See [Save Location](../getting-started/save-location.md).
