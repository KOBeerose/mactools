# mactools

Small macOS utilities collected in one repo. Each tool lives in its own top-level folder and can evolve independently.


## Installation

```bash
git clone https://github.com/KOBeerose/mactools.git
cd mactools
./scripts/install-all.sh
```

## Tools

| Tool | Purpose | Status | Build / Install | Permissions |
| --- | --- | --- | --- | --- |
| `bettermodifiers` | Native menu bar + SwiftUI app. Use `Tab` or `Caps Lock` as full modifier keys with user-defined rules `Trigger + Key -> [⌘⌥⌃⇧]+Key`. Successor to LayerKey. | Active | `cd bettermodifiers && ./scripts/build-install-local.sh` | `Accessibility` |
| `spaceman` | Fork of [ruittenb/Spaceman](https://github.com/ruittenb/Spaceman). Menu bar desktop space indicator with space switching. Local changes: disabled auto-updater, added local build script. | Active | `cd spaceman && ./scripts/build-install-local.sh` | `Accessibility`, `Automation` |

Shared agent knowledge lives in `.agent/knowledge-base.md`.
Tool-specific progress should live in each tool's `.agent/progress.md`.

## Agent skills

| Task | Prompt | Skill |
| --- | --- | --- |
| Fork and add a new submodule | `"fork and add submodule: https://github.com/OriginalAuthor/SomeRepo"` | `sync-fork-submodule` |
| Sync one submodule with upstream | `"sync submodule: spaceman"` | `sync-fork-submodule` |
| Sync all submodules with upstream | `"sync all submodules"` | `sync-fork-submodule` |

Skills live in `.cursor/skills/`. See `.agent/knowledge-base.md` for full details.