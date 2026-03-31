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

## Adding a new tool

When a new tool is added to mactools, update the following files:

1. **`README.md`** — add a row to the Tools table (name, purpose, status, build command, permissions)
2. **`knowledge-base.md`** (this file) — no change needed if it's a standard tool; update if it introduces new conventions
3. **`scripts/install-all.sh`** — add the tool name to the `TOOLS` array

If the new tool is a forked submodule, also update:
4. **`.cursor/skills/sync-fork-submodule/submodule-guide.md`** — add a row to the Current submodules table

## Agent skills / workflows

Reusable workflows are documented in `.cursor/skills/`. Each skill is a folder with a `SKILL.md` entry point.

| Skill | Trigger | Path |
| --- | --- | --- |
| `sync-fork-submodule` | Syncing a submodule with upstream, or forking and adding a new one | `.cursor/skills/sync-fork-submodule/SKILL.md` |

When asked to perform a task that matches a skill above, read the corresponding `SKILL.md` and follow it.
