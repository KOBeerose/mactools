# LayerKey

`LayerKey` is a small macOS menu bar tool for custom desktop-switch shortcuts.

## Current MVP

- Supports `tab + 0-9 -> option + 0-9`
- Preserves plain `tab`
- Preserves `cmd-tab` and other modified Tab shortcuts
- Supports an optional Launch at Login toggle
- Installs as `~/Applications/LayerKey.app`
- Uses `Accessibility` permission for the current Tab-based remap flow

## Build and install

```bash
cd layerkey
./scripts/build-install-local.sh
```

The install script:

- builds the Swift package
- creates the `.app` bundle
- generates the app icon from `assets/app-icon.svg`
- ad-hoc signs the installed app
- installs and opens `~/Applications/LayerKey.app`

## Layout

```text
layerkey/
  .agent/
    progress.md
    structure.md
  Package.swift
  README.md
  assets/
  Sources/
  scripts/
```

## Internal docs

- `.agent/structure.md` is the durable tracked reference for project layout and architecture.
- `.agent/progress.md` tracks completed milestones and remaining work.
- `.agent/plan.md` can exist locally for scratch planning, but it is ignored and not committed.

## Notes

- `caps_lock` support is still under development and should be treated as unfinished.
- The current validated path is the Tab-based remap flow.
- Launch at Login uses the native macOS login item path for the installed app bundle.
