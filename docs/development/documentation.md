# Documentation

This site is [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/),
built from the `docs/` directory and `mkdocs.yml` at the repository root.

ScribeKit is not a Python project, so the documentation toolchain is kept to
one pinned requirements file rather than a package definition.

## Building locally

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r docs/requirements.txt
mkdocs serve
```

Before opening a pull request that touches documentation:

```bash
mkdocs build --strict
```

Strict mode is not optional here. `mkdocs.yml` raises anchor and
unrecognised-link validation from `info` to `warn`, so a cross-reference
pointing at a heading that moved fails the build rather than publishing a page
that cannot be navigated.

The generated `site/` directory and the `.venv/` are ignored by Git.

## Workflows

Two workflows, both separate from application CI:

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `.github/workflows/docs-check.yml` | Pull requests touching `docs/**`, `mkdocs.yml` or the docs workflows | `mkdocs build --strict`. Never deploys. |
| `.github/workflows/docs.yml` | Push to `main` on the same paths, plus `workflow_dispatch` | Builds strict, configures Pages, uploads `site`, deploys. |

`ci.yml` gates whether the code is correct; the documentation workflows gate
whether the site publishes. Neither can block the other.

!!! note "One manual repository setting"

    The repository's Pages source must be set to **GitHub Actions** in
    *Settings → Pages* for the deploy step to succeed. It cannot be set from a
    workflow.

## Where a fact belongs

Each fact lives in one place:

- `README.md` — a concise repository overview. Not the manual.
- `AGENTS.md` — the durable engineering contract.
- `CONTEXT.md` — the current engineering handoff.
- `docs/` — explanatory and reference material.
- `docs/PERFORMANCE.md` — the canonical record of measurements taken on
  hardware. Historical measurements are appended to, never rewritten for prose
  consistency.

Do not duplicate an explanation between the README and a docs page, and do not
update every documentation page for every change: update the pages the change
actually touches.
