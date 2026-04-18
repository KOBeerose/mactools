# LayerKey structure

## Purpose

`LayerKey` is a small macOS menu bar app for desktop-switch shortcut remapping.

Current validated behavior:

- `tab + 0-9 -> option + 0-9`
- plain `tab` still works normally
- `cmd-tab` and other modified Tab shortcuts are preserved

## Project layout

```text
layerkey/
  .agent/
    progress.md
    structure.md
  assets/
    app-icon.svg
  Package.swift
  README.md
  Sources/
    LayerKeyHID/
      include/
      LayerKeyHID.c
    layerkey/
      AppDelegate.swift
      CapsLockController.swift
      EventTapController.swift
      LayerKeyMain.swift
      LaunchAtLoginController.swift
      PermissionsController.swift
      SettingsStore.swift
      ShortcutRule.swift
  scripts/
    build-install-local.sh
```

## Main components

### `Sources/layerkey/AppDelegate.swift`

- menu bar app entry wiring
- status menu
- permission polling and refresh logic

### `Sources/layerkey/EventTapController.swift`

- installs and manages the `CGEventTap`
- handles Tab-based layer behavior
- emits remapped key events

### `Sources/layerkey/CapsLockController.swift`

- Swift wrapper around the HID bridge
- intended to support lower-level Caps Lock handling

### `Sources/layerkey/LaunchAtLoginController.swift`

- wraps native macOS login item registration via `SMAppService`
- reports startup state back to the menu UI

### `Sources/LayerKeyHID/`

- low-level C bridge for HID operations
- used for Caps Lock remapping/state control

### `scripts/build-install-local.sh`

- cleans and builds the Swift package
- assembles the `.app` bundle
- generates the app icon
- ad-hoc signs and installs to `~/Applications/LayerKey.app`

## Current architecture notes

- The validated MVP relies on a `CGEventTap` and `Accessibility`.
- Input Monitoring is not currently required for the Tab-based flow.
- Launch at login is supported for the installed app via native macOS login item registration.
- Caps Lock support is under development and should be treated as unfinished until validated.
