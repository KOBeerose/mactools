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

## New Mac setup

When asked to set up a new Mac (or when the apps aren't installed yet), do these in order. Steps marked **(user)** need the user; ask them and wait.

1. `bash scripts/check-toolchain.sh` — compares Xcode/Swift with `toolchain.env`. If Xcode is missing, the user installs it from the App Store **(user)**.
2. `bash scripts/create-signing-identity.sh` — creates the "KobeTools Dev" certificate so privacy grants survive rebuilds. macOS asks for the password to trust it **(user)**. Skips itself if it already exists.
3. `./scripts/install-all.sh` — submodules, upstream remotes, pre-push hook, then builds and installs every tool.
   Then `./scripts/update-personal.sh` — creates the `mactools-personal` worktree and replaces BetterModifiers with the personal build (see "Personal branch").
4. Clone the private settings repo next to mactools: `gh repo clone KOBeerose/app-settings ../app-settings`. Needs `gh auth login` first **(user)**.
5. Quit all the tools (they rewrite their settings on quit), then `bash scripts/restore-settings.sh`. With no backup under this Mac's name it uses the only backup there is; if there are several it lists them — ask the user which Mac to copy.
6. Grant permissions in System Settings → Privacy & Security **(user)**:
   - Accessibility: BetterModifiers, Spaceman, Maccy, DockDoor
   - Automation: Spaceman
   - Screen Recording: DockDoor
   - Audio capture: FineTune (prompted on first use)
7. Reopen the tools, and quit (⌘Q) and reopen other open apps so they load the restored keyboard shortcuts.
8. Check: hold Tab and press 1 — BetterModifiers' General page shows it under Last Triggered. Tab+F fills the front window, Tab+R restores it.
9. Run `bash scripts/backup-settings.sh` once so this Mac gets its own backup folder.

## Personal branch

`main` is the general version. The `personal` branch adds a few commits only for this user's setup, on top of `main`. Today: BetterModifiers app rules step aside while BetterPalette's palette or DualWhisper's dictation pill is on screen, so Escape closes them in one press while Claude's Escape double-tap rule stays on otherwise.

- `personal` is checked out in a worktree next to mactools: `Coding/mactools-personal`. `Coding/mactools` stays on `main`. Never switch either one to the other branch.
- Develop, commit and push general changes in `mactools` on `main`.
- Then run `./scripts/update-personal.sh`. It rebases `personal` onto `main`, force-pushes it (with lease), and builds and installs BetterModifiers from the worktree. On a conflict it stops and says how to continue.
- Install BetterModifiers only through that script, not with `bettermodifiers/scripts/build-install-local.sh` from `mactools`, or the general build replaces the personal one.
- A change meant only for this setup is committed in `mactools-personal` on `personal`, then the script is run again.

## Settings backups

App settings are backed up to the private [app-settings](https://github.com/KOBeerose/app-settings) repo (cloned next to mactools) under `mac/<computer>/`.

- After changing an app's settings, or shipping a change that alters saved settings (new defaults, a migration), run `bash scripts/backup-settings.sh`. It commits and pushes.
- Restore on another Mac with `bash scripts/restore-settings.sh`.
- A tool that saves settings must be listed in both scripts.
- The scripts also save macOS keyboard shortcuts under `macos/`: App Shortcuts (global and per-app `NSUserKeyEquivalents`), system shortcuts (`com.apple.symbolichotkeys`), and the title-bar double-click action. BetterModifiers rules like Tab+F / Tab+R send chords that only work because of these App Shortcuts.

## Adding a new tool

When a new tool is added to mactools, update the following files:

1. **`README.md`** — add a row to the Tools table (name, purpose, status, build command, permissions)
2. **`knowledge-base.md`** (this file) — no change needed if it's a standard tool; update if it introduces new conventions
3. **`scripts/install-all.sh`** — add the tool name to the `TOOLS` array
4. **`scripts/backup-settings.sh`** and **`scripts/restore-settings.sh`** — include the tool's settings, if it saves any

If the new tool is a forked submodule, also update:
5. **`scripts/install-all.sh`** — add an entry to the `UPSTREAM_REMOTES` array
6. **`.cursor/skills/sync-fork-submodule/submodule-guide.md`** — add a row to the Current submodules table

## Agent skills / workflows

Reusable workflows are documented in `.cursor/skills/`. Each skill is a folder with a `SKILL.md` entry point.

| Skill | Trigger | Path |
| --- | --- | --- |
| `sync-fork-submodule` | Syncing a submodule with upstream, or forking and adding a new one | `.cursor/skills/sync-fork-submodule/SKILL.md` |

When asked to perform a task that matches a skill above, read the corresponding `SKILL.md` and follow it.
