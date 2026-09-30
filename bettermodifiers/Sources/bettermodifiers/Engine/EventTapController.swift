import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import os

@MainActor
final class EventTapController {
    enum Status: Equatable {
        case inactive
        case running
        case missingPermissions
        case failedToCreateTap
        case tapNotReceiving

        var displayText: String {
            switch self {
            case .inactive: return "Disabled"
            case .running: return "Active"
            case .missingPermissions: return "Accessibility required"
            case .failedToCreateTap: return "Failed to start event tap"
            case .tapNotReceiving: return "Accessibility revoked - re-toggle in System Settings"
            }
        }
    }

    private struct TabState {
        var isPressed = false
        var forwardedTabDown = false
        var usedAsLayer = false
        var consumedInputKeys: Set<UInt16> = []
        /// When non-nil, the Tab layer was armed for a `requiresTab` custom
        /// combo (e.g. `Tab + ⌘`). The mask is recorded at arm time and used
        /// to skip the built-in dispatch path entirely. `Tab + key` chord
        /// fallback is suppressed in this mode - the user opted into a
        /// modifier-qualified Tab combo, so we treat the Tab as an exclusive
        /// layer trigger rather than a printable key.
        var armedForCustomMask: ModifierMask?
    }

    private struct CapsLockLayerState {
        var isPressed = false
        var usedAsLayer = false
        var originalCapsLockState = false
        var consumedInputKeys: Set<UInt16> = []
    }

    /// State machine for the Shift+Space layer trigger. Always armed when Space goes
    /// down, but the original Space key-down is *forwarded* whenever Shift was not yet
    /// held. That keeps plain typing - including hold-to-repeat - completely untouched.
    /// If Shift then comes down while Space is still held, we retroactively delete the
    /// space we forwarded (via a synthetic Backspace) and slide into layer mode, mimicking
    /// the standard AutoHotkey trick. On Space release: a forwarded space pairs with a
    /// forwarded space-up; an unforwarded one falls back to a synthetic `Shift+Space`
    /// chord so apps that map that chord still see it.
    private struct ShiftSpaceState {
        var isPressed = false
        /// True when we let the original Space key-down pass through to apps. The matching
        /// key-up MUST also be forwarded so the OS doesn't think Space is stuck.
        var forwardedSpaceDown = false
        var usedAsLayer = false
        var consumedInputKeys: Set<UInt16> = []
        /// True when the layer was armed via the built-in `Shift+Space` path (Shift
        /// held alone). Drives the on-release fallback chord: only the built-in path
        /// emits `Shift+Space` if no third key was pressed, since custom Space combos
        /// (e.g. `Space+Cmd`) would otherwise fire system shortcuts the user
        /// explicitly chose to override.
        var armedForBuiltIn = false
    }

    /// Tracks an in-flight first key of a 2-key sequence rule. Set when the user
    /// presses a layer key that matches the prefix of at least one 2-key rule;
    /// cleared on the second key, on layer release, or on the timeout firing.
    private struct PendingSequence {
        let trigger: Trigger
        let firstKey: UInt16
        /// 1-key rule to fire on timeout, if one exists for the same prefix.
        let fallback: Rule?
        /// Cmd/Ctrl/Opt held when the first key arrived (only meaningful for `.shiftSpace`).
        let extraFlags: CGEventFlags
        var deadline: DispatchWorkItem?
    }

    /// How long to wait for the second key of a sequence rule before firing the
    /// fallback (or swallowing if no fallback). Tuned for "feels instant when no
    /// sequence rule exists, comfortable double-tap window when one does."
    private let sequenceTimeoutMillis = 250

    private let rules: RulesStore
    private let settings: SettingsStore
    private let permissions: PermissionsController
    private let capsLockController: CapsLockController
    private let injectedEventMarker: Int64 = 0x4245544d4f44 // "BETMOD"

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tabState = TabState()
    private var capsLockState = CapsLockLayerState()
    private var shiftSpaceState = ShiftSpaceState()
    private var pending: PendingSequence?
    /// Input keys whose `keyDown` was swallowed by a custom-trigger rule. Their
    /// matching `keyUp` must also be swallowed so apps don't see a stray release
    /// of a key that, from their perspective, was never pressed.
    private var customConsumedKeys: Set<UInt16> = []
    /// Escape guard: uptime of the last swallowed single Escape, and whether the
    /// current Escape press was swallowed (its keyUp and repeats must be too).
    private var lastGuardedEscapeNanos: UInt64?
    private var swallowedEscapeDown = false
    /// True while macOS secure event input is active (password fields, some auth dialogs).
    /// HID Caps→F18 remap is paused so secure fields see real Caps Lock events and LED state.
    private(set) var secureInputActive = false
    /// Polls secure input off the hot path. While it's on, macOS stops delivering
    /// key events to the tap, so an event-driven check can miss the transition.
    private var secureInputTimer: Timer?
    private let eventSource = CGEventSource(stateID: .hidSystemState)
    private let log = Logger(subsystem: "dev.tahaelghabi.BetterModifiers", category: "engine")
    private var receivedAnyEvent = false
    private var loggedFirstEvent = false
    private var healthCheckGeneration = 0

