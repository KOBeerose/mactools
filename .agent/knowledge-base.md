# mactools knowledge base

Shared repository conventions for agent work.

## Conventions

- One top-level folder per tool.
- Keep each tool buildable on its own.
- Put local build/install helpers under each tool's `scripts/`.
- Keep human-facing docs in each tool's `README.md`.
- Put tool-specific planning and internal notes under that tool's `.agent/`.
- Track progress per tool in that tool's `.agent/progress.md`, not at the repo root.
