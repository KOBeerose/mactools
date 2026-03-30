---
name: Modifier Override Tool
overview: Build a tiny standalone macOS menu bar app in `modifier-override` that remaps trigger-plus-number combos into Mission Control shortcuts with a much narrower feature set than Karabiner. The MVP should be extensible, but focused on global key remapping with minimal UI and predictable permission handling.
todos:
  - id: scaffold-app
    content: Scaffold a tiny Swift menu bar app project in `modifier-override` with no updater or extra dependencies.
    status: pending
  - id: event-tap
    content: Implement a `CGEventTap`-based event pipeline and rule engine for trigger-plus-number remapping.
    status: pending
  - id: permissions
    content: Add explicit permission checks/onboarding for Input Monitoring and Accessibility, plus stable local signing/install workflow.
    status: pending
  - id: settings
    content: Add minimal persistent settings so rules can expand beyond the first `caps_lock + 0-9` mapping.
    status: pending
isProject: false
---

# Modifier Override Plan

## Goal

Create a small standalone macOS menu bar app under [/Users/tahaelghabi/Coding/modifier-override](/Users/tahaelghabi/Coding/modifier-override) that:

- listens globally for custom trigger layers like `caps_lock + 1`
- emits Mission Control-compatible shortcuts like `control + 1` or `command + 1`
- preserves normal key behavior when the trigger is tapped alone
- stays minimal in scope, permissions, and UI

## Why A Separate Tool

The current `Spaceman` implementation only supports real macOS modifier keys in both UI and shortcut generation, so it cannot express `caps_lock` or `tab` as a trigger layer:

- [/Users/tahaelghabi/Coding/Spaceman/Spaceman/Helpers/ShortcutHelper.swift](/Users/tahaelghabi/Coding/Spaceman/Spaceman/Helpers/ShortcutHelper.swift)
- [/Users/tahaelghabi/Coding/Spaceman/Spaceman/View/PreferencesView.swift](/Users/tahaelghabi/Coding/Spaceman/Spaceman/View/PreferencesView.swift)

## Recommended MVP

Use a native Swift menu bar app with these pieces:

- `ModifierOverride.xcodeproj` or equivalent app target in [/Users/tahaelghabi/Coding/modifier-override](/Users/tahaelghabi/Coding/modifier-override)
- `AppDelegate.swift` or SwiftUI app entry for a status bar app with no dock icon
- `EventTapController.swift` to install and maintain a `CGEventTap`
- `RuleEngine.swift` to map trigger states like `caps_lock` held -> `1...0` remapped to chosen output shortcuts
- `SettingsStore.swift` to persist rules and defaults
- `PermissionsController.swift` to preflight/request the needed macOS permissions and show exact setup guidance
- a tiny status bar menu for enable/disable, permissions status, and opening settings

## Core Behavior

Start with one clean rule model:

- input trigger key: `caps_lock` or `tab`
- input range: `0-9`
- output modifiers: `control`, `command`, `option`, `shift`, or combinations
- output key: same digit
- optional tap-alone behavior for the trigger key

The first implementation should:

- support both `caps_lock + 0-9` and `tab + 0-9`
- share one rule engine so additional trigger layers can be added by configuration, not redesign
- suppress the original keystroke when a rule matches
- pass through normal typing when no rule matches

## Permission Strategy

A real global remapper will still need macOS keyboard-event permissions. Plan for:

- `CGEventTap` for interception/remapping
- Input Monitoring permission for listening globally
- Accessibility permission for active interception/injection where required

Keep the trust surface small by:

- no network code
- no analytics/updater
- no browser/webview
- no unrelated automation features

## Packaging Strategy

To avoid the TCC instability you hit with unsigned local builds:

- use a stable app bundle path like `~/Applications/ModifierOverride.app`
- make local install/signing part of the project workflow from day one
- prefer stable local signing for repeated rebuilds, rather than ephemeral unsigned runs from build output

## Suggested Build Order

1. Scaffold a minimal menu bar app in [/Users/tahaelghabi/Coding/modifier-override](/Users/tahaelghabi/Coding/modifier-override).
2. Add a health-checked `CGEventTap` that logs raw key events and trigger state.
3. Implement the first rules: `tab + 1...0` and `caps_lock + 1...0` -> the configured Mission Control shortcut, initially `option + 1...0`.
4. Preserve normal tap-alone behavior for `tab` and `caps_lock` whenever no remap chord is completed.
5. Add permission onboarding and clear status/error reporting.
6. Add a simple settings UI and persisted rule model for extensibility.
7. Add a build/install script similar to the one used for your local `Spaceman` workflow.

## Success Criteria

The tool is successful when:

- `caps_lock + number` and `tab + number` reliably switch spaces without Karabiner
- plain `caps_lock` and plain `tab` still behave normally when tapped alone
- the app is small, local-only, and understandable
- rebuild/reinstall does not constantly break permissions