    private(set) var isEnabled = true

    var onStatusChange: ((Status) -> Void)?
    /// Called on the main actor whenever a rule (or modifier-mode mapping) actually fires.
    /// Used by the UI to surface a "Last triggered: X" diagnostic so the user can confirm
    /// the engine is alive without having to read the system log.
    var onRuleFired: ((FiredEvent) -> Void)?

    /// Whether a fired key came from a per-key rule or from Modifier Mode.
    enum FireSource: Equatable {
        case rule
        case modifierMode
    }

    struct FiredEvent {
        let trigger: Trigger
        let inputKeys: [UInt16]
        let modifiers: ModifierMask
        let outputKey: UInt16
        let source: FireSource
    }

    private(set) var status: Status = .inactive {
        didSet {
            guard status != oldValue else { return }
            NSLog("[BetterModifiers] tap status: %@", String(describing: status))
            onStatusChange?(status)
        }
    }

    init(
        rules: RulesStore,
        settings: SettingsStore,
        permissions: PermissionsController,
        capsLockController: CapsLockController
    ) {
        self.rules = rules
        self.settings = settings
        self.permissions = permissions
        self.capsLockController = capsLockController
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        refresh()
    }

    func refresh() {
        stop()

        guard isEnabled else {
            status = .inactive
            return
        }

        guard permissions.hasAccessibilityPermission else {
            status = .missingPermissions
            return
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
            return controller.handleEvent(proxy: proxy, type: type, event: event)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            status = .failedToCreateTap
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.eventTap = eventTap
        self.runLoopSource = source
        resetLayerState()

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        secureInputActive = IsSecureEventInputEnabled()
        syncCapsRemapForCurrentContext()
        startSecureInputPolling()
        receivedAnyEvent = false
        loggedFirstEvent = false
        status = .running
        NSLog("[BetterModifiers] tap created OK (cgSessionEventTap, headInsertEventTap). Waiting for first event...")

        // After ad-hoc rebuilds, AXIsProcessTrusted may still return true while TCC silently
        // ignores us. If we don't see a single event in 30 s, log a warning so support
        // troubleshooting is easier - but DO NOT change the visible status. The status
        // only flips back to a known-bad state when the user manually restarts the engine
        // and the next 30 s window also stays empty. Receiving any event clears the flag.
        healthCheckGeneration &+= 1
        let token = healthCheckGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
            guard let self, self.healthCheckGeneration == token, !self.receivedAnyEvent else { return }
            NSLog("[BetterModifiers] tap created but no events received in 30s - TCC may have silently revoked access")
        }
    }

