# BetterModifiers structure

Durable design notes. Update when architecture changes.

## Goals

- Native macOS menu bar app (LSUIElement) with a SwiftUI configuration window.
- Let the user define rules: `Trigger(Tab|CapsLock) + InputKey -> [Cmd/Opt/Ctrl/Shift]* + OutputKey`.
- Provide a Hyper Key mode that turns Tab or Caps Lock into a fixed modifier combo for any other key.
- Replace the earlier `layerkey` MVP while keeping its proven engine.
- Keep dependencies minimal: only Sparkle (for updates) is third-party.

## Top-level components

```
NSApplication
  └─ AppDelegate (@MainActor)
      ├─ PermissionsController     accessibility status + prompt
      ├─ CapsLockController        toggles HID Caps Lock remap (Caps -> F18)
      ├─ LaunchAtLoginController   SMAppService.mainApp wrapper
      ├─ RulesStore (Observable)   loads/saves rules.json, lookup cache
      ├─ SettingsStore (Observable) loads/saves settings.json (modifier mode, theme)
      ├─ EventTapController        CGEventTap + Tab/Caps state machine, hyper bypass
      ├─ UpdateController          Sparkle SPUStandardUpdaterController wrapper
      ├─ AppViewModel              published bridge for SwiftUI
      ├─ MenuBarController         NSStatusItem + NSMenu (Status / Enable / Open / Launch at Login / Accessibility / Restart Engine / Quit)
      └─ window: NSWindow          lazy NSHostingController(MainWindow)
```

`SettingsStore.onChange` debounces and triggers (a) `engine.refresh()` and (b) `applyAppearance()`. `applicationShouldHandleReopen` reopens the main window when the dock/Finder relaunches the app.

## Event tap flow

1. User presses a key. The CGEventTap callback bounces into `EventTapController.handleEvent`.
2. Synthetic events we posted are tagged with `eventSourceUserData = injectedEventMarker` and pass through unchanged.
3. `keyDown` for `Tab` (no other modifiers) starts a `tabState` "layer" without forwarding the Tab itself; `keyDown` for `F18` (the remapped Caps Lock) starts a `capsLockState` layer.
4. While a layer is active and the next key has no held modifiers, the engine first checks `SettingsStore.hyperConfig(for: trigger)`:
   - If hyper is enabled, emit `keyDown + keyUp` of the input key with `hyper.modifiers` and swallow the original. Per-rule lookup is skipped.
   - Otherwise look up `RulesStore.rule(for: trigger, inputKey:)` and emit `outputKey + outputModifiers` on a hit.
5. On `keyUp` of the trigger:
   - Tab: if we had to forward Tab early (because a non-rule key followed), send `Tab keyUp`. Otherwise, if the layer was never used, emit a normal `Tab` press so plain Tab still works.
   - F18 (Caps Lock): if the layer was never used, toggle the Caps Lock state via IOKit and post a synthetic `flagsChanged` with `maskAlphaShift` so browsers update their IME/UI immediately.
6. `keyUp` of input keys consumed during the layer is swallowed via per-state `consumedInputKeys` sets so the original digit/letter is never echoed.

`Cmd-Tab` and friends are preserved because we only enter the Tab layer when no user modifiers are held.

## Rule storage

`RulesStore` keeps the in-memory `[Rule]` and a `[(trigger, inputKey): Rule]` cache for O(1) hot-path lookups. Persistence is JSON at `~/Library/Application Support/BetterModifiers/rules.json` with an atomic, debounced write (~150 ms) to coalesce edits.

Default seed: `Tab + 0..9 -> Option + 0..9`.

Conflict policy: if two rules share `(trigger, inputKey)` the most-recently-written wins (cache rebuild order). The editor surfaces a warning when the user creates an overlap.

## Settings storage

`SettingsStore` mirrors `RulesStore` (JSON at `~/Library/Application Support/BetterModifiers/settings.json`, `@Sendable` debounced atomic write). `AppSettings`:

- `modifierMode: [Trigger: ModifierModeConfig]` (`isEnabled`, `modifiers`).
- `appearance: AppearanceMode` (system / light / dark).

Sparkle's auto-check preferences are intentionally not stored here; they live in `UserDefaults` under `SUEnableAutomaticChecks` / `SUAutomaticallyDownloadUpdates`, owned by Sparkle.

## UI

