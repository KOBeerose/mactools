# LayerKey

`LayerKey` is a small macOS menu bar tool for custom desktop-switch shortcuts.

## Current MVP

- Supports `tab + 0-9 -> option + 0-9`
- Installs as `~/Applications/LayerKey.app`
- Uses `Accessibility` permission for the current Tab-based remap flow

## Build and install

```bash
cd layerkey
./scripts/build-install-local.sh
```

## Layout

```text
layerkey/
  .agent/
  Package.swift
  README.md
  Sources/
  scripts/
```

## Notes

- `caps_lock` support is planned for a later version.
- App icon/logo is still pending.
