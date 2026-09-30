# mactools

## Project context

Small macOS utilities, each in its own top-level folder. See `README.md` for the full tools list.

## Agent conventions

Read `.agent/knowledge-base.md` at the start of any session. It contains repo conventions and a table of available workflows/skills — including when and how to use them.

## New Mac

Setting up a new Mac from just this clone: follow "New Mac setup" in `.agent/knowledge-base.md` step by step. It installs the tools, restores settings and keyboard shortcuts from the private app-settings repo, and lists what the user has to do by hand.

## Key rules

- One tool per top-level folder; each is independently buildable.
- Build/install scripts live under each tool's `scripts/`.
- Planning and progress notes live under each tool's `.agent/`.
- After changing an app's settings, or shipping a change that alters saved settings (new defaults, a migration), run `bash scripts/backup-settings.sh` so the private app-settings repo stays current. See "Settings backups" in `.agent/knowledge-base.md`.
- Submodule tools are forks under the KobeTools GitHub org — follow the sync workflow in `.agent/knowledge-base.md` before merging upstream changes.
