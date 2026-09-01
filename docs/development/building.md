# Building

## Requirements

macOS 26.5 or later and Xcode 26 or later. See
[Requirements](../getting-started/requirements.md).

## Build

```bash
xcodebuild -project ScribeKit.xcodeproj -scheme ScribeKit -destination 'platform=macOS' build
```

## Test

```bash
xcodebuild -project ScribeKit.xcodeproj -scheme ScribeKit -destination 'platform=macOS' test
```

The `ScribeKit` scheme is shared and must stay committed; CI depends on it.

## Continuous integration

`.github/workflows/ci.yml` runs on a `macos-26` runner and does two things:
`build-for-testing`, then `test-without-building`, both with ad-hoc signing so
the sandboxed app is launchable for unit tests without provisioning profiles or
team credentials.

CI runs build and unit tests only — no linting, formatting, coverage or UI
tests.

The documentation workflows are separate from application CI, and neither can
block the other. See [Documentation](documentation.md).

## Dependencies

ScribeKit prefers Apple platform frameworks over third-party dependencies. A
dependency is added only when the platform genuinely cannot do the job, and the
pull request has to say why.

## Distribution

A distributable ScribeKit is a Developer ID signed, notarized and stapled disk
image, `ScribeKit-<version>.dmg`, holding `ScribeKit.app` beside an
`Applications` alias. `Tools/Release/package.sh` runs the sequence: archive,
export, verify, notarize, staple, build the image, notarize and staple the
image, and report the Gatekeeper assessment and the SHA-256.

It stores no credentials. Notarization reads a `notarytool` keychain profile,
created once and interactively so no secret is ever written to the repository
or to a shell history:

```bash
xcrun notarytool store-credentials ScribeKit --apple-id <apple-id> --team-id <team-id>
```

Set `SCRIBEKIT_NOTARY_PROFILE` to use a differently named profile. Everything
the script writes lands in `build/release`, which is not tracked.

**The signing half of this has never run.** A Developer ID Application
certificate and Apple's notary service both require a paid Apple Developer
Program membership, which this release does not have, so the archive step is
the last step that has been exercised. What that archive proves is recorded in
[Releases](../reference/releases.md); an Apple Development signature is not a
substitute, and neither is ad-hoc signing, because neither passes Gatekeeper on
another Mac. v0.1.0 therefore ships as source.

## The application icon

`Tools/AppIcon/make-appicon.swift` regenerates the ten macOS representations in
`ScribeKit/Assets.xcassets/AppIcon.appiconset` from the brand mark in
`docs/images/scribekit-logo2.png`. Run it from the repository root after
changing the mark; the generated PNGs are tracked, because the build needs
them.
