# LayerKey progress

## Completed milestones

### Milestone 1: App scaffold and local install

- Swift package scaffold created.
- Local build/install/signing script added.
- App installs to `~/Applications/LayerKey.app`.

### Milestone 2: Working Tab-based layer MVP

- `tab + 0-9 -> option + 0-9` is implemented.
- Plain `tab` still works normally.
- `cmd-tab` and other modified Tab shortcuts are preserved.

### Milestone 3: Stability and packaging polish

- Event tap stability improved by removing the periodic tap restart.
- App bundle icon generation added.
- Menu bar icon switched to a clean keyboard-style symbol.
- Project/app naming updated from `ModifierOverride` to `LayerKey`.

### Milestone 4: Startup behavior

- Added an optional Launch at Login toggle in the menu bar app.
- Switched startup handling to native macOS login item registration.
- Removed the temporary LaunchAgent fallback and cleanup path.

## Pending work

- Validate and refine true `caps_lock` support via the lower-level HID path.
- Decide whether the menu bar icon needs a custom monochrome asset beyond the current symbol.
