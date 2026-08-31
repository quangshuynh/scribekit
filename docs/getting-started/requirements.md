# Requirements

| Requirement | Version | Why |
| --- | --- | --- |
| macOS | 26 or later | `SpeechAnalyzer`/`SpeechTranscriber` and the ScreenCaptureKit behaviour ScribeKit relies on. |
| Xcode | 26 or later | Builds a macOS 26 target. Only needed to build from source. |
| On-device speech model | Installed for the recognition language | Recognition is local; ScribeKit does not download models. |

ScribeKit is not distributed as a signed release build yet, so building from
source in Xcode is currently the only way to run it.

## Permissions

Listing applications and capturing their audio require **Screen & System Audio
Recording** permission, which macOS asks for the first time ScribeKit looks for
sources. Without it, the setup screen reports the missing permission instead of
a list or a capture.

Transcription itself asks for no permission, because it runs against a speech
model on this Mac rather than through a service. See
[Permissions](../privacy/permissions.md).

## Language models

The recognition language is chosen explicitly from the locales the recogniser
supports. Locales whose on-device model is not installed are listed and
disabled rather than silently unavailable, and ScribeKit refuses to start a
meeting in a language whose model is absent rather than installing one on your
behalf.
