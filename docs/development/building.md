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
