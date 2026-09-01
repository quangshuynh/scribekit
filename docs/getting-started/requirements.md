# Requirements

| Requirement | Version | Why |
| --- | --- | --- |
| macOS | 26.5 or later | The built application declares `LSMinimumSystemVersion` 26.5, so macOS refuses to launch it on anything earlier. The APIs it uses — `SpeechAnalyzer`/`SpeechTranscriber` and the ScreenCaptureKit behaviour ScribeKit relies on — are available from macOS 26.0, but no build has been made or tested against a lower target. |
| Mac | Apple Silicon | The only architecture ScribeKit has been built and validated on. The project builds a universal binary, but nothing has been tested on Intel. |
| Xcode | 26 or later | Builds the macOS 26.5 target, and is currently the only way to get a running ScribeKit. |
| On-device speech model | Installed for the recognition language | Recognition is local; ScribeKit does not download models, and there is no network fallback. |

**v0.1.0 is a source release.** No signed or notarized application is
published, so [building from source](build-and-run.md) is the only way to run
ScribeKit. See [Releases](../reference/releases.md).

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
