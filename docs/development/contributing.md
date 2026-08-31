# Contributing

`CONTRIBUTING.md` in the repository root is the short version; `AGENTS.md` is
the durable engineering contract and is the file to read before changing
anything.

## Before you change code

1. Read `AGENTS.md`. Read `CONTEXT.md` when the current state of the project
   matters.
2. Inspect the relevant code before changing it.
3. Preserve the established architecture and conventions — see
   [Architecture Boundaries](architecture-boundaries.md).
4. Keep changes scoped to what was asked. Do not start later work early.

## Before you open a pull request

```bash
xcodebuild -project ScribeKit.xcodeproj -scheme ScribeKit -destination 'platform=macOS' test
```

Build and run the tests, and report real results. If you touched documentation,
also run `mkdocs build --strict` — see [Documentation](documentation.md).

## Things that will be pushed back on

- Simulating unimplemented behaviour, or describing a planned feature as
  working.
- Anything that rewrites, annotates or reorders a raw transcript.
- Anything that lets a derived artifact reach a source artifact.
- A new third-party dependency without a reason the platform cannot do the job.
- A change that makes an active meeting depend on a view's lifetime.
- Claiming a security or encryption property ScribeKit does not have.
