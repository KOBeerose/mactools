# mactools

Small macOS utilities collected in one repo. Each tool lives in its own top-level folder and can evolve independently.


## Installation

```bash
git clone https://github.com/KOBeerose/mactools.git
cd mactools
./scripts/install-all.sh
```

Windows tools (including the cross-platform Wox launcher) live in the companion [wintools](https://github.com/KOBeerose/wintools) repo. Settings backups go to the private [app-settings](https://github.com/KOBeerose/app-settings) repo: clone it next to `mactools`, then run `scripts/backup-settings.sh` / `scripts/restore-settings.sh`.

`install-all.sh` also enables a pre-push hook that refuses to push mactools while a submodule points at a commit its fork doesn't have yet.

## Tools

| Tool | Purpose | Status | Build / Install | Permissions |
| --- | --- | --- | --- | --- |
| `bettermodifiers` | Native menu bar + SwiftUI app. Use `Tab` or `Caps Lock` as full modifier keys with user-defined rules `Trigger + Key -> [⌘⌥⌃⇧]+Key`. Per-app key rules (double-tap, block, remap). Successor to LayerKey. | Active | `cd bettermodifiers && ./scripts/build-install-local.sh` | `Accessibility` |
| `spaceman` | Fork of [ruittenb/Spaceman](https://github.com/ruittenb/Spaceman). Menu bar desktop space indicator with space switching. Local changes: Sparkle never started and update feed/buttons removed, local build script, "Fullscreen space names" setting (App name / Short / None). | Active | `cd spaceman && ./scripts/build-install-local.sh` | `Accessibility`, `Automation` |
| `maccy` | Fork of [p0deje/Maccy](https://github.com/p0deje/Maccy). Clipboard manager. Local changes: Sparkle never started, update feed removed, local build script (ad-hoc signed, keeps sandbox history). | Active | `cd maccy && ./scripts/build-install-local.sh` | `Accessibility` |
| `finetune` | Fork of [ronitsingh10/FineTune](https://github.com/ronitsingh10/FineTune). Per-app volume, EQ, boost and input/output switching (replaces eqMac). Local changes: Sparkle never started, update feed removed, local build script. | Active | `cd finetune && ./scripts/build-install-local.sh` | `Audio capture` |
| `dockdoor` | Fork of [ejbills/DockDoor](https://github.com/ejbills/DockDoor). Window previews and switcher for the Dock. Local changes: Sparkle never started, update feed and menu item removed, local Release build script. | Active | `cd dockdoor && ./scripts/build-install-local.sh` | `Accessibility`, `Screen Recording` |

Shared agent knowledge lives in `.agent/knowledge-base.md`.
Tool-specific progress should live in each tool's `.agent/progress.md`.

## Agent skills

| Task | Prompt | Skill |
| --- | --- | --- |
| Fork and add a new submodule | `"fork and add submodule: https://github.com/OriginalAuthor/SomeRepo"` | `sync-fork-submodule` |
| Sync one submodule with upstream | `"sync submodule: spaceman"` | `sync-fork-submodule` |
| Sync all submodules with upstream | `"sync all submodules"` | `sync-fork-submodule` |

Before any sync, `scripts/audit-upstream.sh <submodule>` prints what upstream would bring in (dependencies, permissions, build scripts, updater, network code, agent/CI files) and previews conflicts, without merging.

Skills live in `.cursor/skills/`. See `.agent/knowledge-base.md` for full details.