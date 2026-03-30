# mactools

Small macOS utilities collected in one repo. Each tool lives in its own top-level folder and can evolve independently.

Shared agent knowledge lives in `.agent/knowledge-base.md`.
Tool-specific progress should live in each tool's `.agent/progress.md`.

## Tools

| Tool | Purpose | Status | Build / Install | Permissions |
| --- | --- | --- | --- | --- |
| `layerkey` | Menu bar remapper for desktop-switch shortcuts. Current MVP supports `tab + 0-9 -> option + 0-9`. | Active | `cd layerkey && ./scripts/build-install-local.sh` | `Accessibility` |