# Save Location

ScribeKit writes only into a folder you chose in the system open panel. The
choice is remembered across launches as a security-scoped bookmark; the
bookmark data never reaches the setup screen, which sees only a folder and its
state.

## What is created there

Each meeting gets its own directory, named from its date and title:

```
<chosen save folder>/
  2026-08-29-closures-walkthrough/
    transcript.md
    audio.caf         # raw retention only
    audio.m4a         # compressed retention only
    .scribekit/
      session.json
```

`transcript.md` and `.scribekit/session.json` are always created. Exactly one
audio file is created when retention is on, and none when it is off; there is
never both. See [Session Artifacts](../internals/session-artifacts.md).

## When the folder moves or disappears

- A folder macOS reports as **stale** — moved on the same disk — is followed
  automatically.
- A folder that was **deleted**, or whose disk is absent, has to be chosen
  again. ScribeKit says so rather than looking anywhere else, and offers
  controls to replace or forget the location.
- If the folder cannot be restored at launch, ScribeKit reports that it could
  not check for an unfinished meeting rather than scanning elsewhere.

The controls match those states: **Choose Folder…** or **Change Folder…** picks
one, **Forget Folder** stops remembering it, and **Try Again** resolves a
remembered folder afresh — for a disk that has since been reconnected. A folder
that was chosen but could not be remembered is still used for this launch, and
ScribeKit says it will need choosing again next time rather than treating it as
a failure. There is no fallback to Documents, Desktop or a temporary directory,
and no meeting starts without a folder you picked.

## Access lifetime

Access to the folder is held for exactly as long as a meeting is being
written, and released when its transcript is closed — including on every
failure path. Outside a meeting, access is borrowed only while the folder is
being validated or scanned for unfinished sessions. ScribeKit never weakens the
App Sandbox to reach a path and never writes to a location you did not pick.
