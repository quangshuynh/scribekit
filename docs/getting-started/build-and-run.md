# Build & Run

v0.1.0 publishes no signed or notarized application, so building from source is
how ScribeKit is run. See [Releases](../reference/releases.md).

## Build

```bash
git clone https://github.com/quangshuynh/scribekit.git
cd scribekit
xcodebuild -project ScribeKit.xcodeproj -scheme ScribeKit -destination 'platform=macOS' build
```

Or open `ScribeKit.xcodeproj` in Xcode and run the `ScribeKit` scheme. The
`ScribeKit` scheme is shared and committed, because CI depends on it.

## Signing

The project uses automatic signing and carries the author's development team,
so a fresh clone signs with whatever Apple Development identity is on the Mac
that builds it once you select your own team in Xcode's *Signing &
Capabilities* tab. A free Apple ID is enough; the paid Developer Program is
needed to *distribute* ScribeKit, not to build and run it.

To build without touching the project settings, sign ad-hoc the way CI does:

```bash
xcodebuild -project ScribeKit.xcodeproj -scheme ScribeKit -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
```

Both commands were run against a clean clone of the v0.1.0 source.

## Test

```bash
xcodebuild -project ScribeKit.xcodeproj -scheme ScribeKit -destination 'platform=macOS' test
```

Unit tests use [Swift Testing](https://developer.apple.com/documentation/testing).
See [Testing](../development/testing.md) for what they cover.

## First launch

1. macOS asks for Screen & System Audio Recording permission the first time
   ScribeKit looks for capture sources. Grant it, or the source list stays
   empty and says why.
2. Choose a save location in the system open panel. See
   [Save Location](save-location.md).
3. Choose a recognition language whose on-device model is installed.

Then go to [First Meeting](first-meeting.md).
