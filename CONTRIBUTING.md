# Contributing

## Setup

Requires macOS 26 or later with Xcode 26. Open `ScribeKit.xcodeproj` — there
are no package dependencies to resolve.

## Build and test

```bash
xcodebuild -project ScribeKit.xcodeproj -scheme ScribeKit -destination 'platform=macOS' build
xcodebuild -project ScribeKit.xcodeproj -scheme ScribeKit -destination 'platform=macOS' test
```

Run both before opening a pull request. CI runs the same commands.

## Code and documentation

- Follow the rules in [AGENTS.md](AGENTS.md); it is the engineering contract.
- Document non-trivial types, methods and important properties with `///`,
  including parameters, return values and thrown errors.
- Unit tests use Swift Testing. Cover behaviour, not the existence of symbols.
- Avoid new dependencies; explain the need if one is unavoidable.
- Documentation lives under `docs/` and is published from `main`. If you touch
  it, run `mkdocs build --strict` — see `docs/development/documentation.md`.

## Commits and pull requests

- Use short, imperative commit subjects with a `type:` prefix
  (`feat:`, `fix:`, `test:`, `docs:`, `ci:`, `chore:`).
- Keep commits coherent; do not squash unrelated work into one commit.
- Fill in the pull request template, including the transcript/privacy and
  energy sections.
