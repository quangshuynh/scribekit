# Build & Run

## Build

```bash
xcodebuild -project ScribeKit.xcodeproj -scheme ScribeKit -destination 'platform=macOS' build
```

Or open `ScribeKit.xcodeproj` in Xcode and run the `ScribeKit` scheme. The
`ScribeKit` scheme is shared and committed, because CI depends on it.

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