- `MainWindow` is a `NavigationSplitView` with `Modifier Mode → Rules → General → Appearance → About`. The title-bar sidebar-toggle is removed via `.toolbar(removing: .sidebarToggle)` (macOS 14.4+) so the sidebar is always visible. Detail panes are tinted with `Color(nsColor: .underPageBackgroundColor)` for a softer light theme.
- Each page starts with a `PageHeader` (title + subtitle) so the user always sees what the page is for.
- `ModifierModeView` renders one `GroupBox` card per trigger with a toggle, `ModifierTogglesView`, and a live preview chip row.
- `RulesView` is a `ScrollView` of two `GroupBox` cards (one per trigger). Each card lists `InlineRuleRow`s and ends with an "Add rule for X" button that appends a new rule pre-set to the first unused digit (`RulesStore.firstUnusedInputKey(for:)`) and auto-enters input recording.
- `InlineRuleRow` is the editor: enable switch, trigger chip, tappable input key chip, `CompactModifierTogglesView` (in-place ⌃⌥⇧⌘ toggles), tappable output key chip, big circular trash. Tapping a key chip starts an `NSEvent.addLocalMonitorForEvents(.keyDown)` recording session; the next non-modifier key commits via `RulesStore.update`. There is no editor sheet anymore (`RuleEditorView` was deleted).
- `KeyRecorderView` is still around for any future single-key picker needs but is unused by the current UI.
- `GeneralView` exposes the enable toggle, launch-at-login toggle, accessibility status, engine status text, and a "Restart Engine" button (calls `EventTapController.refresh`).
- `AppearanceView` exposes the System / Light / Dark theme picker.
- `AboutView` shows version info and the Sparkle Updates row (auto-check toggle, Check Now button, last-checked text + inline status when Sparkle is unconfigured).

The window is created lazily by `AppDelegate.openMainWindow()` and torn down on close (`isReleasedWhenClosed = false` + manual nilling) so the resident memory cost stays close to the menu bar baseline.

## Permissions and login item

- Accessibility: required for the event tap. `AppDelegate` calls `permissions.requestAccessibilityPermission()` on first launch when the trust bit is false (system prompt with a deep-link to System Settings). It then polls `AXIsProcessTrusted()` every 2 s and only restarts the tap when the value flips, so editing rules never causes a tap reset.
- Tap health check: after `CGEvent.tapCreate` succeeds, `EventTapController` schedules a 4 s deadline; if `handleEvent` has not fired even once it sets `status = .tapNotReceiving`, re-prompts for Accessibility, and surfaces the situation in the menu bar / `GeneralView`. This catches the common "ad-hoc rebuild silently invalidated TCC" failure mode. A "Restart Engine" command in the menu bar and `GeneralView` re-creates the tap on demand.
- Launch at login: `SMAppService.mainApp.register()`. Same approach as Spaceman; works even if the macOS Login Items UI doesn't show the entry for ad-hoc-signed apps.
- `LegacyMigrator` runs once (`UserDefaults` flag) to unregister/delete the old LayerKey/ModifierOverride/`Better Modifiers` artifacts.

## Updates (Sparkle 2)

- SwiftPM dependency: `https://github.com/sparkle-project/Sparkle` from 2.6.4 (resolved 2.9.x).
- `UpdateController` owns one `SPUStandardUpdaterController(startingUpdater: true, …)`. It exposes `automaticChecksEnabled` (proxied to `updater.automaticallyChecksForUpdates`), `lastCheckText`, and `checkForUpdates()`.
- About page reads/writes through that controller. Sparkle handles scheduling, EdDSA verification, and the standard "release notes / progress / install" UI.
- Build script embeds `Sparkle.framework` under `Contents/Frameworks` and ad-hoc signs the framework before re-signing the bundle.
- `Info.plist` keys (templated by the build script): `SUFeedURL`, `SUPublicEDKey` (placeholder until the maintainer generates one), `SUEnableAutomaticChecks`, `SUScheduledCheckInterval`, `SUAllowsAutomaticUpdates`.

## Build / install

`scripts/build-install-local.sh` does `swift package clean` + `swift build -c release`, builds the `BetterModifiers.app` bundle, embeds `Sparkle.framework`, generates the `.icns` from `assets/app-icon.svg`, removes legacy `LayerKey.app` / `ModifierOverride.app` / `Better Modifiers.app`, ad-hoc signs the framework + bundle, and opens the installed app.

The C target is `BetterModifiersHID` (functions `bm_*`, header guard `BETTER_MODIFIERS_HID_H`). SwiftPM platform requirement: `macOS 14` (so we can use `.toolbar(removing: .sidebarToggle)` from macOS 14.4 behind an `if #available` guard).

## Out of scope (parking lot)

- Per-app rule scoping
- Non-keystroke actions (launch app, run shell, open URL)
- Sequences / chord output
- Rule import/export and iCloud sync
- Onboarding wizard
- Custom monochrome menu bar icon (uses `keyboard` SF Symbol for now)
- Hosting the appcast and generating the Sparkle EdDSA key pair (documented but performed manually)
