# modifier-override

`modifier-override` is a small macOS menu bar tool for custom desktop-switch shortcuts.

## Current MVP

- Supports `tab + 0-9 -> option + 0-9`
- Installs as `~/Applications/ModifierOverride.app`
- Uses `Accessibility` permission for the current Tab-based remap flow

## Build and install

```bash
cd modifier-override
./scripts/build-install-local.sh
```

## Layout

```text
modifier-override/
  .agent/
  Package.swift
  README.md
  Sources/
  scripts/
```

## Notes

- `caps_lock` support is planned for a later version.
- App icon/logo is still pending.