    func stop() {
        secureInputTimer?.invalidate()
        secureInputTimer = nil
        capsLockController.syncRemap(enabled: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            // Without this the WindowServer keeps the disabled tap registered,
            // so every restart leaked one.
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
        runLoopSource = nil
        resetLayerState()
    }

    /// Rules and settings are read live on every event, so edits only need to
    /// drop an in-flight sequence that may point at a rule that just changed.
    func configurationDidChange() {
        clearPending()
    }

    private func resetLayerState() {
        tabState = TabState()
        capsLockState = CapsLockLayerState()
        shiftSpaceState = ShiftSpaceState()
        customConsumedKeys = []
        lastGuardedEscapeNanos = nil
        swallowedEscapeDown = false
        clearPending()
    }

    /// Plain Escape with no layer held, in one of the guarded apps.
    private func shouldGuardEscape(event: CGEvent) -> Bool {
        let config = settings.settings.escapeGuard
        guard config.isEnabled,
              !tabState.isPressed, !capsLockState.isPressed, !shiftSpaceState.isPressed,
              event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
              let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        else { return false }
        return config.bundleIDs.contains(bundleID)
    }

    /// First tap is swallowed; a second tap within the window goes through as one Escape.
    private func handleGuardedEscapeDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return swallowedEscapeDown ? nil : Unmanaged.passUnretained(event)
        }
        let now = DispatchTime.now().uptimeNanoseconds
        let window = UInt64(settings.settings.escapeGuard.windowMillis) * 1_000_000
        if let last = lastGuardedEscapeNanos, now - last <= window {
            lastGuardedEscapeNanos = nil
            swallowedEscapeDown = false
            return Unmanaged.passUnretained(event)
        }
        lastGuardedEscapeNanos = now
        swallowedEscapeDown = true
        return nil
    }

    private func handleEvent(
        proxy _: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Key-ups may have been dropped while disabled; start clean so a
            // layer key can't stay stuck "held".
            resetLayerState()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        receivedAnyEvent = true
        if !loggedFirstEvent {
            loggedFirstEvent = true
            let kc = event.getIntegerValueField(.keyboardEventKeycode)
            NSLog("[BetterModifiers] first event received: type=%d keyCode=%lld - tap is alive", type.rawValue, kc)
        }
        if status == .tapNotReceiving {
            status = .running
        }

        if event.getIntegerValueField(.eventSourceUserData) == injectedEventMarker {
            return Unmanaged.passUnretained(event)
        }

        guard isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))

        // Self-heal external keyboards: if we see a raw Caps Lock event (keycode 57)
        // it means the HID-level Caps->F18 mapping didn't stick to this device (typical
        // after hot-plugging an external keyboard - Keychron, etc - that re-enumerates
        // after our initial mapping pass). Re-apply the mapping; the next press will be
        // delivered as F18 and our normal layer logic will pick it up.
        if keyCode == KeyCodes.capsLock {
            if secureInputActive {
                return Unmanaged.passUnretained(event)
            }
            capsLockController.syncRemap(enabled: true)
        }

        switch type {
        case .keyDown: return handleKeyDown(event: event, keyCode: keyCode)
        case .keyUp:   return handleKeyUp(event: event, keyCode: keyCode)
        case .flagsChanged:
            handleFlagsChanged(event: event)
            return Unmanaged.passUnretained(event)
        default: return Unmanaged.passUnretained(event)
        }
    }

    /// Watches modifier transitions while Space is forwarded and a Space-required
    /// layer is in flight. The AHK-style trick (post a synthetic Backspace to undo
    /// the inserted space, slide into layer mode) is intentionally limited to the
    /// built-in `Shift+Space` path. Custom Space combos like `Space+Cmd` are NOT
    /// upgraded retro-actively because their natural fallback (`Cmd+Space` =
    /// Spotlight) is too disruptive to silently swallow if the user happens to
    /// release without typing a layer key. For custom Space combos, the user must
    /// press the modifier BEFORE Space.
    private func handleFlagsChanged(event: CGEvent) {
        guard shiftSpaceState.isPressed, shiftSpaceState.forwardedSpaceDown else { return }
        let shiftHeld = event.flags.contains(.maskShift)
        guard shiftHeld, !hasNonShiftUserModifiers(event.flags) else { return }
        emitKeyEventPair(keyCode: KeyCodes.delete, flags: [])
        shiftSpaceState.forwardedSpaceDown = false
        shiftSpaceState.armedForBuiltIn = true
    }

    private func handleKeyDown(event: CGEvent, keyCode: UInt16) -> Unmanaged<CGEvent>? {
        if secureInputActive {
            return Unmanaged.passUnretained(event)
        }

        if keyCode == KeyCodes.escape, shouldGuardEscape(event: event) {
            return handleGuardedEscapeDown(event: event)
        }

        if keyCode == KeyCodes.f18 {
            capsLockState.isPressed = true
            capsLockState.usedAsLayer = false
            capsLockState.originalCapsLockState = capsLockController.currentCapsLockState()
            capsLockState.consumedInputKeys = []
            return nil
        }

        if keyCode == KeyCodes.tab {
            if isPlainTabLayerTrigger(event: event) {
                tabState.isPressed = true
                tabState.forwardedTabDown = false
                tabState.usedAsLayer = false
                tabState.consumedInputKeys = []
                tabState.armedForCustomMask = nil
                return nil
            }
            // Modifiers held: arm only when the held mask matches a Tab-required
            // custom trigger. Otherwise pass Tab through so e.g. Cmd+Tab
            // (system app switcher) keeps working unchanged.
            if matchesRequiresTabCustom(event: event) {
                tabState.isPressed = true
                tabState.forwardedTabDown = false
                tabState.usedAsLayer = false
                tabState.consumedInputKeys = []
                tabState.armedForCustomMask = ModifierMask(eventFlags: event.flags)
                return nil
            }
            // Pass Tab through (system shortcut, like Cmd+Tab).
        }

        // Space arming. Always arm the state machine on the first Space-down so we can
        // upgrade into layer mode if Shift comes in later, BUT forward the original
        // Space-down whenever no qualifier was already held - so plain typing,
        // hold-to-repeat, Cmd+Space (Spotlight) and friends are completely undisturbed.
        // Custom Space-required triggers are checked on top of the built-in
        // Shift+Space path: if the held modifier mask matches one, we arm without
        // forwarding (so the modifier MUST be pressed before Space).
        if keyCode == KeyCodes.space {
            if !shiftSpaceState.isPressed {
                shiftSpaceState.isPressed = true
                shiftSpaceState.usedAsLayer = false
                shiftSpaceState.consumedInputKeys = []
                shiftSpaceState.armedForBuiltIn = false
                if isShiftSpaceLayerTrigger(event: event) {
                    shiftSpaceState.forwardedSpaceDown = false
                    shiftSpaceState.armedForBuiltIn = true
                    return nil
                }
                if matchesRequiresSpaceCustom(event: event) {
                    shiftSpaceState.forwardedSpaceDown = false
                    return nil
                }
                shiftSpaceState.forwardedSpaceDown = true
                return Unmanaged.passUnretained(event)
            }
            // Subsequent Space key-down for the same physical hold (auto-repeat). If we
            // forwarded the original press, keep forwarding so hold-to-repeat behaves
            // normally; otherwise we're in layer-pre-fire mode and should swallow.
            return shiftSpaceState.forwardedSpaceDown
                ? Unmanaged.passUnretained(event)
                : nil
        }

        if shiftSpaceState.isPressed {
            // Custom Space-required triggers come first - they can match any held
            // modifier combination (or with Caps Lock), unlike the built-in path
            // which is restricted to Shift held alone.
            if let ct = matchingCustomTrigger(flags: event.flags, tab: false, space: true),
               case .consumed(let consumedKeys) = dispatchLayerKey(
                   trigger: .custom(ct.id), keyCode: keyCode, event: event, extraFlags: []
               ) {
                shiftSpaceState.usedAsLayer = true
                shiftSpaceState.consumedInputKeys.formUnion(consumedKeys)
                if capsLockState.isPressed { capsLockState.usedAsLayer = true }
                return nil
            }

            if event.flags.contains(.maskShift) {
                // Built-in Shift+Space dispatch. Cmd / Ctrl / Opt held alongside
                // ride through and compose with the rule's output flags.
                let extraFlags = composableExtraFlags(event.flags)
                if case .consumed(let consumedKeys) = dispatchLayerKey(
                    trigger: .shiftSpace, keyCode: keyCode, event: event, extraFlags: extraFlags
                ) {
                    shiftSpaceState.usedAsLayer = true
                    shiftSpaceState.consumedInputKeys.formUnion(consumedKeys)
                    return nil
                }
                // Miss: fall through so the third key types normally. We deliberately do
                // NOT mark usedAsLayer here, so on Space-up we still emit the fallback
                // Shift+Space chord the user implicitly intended.
            }
        }

        if capsLockState.isPressed {
            if !hasAnyUserModifiers(event.flags),
               case .consumed(let consumedKeys) = dispatchLayerKey(
                   trigger: .capsLock, keyCode: keyCode, event: event, extraFlags: []
               ) {
                capsLockState.usedAsLayer = true
                capsLockState.consumedInputKeys.formUnion(consumedKeys)
                return nil
            }

            capsLockState.usedAsLayer = true
        }

        if tabState.isPressed {
            if tabState.armedForCustomMask != nil {
                // Tab was armed for a `requiresTab` custom combo. Match the
                // currently-held mask back to the trigger and dispatch via the
                // custom path. On miss, fall through and let the key type
                // normally - we never forwarded Tab, so the user's app sees
                // just the key (with whatever modifiers are held).
                if let ct = matchingCustomTrigger(flags: event.flags, tab: true, space: false),
                   case .consumed(let consumedKeys) = dispatchLayerKey(
                   trigger: .custom(ct.id), keyCode: keyCode, event: event, extraFlags: []
               ) {
                    tabState.usedAsLayer = true
                    tabState.consumedInputKeys.formUnion(consumedKeys)
                    if capsLockState.isPressed { capsLockState.usedAsLayer = true }
                    return nil
                }
                // Custom miss: don't forward Tab, just let the key pass through.
            } else {
                if !hasAnyUserModifiers(event.flags),
                   case .consumed(let consumedKeys) = dispatchLayerKey(
                       trigger: .tab, keyCode: keyCode, event: event, extraFlags: []
                   ) {
                    tabState.usedAsLayer = true
                    tabState.consumedInputKeys.formUnion(consumedKeys)
                    return nil
                }

                if !tabState.forwardedTabDown {
                    emitSingleKeyEvent(keyCode: KeyCodes.tab, flags: [], keyDown: true)
                    tabState.forwardedTabDown = true
                }
            }
        }

        // Custom modifier-combo triggers. Skipped when Tab or Shift+Space is
        // armed (those are full state machines that own the next keystroke),
        // but Caps Lock state is treated as a *combo qualifier* rather than an
        // exclusive layer - that lets the user build `Caps + ⌥` combos that
        // coexist with regular Caps-rule rows. If a Caps-required custom rule
        // fires we mark `usedAsLayer = true` so releasing Caps doesn't toggle
        // the system Caps Lock state.
        let exclusiveLayerActive = tabState.isPressed || shiftSpaceState.isPressed
        if !exclusiveLayerActive,
           let ct = matchingCustomTrigger(flags: event.flags, tab: false, space: false),
           case .consumed(let keys) = dispatchLayerKey(
               trigger: .custom(ct.id), keyCode: keyCode, event: event, extraFlags: []
           ) {
            customConsumedKeys.formUnion(keys)
            if capsLockState.isPressed { capsLockState.usedAsLayer = true }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    /// The custom trigger whose qualifiers exactly match what's held right now.
    /// Tab / Space must match too, so a `Space + ⌘` trigger never fires on plain ⌘.
    private func matchingCustomTrigger(flags: CGEventFlags, tab: Bool, space: Bool) -> CustomTrigger? {
        let mask = ModifierMask(eventFlags: flags)
        let capsHeld = capsLockState.isPressed
        return settings.settings.customTriggers.first { ct in
            ct.requiresTab == tab
                && ct.requiresSpace == space
                && ct.requiresCapsLock == capsHeld
                && ct.modifiers == mask
                && !ct.isEmpty
        }
    }

    /// Modifier Mode first, then per-key rules. Same for built-in and custom
    /// triggers. While Modifier Mode is on, every key fires with the mode's
    /// modifiers except keys in `exceptions`, which either go through the
    /// rules (`useRules`) or miss so they type normally (`typeNormally`).
    private func dispatchLayerKey(
        trigger: Trigger,
        keyCode: UInt16,
        event: CGEvent,
        extraFlags: CGEventFlags
    ) -> LayerResolveResult {
        let mode = settings.modeConfig(for: trigger)
        if mode.isEnabled {
            if !mode.exceptions.contains(keyCode) {
                // An excepted key may have left a sequence pending; resolve it first.
                if pending?.trigger == trigger { firePendingTimeout() }
                emitKeyEventPair(keyCode: keyCode, flags: mode.modifiers.eventFlags.union(extraFlags))
                fireDiagnostic(trigger: trigger, inputKeys: [keyCode], modifiers: mode.modifiers,
                               outputKey: keyCode, source: .modifierMode)
                return .consumed([keyCode])
            }
            if mode.exceptionBehavior == .typeNormally { return .miss }
        }
        return resolveLayerKey(trigger: trigger, keyCode: keyCode, event: event, extraFlags: extraFlags)
    }

    private func fireDiagnostic(
        trigger: Trigger,
        inputKeys: [UInt16],
        modifiers: ModifierMask,
        outputKey: UInt16,
        source: FireSource = .rule
    ) {
        // Logger, not NSLog: this runs on every fired key and NSLog is synchronous.
        log.debug("fired \(trigger.id, privacy: .public) -> \(modifiers.displaySymbols, privacy: .public)\(KeyCodes.label(for: outputKey), privacy: .public)")
        onRuleFired?(FiredEvent(trigger: trigger, inputKeys: inputKeys, modifiers: modifiers,
                                outputKey: outputKey, source: source))
    }

    private enum LayerResolveResult {
        /// The key was consumed by the rule/sequence engine. Caller must add the
        /// listed keys to its layer state's `consumedInputKeys` (so the matching
        /// keyUps are also swallowed) and mark the layer as used.
        case consumed([UInt16])
        /// No single-key or sequence rule matched. Caller continues with its
        /// existing miss behavior.
        case miss
    }

    /// Sequence-aware first/second key dispatch. Handles three cases:
    ///   1. We're already pending a second key for this trigger -> try to fire a
    ///      2-key rule; on no match, fire the fallback (if any) and re-dispatch
    ///      the current key as a fresh first key.
    ///   2. Fresh first key with no sequence prefix -> fire the 1-key rule
    ///      immediately (no waiting).
    ///   3. Fresh first key that prefixes at least one 2-key rule -> arm a
    ///      `pending` state with a timeout. Caller swallows the keystroke now.
    private func resolveLayerKey(
        trigger: Trigger,
        keyCode: UInt16,
        event: CGEvent,
        extraFlags: CGEventFlags
    ) -> LayerResolveResult {
        guard !settings.isPaused(trigger) else { return .miss }
        var consumed: [UInt16] = []

        if let p = pending, p.trigger == trigger {
            // While pending, suppress auto-repeats of the first key entirely - hold-to-
            // repeat is a single physical press, not a deliberate double-tap.
            let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if isAutorepeat && keyCode == p.firstKey {
                return .consumed([keyCode])
            }

            if let twoKey = rules.sequenceRule(trigger: trigger, firstKey: p.firstKey, secondKey: keyCode) {
                let outFlags = twoKey.outputModifiers.eventFlags
                    .union(p.extraFlags)
                    .union(extraFlags)
                emitKeyEventPair(keyCode: twoKey.outputKey, flags: outFlags)
                fireDiagnostic(trigger: trigger,
                               inputKeys: [p.firstKey, keyCode],
                               modifiers: twoKey.outputModifiers,
                               outputKey: twoKey.outputKey)
                clearPending()
                return .consumed([keyCode])
            }

            // 2-key miss. Fire fallback for the first key if defined, then
            // re-dispatch the current key as a fresh first key below.
            if let fb = p.fallback {
                let outFlags = fb.outputModifiers.eventFlags.union(p.extraFlags)
                emitKeyEventPair(keyCode: fb.outputKey, flags: outFlags)
                fireDiagnostic(trigger: trigger,
                               inputKeys: [p.firstKey],
                               modifiers: fb.outputModifiers,
                               outputKey: fb.outputKey)
            }
            clearPending()
        }

        switch rules.lookup(trigger: trigger, firstKey: keyCode) {
        case .singleKeyHit(let rule):
            let outFlags = rule.outputModifiers.eventFlags.union(extraFlags)
            emitKeyEventPair(keyCode: rule.outputKey, flags: outFlags)
            fireDiagnostic(trigger: trigger,
                           inputKeys: [keyCode],
                           modifiers: rule.outputModifiers,
                           outputKey: rule.outputKey)
            consumed.append(keyCode)
            return .consumed(consumed)
        case .ambiguous(let fallback):
            startPending(trigger: trigger, firstKey: keyCode, fallback: fallback, extraFlags: extraFlags)
            consumed.append(keyCode)
            return .consumed(consumed)
        case .miss:
            return consumed.isEmpty ? .miss : .consumed(consumed)
        }
    }

    private func startPending(
        trigger: Trigger,
        firstKey: UInt16,
        fallback: Rule?,
        extraFlags: CGEventFlags
    ) {
        clearPending()
        let work = DispatchWorkItem { [weak self] in
            self?.firePendingTimeout()
        }
        pending = PendingSequence(
            trigger: trigger,
            firstKey: firstKey,
            fallback: fallback,
            extraFlags: extraFlags,
            deadline: work
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(sequenceTimeoutMillis), execute: work)
    }

    private func firePendingTimeout() {
        guard let p = pending else { return }
        if let fb = p.fallback {
            let outFlags = fb.outputModifiers.eventFlags.union(p.extraFlags)
            emitKeyEventPair(keyCode: fb.outputKey, flags: outFlags)
            fireDiagnostic(trigger: p.trigger,
                           inputKeys: [p.firstKey],
                           modifiers: fb.outputModifiers,
                           outputKey: fb.outputKey)
        }
        // Cancel the deadline too: when resolved early (layer released), a stale
        // timer would otherwise fire on the next sequence and cut it short.
        clearPending()
    }

    private func clearPending() {
        pending?.deadline?.cancel()
        pending = nil
    }

    /// Called when a layer-trigger key is released. If a sequence is still
    /// pending for this trigger, resolve it as if the timeout fired (so the
    /// fallback 1-key rule still gets a chance to fire), then return.
    private func resolvePendingForLayerEnd(_ trigger: Trigger) {
        guard pending?.trigger == trigger else { return }
        firePendingTimeout()
    }

    private func handleKeyUp(event: CGEvent, keyCode: UInt16) -> Unmanaged<CGEvent>? {
        if secureInputActive {
            return Unmanaged.passUnretained(event)
        }

        if keyCode == KeyCodes.escape, swallowedEscapeDown {
            swallowedEscapeDown = false
            return nil
        }

        if keyCode == KeyCodes.f18, capsLockState.isPressed {
            resolvePendingForLayerEnd(.capsLock)
            if !capsLockState.usedAsLayer && pending == nil {
                let newState = !capsLockState.originalCapsLockState
                capsLockController.setCapsLockState(newState)
                postSyntheticCapsLockFlagsChanged(isEnabled: newState)
            }
            capsLockState = CapsLockLayerState()
            return nil
        }

        if keyCode == KeyCodes.tab, tabState.isPressed {
            if tabState.armedForCustomMask != nil {
                // Custom Tab combo: swallow the keyUp and don't emit any
                // fallback chord. The user explicitly asked us to consume
                // Tab+modifier so a tap-without-rule should be a no-op.
                tabState = TabState()
                return nil
            }
            let firedPending = pending?.trigger == .tab
            resolvePendingForLayerEnd(.tab)
            if tabState.forwardedTabDown {
                emitSingleKeyEvent(keyCode: KeyCodes.tab, flags: [], keyDown: false)
            } else if !tabState.usedAsLayer && !firedPending {
                emitKeyEventPair(keyCode: KeyCodes.tab, flags: [])
            }
            tabState = TabState()
            return nil
        }

        if keyCode == KeyCodes.space, shiftSpaceState.isPressed {
            // Resolve any in-flight pending sequence for either built-in or custom
            // Space-required triggers before tearing the state down.
            let firedPending: Bool = {
                guard let p = pending else { return false }
                if p.trigger == .shiftSpace { return true }
                if case .custom(let id) = p.trigger {
                    return settings.customTrigger(id: id)?.requiresSpace == true
                }
                return false
            }()
            if firedPending {
                firePendingTimeout()
            }
            let forwarded = shiftSpaceState.forwardedSpaceDown
            let wasLayer = shiftSpaceState.usedAsLayer || firedPending
            let armedForBuiltIn = shiftSpaceState.armedForBuiltIn
            shiftSpaceState = ShiftSpaceState()
            if forwarded {
                // The original Space-down was real; pair it with a real Space-up.
                return Unmanaged.passUnretained(event)
            }
            if !wasLayer && armedForBuiltIn {
                // Built-in Shift+Space chord typed without a layer key. Emit the
                // fallback so apps that bind Shift+Space still see it. Custom
                // Space-required triggers don't get a fallback - their natural
                // fallback would be a system shortcut (Cmd+Space etc.) the user
                // explicitly chose to override.
                emitKeyEventPair(keyCode: KeyCodes.space, flags: [.maskShift])
            }
            return nil
        }

        if tabState.consumedInputKeys.contains(keyCode) {
            tabState.consumedInputKeys.remove(keyCode)
            return nil
        }

        if capsLockState.consumedInputKeys.contains(keyCode) {
            capsLockState.consumedInputKeys.remove(keyCode)
            return nil
        }

        if shiftSpaceState.consumedInputKeys.contains(keyCode) {
            shiftSpaceState.consumedInputKeys.remove(keyCode)
            return nil
        }

        if customConsumedKeys.contains(keyCode) {
            customConsumedKeys.remove(keyCode)
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func emitKeyEventPair(keyCode: UInt16, flags: CGEventFlags) {
        emitSingleKeyEvent(keyCode: keyCode, flags: flags, keyDown: true)
        emitSingleKeyEvent(keyCode: keyCode, flags: flags, keyDown: false)
    }

    private func emitSingleKeyEvent(keyCode: UInt16, flags: CGEventFlags, keyDown: Bool) {
        let virtualKey = CGKeyCode(keyCode)
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: virtualKey, keyDown: keyDown) else {
            return
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: injectedEventMarker)
        event.post(tap: .cghidEventTap)
    }

    /// After toggling Caps Lock via IOKit, web views (Chromium/WebKit) and especially password
    /// fields only refresh their caps-lock indicator when they see a real Quartz `flagsChanged`
    /// event with `alphaShift`. The keyboard-event init below produces a `keyDown`/`keyUp`
    /// event by default, which most apps tolerate but browser password fields ignore — so we
    /// override `event.type` to `.flagsChanged` after construction.
    private func postSyntheticCapsLockFlagsChanged(isEnabled: Bool) {
        let virtualKey = CGKeyCode(KeyCodes.capsLock)
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: virtualKey, keyDown: true) else {
            return
        }
        event.type = .flagsChanged
        event.flags = isEnabled ? .maskAlphaShift : []
        event.setIntegerValueField(.eventSourceUserData, value: injectedEventMarker)
        event.post(tap: .cghidEventTap)
    }

    private func startSecureInputPolling() {
        secureInputTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateSecureInputStateIfNeeded() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        secureInputTimer = timer
    }

    /// macOS enables secure event input for password fields and some system auth UI.
    /// While active, pause the Caps→F18 HID remap and pass keyboard events through so
    /// Caps Lock LED / case behave normally.
    private func updateSecureInputStateIfNeeded() {
        let now = IsSecureEventInputEnabled()
        guard now != secureInputActive else { return }
        secureInputActive = now
        defer { onStatusChange?(status) }
        if now {
            NSLog("[BetterModifiers] secure input active — pausing Caps Lock HID remap")
            // Key-ups stop arriving while secure input is on, so drop any held layer.
            resetLayerState()
            capsLockController.syncRemap(enabled: false)
        } else {
            NSLog("[BetterModifiers] secure input inactive — restoring Caps Lock HID remap")
            syncCapsRemapForCurrentContext()
            postSyntheticCapsLockFlagsChanged(isEnabled: capsLockController.currentCapsLockState())
        }
    }

    private func syncCapsRemapForCurrentContext() {
        let shouldRemap = isEnabled && status == .running && !secureInputActive
        capsLockController.syncRemap(enabled: shouldRemap)
    }

    private func isPlainTabLayerTrigger(event: CGEvent) -> Bool {
        !hasAnyUserModifiers(event.flags)
    }

    /// Shift+Space arms the layer iff Shift is currently held AND no other user
    /// modifier (Cmd / Ctrl / Opt) is held. That keeps Cmd+Shift+Space, Ctrl+Space,
    /// etc. as their normal system shortcuts.
    private func isShiftSpaceLayerTrigger(event: CGEvent) -> Bool {
        event.flags.contains(.maskShift) && !hasNonShiftUserModifiers(event.flags)
    }

    /// True when the held modifier mask (and Caps Lock state) exactly matches a
    /// user-defined `requiresTab` custom trigger. Determines whether a Tab-down
    /// with modifiers held should be intercepted (arm a custom Tab layer) or
    /// passed through (so e.g. Cmd+Tab keeps switching apps).
    private func matchesRequiresTabCustom(event: CGEvent) -> Bool {
        matchingCustomTrigger(flags: event.flags, tab: true, space: false) != nil
    }

    /// True when the held modifier mask (and Caps Lock state) exactly matches a
    /// user-defined `requiresSpace` custom trigger. Used at Space-down arming time.
    private func matchesRequiresSpaceCustom(event: CGEvent) -> Bool {
        matchingCustomTrigger(flags: event.flags, tab: false, space: true) != nil
    }

    private static let nonShiftUserFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
    // Intentionally excludes .maskSecondaryFn (Fn) and .maskAlphaShift (Caps Lock LED state).
    // The OS sets Fn for arrow keys and some function-row aliases, which would otherwise
    // suppress the Tab/Caps layer for no good reason.
    private static let userFlags: CGEventFlags = nonShiftUserFlags.union(.maskShift)

    /// Cmd / Ctrl / Opt currently held - the modifiers that may be layered on top of
    /// Shift+Space and combined with the rule's output flags. Shift is excluded
    /// because it's the trigger qualifier, not an extra modifier.
    private func composableExtraFlags(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(Self.nonShiftUserFlags)
    }

    private func hasNonShiftUserModifiers(_ flags: CGEventFlags) -> Bool {
        !flags.intersection(Self.nonShiftUserFlags).isEmpty
    }

    private func hasAnyUserModifiers(_ flags: CGEventFlags) -> Bool {
        !flags.intersection(Self.userFlags).isEmpty
    }
}
