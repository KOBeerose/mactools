# mactools

## Project context

Small macOS utilities, each in its own top-level folder. See `README.md` for the full tools list.

## Agent conventions

Read `.agent/knowledge-base.md` at the start of any session. It contains repo conventions and a table of available workflows/skills — including when and how to use them.

## Key rules

- One tool per top-level folder; each is independently buildable.
- Build/install scripts live under each tool's `scripts/`.
- Planning and progress notes live under each tool's `.agent/`.
- Submodule tools are forks under the KobeTools GitHub org — follow the sync workflow in `.agent/knowledge-base.md` before merging upstream changes.
