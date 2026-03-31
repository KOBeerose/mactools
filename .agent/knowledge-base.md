# mactools knowledge base

Shared repository conventions for agent work.

## Conventions

- One top-level folder per tool.
- Keep each tool buildable on its own.
- Put local build/install helpers under each tool's `scripts/`.
- Keep human-facing docs in each tool's `README.md`.
- Put tool-specific planning and internal notes under that tool's `.agent/`.
- Track progress per tool in that tool's `.agent/progress.md`, not at the repo root.
- Commit only durable `.agent` docs by default: `.agent/progress.md` and `.agent/structure.md`.

## Agent skills / workflows

Reusable workflows are documented in `.cursor/skills/`. Each skill is a folder with a `SKILL.md` entry point.

| Skill | Trigger | Path |
| --- | --- | --- |
| `sync-fork-submodule` | Syncing or adding a fork-based submodule | `.cursor/skills/sync-fork-submodule/SKILL.md` |

When asked to perform a task that matches a skill above, read the corresponding `SKILL.md` and follow it.
