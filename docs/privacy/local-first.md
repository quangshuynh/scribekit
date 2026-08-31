# Local-first Model

Everything stays on your machine unless you explicitly export it.

- **No accounts.** There is nothing to sign in to.
- **No cloud database.** Transcripts are files in a folder you chose.
- **No telemetry, no analytics, no crash reporting.** ScribeKit makes no
  network calls for any of them, because it cannot make network calls at all.
  See [Network Policy](network-policy.md).
- **No stealth capture.** Capture is always visible to the user. There is no
  hidden or silent recording mode.
- **Recognition is local.** `SpeechAnalyzer` runs against a model installed on
  your Mac, and there is no network fallback, silent or otherwise. See
  [On-device Speech](../internals/on-device-speech.md).
- **Search is local and computed.** Plain substring matching over transcripts
  already loaded: no embeddings, no vector database, no cloud service, and no
  index file written anywhere near your transcripts.

## Raw transcripts are source material

The raw transcript is never silently rewritten — not by AI, LLMs,
summarisation, grammar cleanup, inferred substitutions or semantic rewriting.

Derived artifacts — notes, marks, and whatever later work adds — must be
explicitly requested by you, stored separately from the raw transcript,
incapable of overwriting it, and clearly distinguishable from captured
transcription in the interface. See
[Session Artifacts](../internals/session-artifacts.md).

## What is not claimed

!!! warning "No encryption"

    ScribeKit does not encrypt anything. `transcript.md`, the session record
    and any retained recording are ordinary files in the folder you chose, and
    they are exactly as private as that folder is. Anyone who can read the
    folder can read the transcript and play the recording.

ScribeKit also makes no claim to be crash-proof; see
[Crash Recovery](../reliability/crash-recovery.md).
