# CLAUDE.md

- Read `AGENTS.md` first; it is the engineering contract for this repository.
- Read `CONTEXT.md` when the current state of the project matters.
- Inspect the relevant code before changing it.
- Preserve the established architecture and conventions.
- Keep work scoped to what was asked; do not implement future milestones early.
- Never simulate unimplemented behaviour, and never rewrite raw transcripts.
- Validate with a build and the unit tests before reporting completion:

  ```bash
  xcodebuild -project ScribeKit.xcodeproj -scheme ScribeKit -destination 'platform=macOS' test
  ```

- Update `CONTEXT.md` when the project state changes.
- Do not duplicate repository-wide documentation here or in commit messages.
- Do not repeatedly summarise the repository back to the user.
