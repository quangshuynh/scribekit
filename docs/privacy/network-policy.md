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

- No diagnostic upload. A diagnostic report is created only when you ask for
  one, written only where you say, and never sent anywhere. See
  [Diagnostics & Support](diagnostics.md).

## Local logging is not telemetry

ScribeKit writes to the macOS unified logging system, the local facility every
application on a Mac uses. Those entries stay on your Mac under the system's
own retention; nothing reads them but you, and ScribeKit itself never collects
or attaches them.

## Getting data out

The only way anything leaves your Mac is you moving it: the files are ordinary
Markdown and audio in a folder you chose, and there is no export feature to
route them anywhere. A diagnostic report is the one file ScribeKit writes
outside that folder, and only to a location you pick in a save panel.
