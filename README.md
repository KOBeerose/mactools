# mactools

Small macOS utilities collected in one repo. Each tool lives in its own top-level folder and can evolve independently.

Shared agent knowledge lives in `.agent/knowledge-base.md`.
Tool-specific progress should live in each tool's `.agent/progress.md`.

## Tools

| Tool | Purpose | Status | Build / Install | Permissions |
| --- | --- | --- | --- | --- |
| `layerkey` | Menu bar remapper for desktop-switch shortcuts. Current MVP supports `tab + 0-9 -> option + 0-9`. | Active | `cd layerkey && ./scripts/build-install-local.sh` | `Accessibility` |
| `spaceman` | Submodule fork of [ruittenb/Spaceman](https://github.com/ruittenb/Spaceman). Menu bar desktop space indicator. | Active | `cd spaceman && ./scripts/build-install-local.sh` | — |

## Submodules

Tools marked as submodules are forks hosted under the KobeTools org. Each has two remotes: `origin` (KobeTools fork) and `upstream` (original author).

**Cloning with submodules:**
```bash
git clone --recurse-submodules https://github.com/KOBeerose/mactools.git
# or after a plain clone:
git submodule update --init
```

**Adding a new submodule:** provide the upstream URL to the agent — it derives the KobeTools fork URL automatically and handles setup.
> "add submodule: https://github.com/OriginalAuthor/SomeRepo"

**Syncing a submodule with upstream:** ask the agent to sync — it fetches upstream, reviews the diff, presents a summary, and waits for your approval before merging.
> "sync spaceman submodule"

Agent skill: `.cursor/skills/sync-fork-submodule/`