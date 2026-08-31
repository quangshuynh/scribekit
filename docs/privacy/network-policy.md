# Network Policy

ScribeKit does not make network calls, and cannot.

The app ships **without the network client entitlement**, so the App Sandbox
does not permit it to open a network connection. This is not a policy the code
follows — it is a capability the process does not have.

## What that rules out

- No telemetry, analytics or crash reporting.
- No accounts, sync or cloud database.
- No server-backed speech recognition, and no fallback to it. ScribeKit uses
  `SpeechAnalyzer` and `SpeechTranscriber` against a locally installed model,
  and specifically does *not* use `SFSpeechRecognizer`, the older API that can
  send audio to Apple's servers.
- No model downloads. A language whose on-device model is not installed is
  listed and disabled; ScribeKit reports it so you can install it, and does not
  fetch it for you.
- No embeddings, vector database or cloud search. History's search is plain
  substring matching, computed locally.
- No update check.

## Getting data out

The only way anything leaves your Mac is you moving it: the files are ordinary
Markdown and audio in a folder you chose, and there is no export feature to
route them anywhere.
