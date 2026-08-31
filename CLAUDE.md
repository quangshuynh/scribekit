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

## Reading the documentation

`README.md` is a concise repository overview. The detailed documentation lives
under `docs/` and is published as a site; it is explanatory and reference
material, not a substitute for the code, the tests or `CONTEXT.md` when
determining what the implementation currently does.

For an implementation task:

- Start with `AGENTS.md` and `CONTEXT.md`. Do not routinely read `README.md`
  plus the whole `docs/` tree.
- Search before opening. Use a targeted `grep` over `docs/` to find the page
  that covers the subject rather than reading the tree.
- Open a docs page only when the task touches that subject.
- Update the pages the change actually touches. An interval does not update
  every documentation page.
- Documentation changes are validated with `mkdocs build --strict`; see
  `docs/development/documentation.md`.
