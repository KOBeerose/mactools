# BetterModifiers

Use **Tab** and **Caps Lock** as full modifier keys on macOS. Define your own rules of the shape:

```
Trigger (Tab | Caps Lock) + InputKey  →  [⌘ ⌥ ⌃ ⇧]* + OutputKey
```

…or flip on **Hyper Key** mode and have the trigger act as a fixed modifier combo for any key that follows.

BetterModifiers is a small native menu bar utility (AppKit status item + SwiftUI `App` + `Window` Scene) that succeeds and replaces the earlier `layerkey` MVP. It keeps the proven event-tap engine and adds a real rule editor, a Modifier Mode page, theming, and Sparkle-based updates.

**Current version: 1.0.0**

## Highlights

- **Menu bar app** (`LSUIElement = true`). No Dock icon, low memory. Closing the window keeps the engine running so your remaps stay live; quit explicitly from the menu bar.
- **Modifier Mode** per trigger (Tab and Caps Lock independently) — turns the trigger into a fixed modifier combo for any following key.
- **Rule editor** with explicit ⌃⌥⇧⌘ toggles so you can author shortcuts the OS would normally swallow (e.g. `⌃⌘ + Arrow`).
- **HID-level Caps Lock remap** to F18 while running, with a synthetic `flagsChanged` event so browsers stay in sync.
- **Appearance**: System / Light / Dark, plus a "Hide menu bar icon" mode (re-open from Finder).
- **Sparkle 2 updates** with auto-check and a Check Now button in About.
- **One-shot legacy migration** removes old LayerKey / ModifierOverride / Better Modifiers installs.
- **One third-party dependency**: Sparkle (used only for updates).

## Build & install

```bash
cd mactools/bettermodifiers
./scripts/build-install-local.sh
```

This will:

1. `swift package clean` + `swift build -c release` (resolves Sparkle on first run).
2. Wrap the binary as `~/Applications/BetterModifiers.app` (`LSUIElement`, ad-hoc signed).
3. Embed `Sparkle.framework` under `Contents/Frameworks` and ad-hoc sign it.
4. Generate the icon from `assets/app-icon.svg` via `sips` + `iconutil`.
5. Remove any leftover `LayerKey.app` / `ModifierOverride.app` / `Better Modifiers.app`.
6. Open the installed app.

After first launch, grant **Accessibility** permission in System Settings → Privacy & Security → Accessibility. The menu bar icon will switch to "Active".

## Layout

```text
bettermodifiers/
  Package.swift
  scripts/build-install-local.sh
  assets/app-icon.svg
  Sources/
    BetterModifiersHID/             C bridge for IOKit Caps Lock remap (bm_*)
    bettermodifiers/
      BetterModifiersMain.swift     @main SwiftUI App + Window Scene; @NSApplicationDelegateAdaptor
      AppDelegate.swift             ties engine + settings + UI together; closes-to-tray
      AppViewModel.swift            observable bridge for SwiftUI views
      MenuBarController.swift       NSStatusItem (with setVisible)
      Engine/
        EventTapController.swift    CGEventTap, Tab/Caps state machine, rule + hyper lookup
        CapsLockController.swift    Caps Lock remap + state via the C bridge
        KeyCodes.swift              virtual key constants and labels
      Model/
        Trigger.swift               .tab | .capsLock
        ModifierMask.swift          Cmd/Opt/Ctrl/Shift OptionSet
        Rule.swift                  Codable rule
        RulesStore.swift            JSON store in Application Support, O(1) lookup cache
        AppSettings.swift           hyper config + appearance + hide menu bar icon
        SettingsStore.swift         JSON store, debounced atomic save
      System/
        PermissionsController.swift Accessibility status + prompt
        LaunchAtLoginController.swift SMAppService.mainApp wrapper
        LegacyMigrator.swift        one-shot LayerKey/ModifierOverride/Better Modifiers cleanup
        UpdateController.swift      Sparkle SPUStandardUpdaterController wrapper
      UI/
        MainWindow.swift            NavigationSplitView (Modifier Mode / Rules / General / Appearance / About) with a single custom sidebar toggle in the leading toolbar slot
        SidebarVisibility.swift     ObservableObject driving NavigationSplitViewVisibility (animated)
        ModifierModeView.swift      per-trigger Modifier Mode config card
        RulesView.swift             per-trigger cards, banner when Modifier Mode is active
        KeyRecorderView.swift       NSEvent local monitor based recorder (key only)
        GeneralView.swift           enable + launch-at-login + accessibility + troubleshooting
        AppearanceView.swift        theme picker + hide menu bar icon
        AboutView.swift             version + Sparkle Updates row
        Components/
          InlineRuleRow.swift       inline-editable rule row; chip cluster has fixed intrinsic width and is centered between toggle and trash via flexible Spacers
          KeyChip.swift             small reusable chips
          ModifierTogglesView.swift ⌃⌥⇧⌘ chip toggles
          PageHeader.swift          title + subtitle for every page
```

State is persisted to `~/Library/Application Support/BetterModifiers/`:

- `rules.json` – your rules (atomic, debounced writes).
- `settings.json` – hyper config, appearance, hide menu bar icon.

Sparkle's auto-check preference lives in `UserDefaults` (managed by Sparkle itself).

## Default rules

A fresh install seeds `Tab + 0..9 → Option + 0..9` so it's a drop-in replacement for the LayerKey MVP. Edit, add, or delete rules from the **Rules** tab.

## Releasing (Sparkle)

1. Run Sparkle's `bin/generate_keys` once. Store the private key in the maintainer keychain. Replace `SUPublicEDKey` in `scripts/build-install-local.sh` with the public key.
2. For each release:
  - Bump `CFBundleShortVersionString` / `CFBundleVersion` in the Info.plist heredoc.
  - Run `./scripts/build-install-local.sh`.
  - Zip `~/Applications/BetterModifiers.app` → `BetterModifiers-vX.Y.Z.zip`.
  - `bin/sign_update BetterModifiers-vX.Y.Z.zip` to get the EdDSA signature.
  - Attach the zip to a GitHub release tagged `bettermodifiers-vX.Y.Z`.
  - Append a new `<item>` to `appcast.xml` (suggested host: `gh-pages` branch under `bettermodifiers/appcast.xml`, matching `SUFeedURL`).

Until `SUPublicEDKey` is filled in with a real key, Sparkle is wired but will refuse to install any update, so it's safe to ship.

## Notes

- The Caps Lock layer works by remapping Caps Lock to F18 at the HID level while the app runs, so you can still use Caps Lock as a normal toggle (we restore that behavior on key-up). When the app quits, the OS re-reads the user keyboard map and Caps Lock returns to default.
- When **Hyper Key** is enabled for a trigger, all per-rule mappings for that trigger are paused; the Rules page surfaces a banner.
- macOS Login Items UI may not always show ad-hoc-signed apps; the in-app **Launch at Login** toggle still works via `SMAppService.mainApp`.
- If you hide the menu bar icon, double-click `BetterModifiers.app` in Finder to reopen the window.
- `rules.json` and `settings.json` are portable; you can hand-edit them while the app is closed.

## Agent docs

See `.agent/structure.md` and `.agent/progress.md` for design and milestone tracking.