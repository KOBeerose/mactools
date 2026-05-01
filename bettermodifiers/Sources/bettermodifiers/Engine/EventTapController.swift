import ApplicationServices
import Foundation

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
    private var receivedAnyEvent = false
    private var loggedFirstEvent = false
    private var healthCheckGeneration = 0

    private(set) var isEnabled = true

    var onStatusChange: ((Status) -> Void)?
    /// Called on the main actor whenever a rule (or modifier-mode mapping) actually fires.
    /// Used by the UI to surface a "Last triggered: X" diagnostic so the user can confirm
    /// the engine is alive without having to read the system log.
    var onRuleFired: ((Trigger, [UInt16], ModifierMask, UInt16) -> Void)?

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
        tabState = TabState()
        capsLockState = CapsLockLayerState()
        shiftSpaceState = ShiftSpaceState()
        customConsumedKeys = []
        clearPending()

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        capsLockController.syncRemap(enabled: true)
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
        capsLockController.syncRemap(enabled: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        tabState = TabState()
        capsLockState = CapsLockLayerState()
        shiftSpaceState = ShiftSpaceState()
        customConsumedKeys = []
        clearPending()
    }

    private func handleEvent(
        proxy _: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
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

        // Self-heal external keyboards: if we see a raw Caps Lock event (keycode 57)
        // it means the HID-level Caps->F18 mapping didn't stick to this device (typical
        // after hot-plugging an external keyboard - Keychron, etc - that re-enumerates
        // after our initial mapping pass). Re-apply the mapping; the next press will be
        // delivered as F18 and our normal layer logic will pick it up.
        if event.getIntegerValueField(.keyboardEventKeycode) == Int64(KeyCodes.capsLock) {
            capsLockController.syncRemap(enabled: true)
        }

        if event.getIntegerValueField(.eventSourceUserData) == injectedEventMarker {
            return Unmanaged.passUnretained(event)
        }

        guard isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .keyDown: return handleKeyDown(event: event, keyCode: keyCode)
        case .keyUp:   return handleKeyUp(event: event, keyCode: keyCode)
        case .flagsChanged:
            handleFlagsChanged(event: event)
            return Unmanaged.passUnretained(event)
        default: return Unmanaged.passUnretained(event)
        }
    }

    /// Watches modifier transitions while Shift+Space is in play. If the user already
    /// pressed Space (and we forwarded it) and then adds Shift cleanly (no Cmd / Ctrl /
    /// Opt), we post a synthetic Backspace to undo the inserted space and convert the
    /// in-flight chord into the layer trigger. Composing Cmd / Ctrl / Opt on top after
    /// the layer is armed is fine - those flags ride through to the rule's output.
    private func handleFlagsChanged(event: CGEvent) {
        guard shiftSpaceState.isPressed, shiftSpaceState.forwardedSpaceDown else { return }
        let shiftHeld = event.flags.contains(.maskShift)
        guard shiftHeld, !hasNonShiftUserModifiers(event.flags) else { return }
        emitKeyEventPair(keyCode: KeyCodes.delete, flags: [])
        shiftSpaceState.forwardedSpaceDown = false
    }

    private func handleKeyDown(event: CGEvent, keyCode: UInt16) -> Unmanaged<CGEvent>? {
        if keyCode == KeyCodes.f18 {
            capsLockState.isPressed = true
            capsLockState.usedAsLayer = false
            capsLockState.originalCapsLockState = capsLockController.currentCapsLockState()
            capsLockState.consumedInputKeys = []
            return nil
        }

        if keyCode == KeyCodes.tab, isPlainTabLayerTrigger(event: event) {
            tabState.isPressed = true
            tabState.forwardedTabDown = false
            tabState.usedAsLayer = false
            tabState.consumedInputKeys = []
            return nil
        }

        // Space arming. Always arm the state machine on the first Space-down so we can
        // upgrade into layer mode if Shift comes in later, BUT forward the original
        // Space-down whenever Shift wasn't already held - so plain typing, hold-to-
        // repeat, Cmd+Space (Spotlight) and friends are completely undisturbed.
        if keyCode == KeyCodes.space {
            if !shiftSpaceState.isPressed {
                shiftSpaceState.isPressed = true
                shiftSpaceState.usedAsLayer = false
                shiftSpaceState.consumedInputKeys = []
                if isShiftSpaceLayerTrigger(event: event) {
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

        if shiftSpaceState.isPressed, event.flags.contains(.maskShift) {
            // Shift is held (regardless of whether it came before or after Space) - this
            // is the layer dispatch path. Cmd / Ctrl / Opt held alongside ride through
            // and compose with the rule's output flags.
            let extraFlags = composableExtraFlags(event.flags)
            let mode = settings.modeConfig(for: .shiftSpace)
            if mode.isEnabled {
                shiftSpaceState.usedAsLayer = true
                shiftSpaceState.consumedInputKeys.insert(keyCode)
                emitKeyEventPair(keyCode: keyCode, flags: mode.modifiers.eventFlags.union(extraFlags))
                fireDiagnostic(trigger: .shiftSpace, inputKeys: [keyCode], modifiers: mode.modifiers, outputKey: keyCode)
                return nil
            }
            let result = resolveLayerKey(trigger: .shiftSpace, keyCode: keyCode, event: event, extraFlags: extraFlags)
            switch result {
            case .consumed(let consumedKeys):
                shiftSpaceState.usedAsLayer = true
                consumedKeys.forEach { shiftSpaceState.consumedInputKeys.insert($0) }
                return nil
            case .miss:
                // Fall through so the third key types normally. We deliberately do
                // NOT mark usedAsLayer here, so on Space-up we still emit the fallback
                // Shift+Space chord the user implicitly intended.
                break
            }
        }

        if capsLockState.isPressed {
            let mode = settings.modeConfig(for: .capsLock)
            if mode.isEnabled, !hasAnyUserModifiers(event.flags) {
                capsLockState.usedAsLayer = true
                capsLockState.consumedInputKeys.insert(keyCode)
                emitKeyEventPair(keyCode: keyCode, flags: mode.modifiers.eventFlags)
                fireDiagnostic(trigger: .capsLock, inputKeys: [keyCode], modifiers: mode.modifiers, outputKey: keyCode)
                return nil
            }
            if !mode.isEnabled, !hasAnyUserModifiers(event.flags) {
                let result = resolveLayerKey(trigger: .capsLock, keyCode: keyCode, event: event, extraFlags: [])
                switch result {
                case .consumed(let consumedKeys):
                    capsLockState.usedAsLayer = true
                    consumedKeys.forEach { capsLockState.consumedInputKeys.insert($0) }
                    return nil
                case .miss:
                    break
                }
            }

            capsLockState.usedAsLayer = true
        }

        if tabState.isPressed {
            let mode = settings.modeConfig(for: .tab)
            if mode.isEnabled, !hasAnyUserModifiers(event.flags) {
                tabState.usedAsLayer = true
                tabState.consumedInputKeys.insert(keyCode)
                emitKeyEventPair(keyCode: keyCode, flags: mode.modifiers.eventFlags)
                fireDiagnostic(trigger: .tab, inputKeys: [keyCode], modifiers: mode.modifiers, outputKey: keyCode)
                return nil
            }
            if !mode.isEnabled, !hasAnyUserModifiers(event.flags) {
                let result = resolveLayerKey(trigger: .tab, keyCode: keyCode, event: event, extraFlags: [])
                switch result {
                case .consumed(let consumedKeys):
                    tabState.usedAsLayer = true
                    consumedKeys.forEach { tabState.consumedInputKeys.insert($0) }
                    return nil
                case .miss:
                    break
                }
            }

            if !tabState.forwardedTabDown {
                emitSingleKeyEvent(keyCode: KeyCodes.tab, flags: [], keyDown: true)
                tabState.forwardedTabDown = true
            }
        }

        // Custom modifier-combo triggers. Skip entirely when a built-in layer is
        // active so e.g. Caps + Cmd + W doesn't accidentally fire a `⌘`-keyed
        // custom rule. Strict mask equality keeps `⌃⌥+anything` from intercepting
        // when the user has stacked extra modifiers (e.g. for a system shortcut).
        let isBuiltInLayerActive = tabState.isPressed || capsLockState.isPressed || shiftSpaceState.isPressed
        if !isBuiltInLayerActive {
            let heldMask = ModifierMask(eventFlags: event.flags)
            if !heldMask.isEmpty {
                for ct in settings.settings.customTriggers
                    where !ct.modifiers.isEmpty && ct.modifiers == heldMask
                {
                    let result = resolveLayerKey(
                        trigger: .custom(ct.id),
                        keyCode: keyCode,
                        event: event,
                        extraFlags: []
                    )
                    switch result {
                    case .consumed(let keys):
                        keys.forEach { customConsumedKeys.insert($0) }
                        return nil
                    case .miss:
                        break
                    }
                    break // at most one custom trigger can match a given mask
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func fireDiagnostic(trigger: Trigger, inputKeys: [UInt16], modifiers: ModifierMask, outputKey: UInt16) {
        let inputLabel = inputKeys.map { KeyCodes.label(for: $0) }.joined(separator: " + ")
        NSLog("[BetterModifiers] fired %@ + %@ -> %@%@",
              trigger.displayName,
              inputLabel,
              modifiers.displaySymbols,
              KeyCodes.label(for: outputKey))
        onRuleFired?(trigger, inputKeys, modifiers, outputKey)
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
        pending = nil
    }

    private func clearPending() {
        pending?.deadline?.cancel()
        pending = nil
    }

    /// Called when a layer-trigger key is released. If a sequence is still
    /// pending for this trigger, resolve it as if the timeout fired (so the
    /// fallback 1-key rule still gets a chance to fire), then return.
    private func resolvePendingForLayerEnd(_ trigger: Trigger) {
        guard let p = pending, p.trigger == trigger else { return }
        firePendingTimeout()
        _ = p
    }

    private func handleKeyUp(event: CGEvent, keyCode: UInt16) -> Unmanaged<CGEvent>? {
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
            let firedPending = pending?.trigger == .shiftSpace
            resolvePendingForLayerEnd(.shiftSpace)
            let forwarded = shiftSpaceState.forwardedSpaceDown
            let wasLayer = shiftSpaceState.usedAsLayer || firedPending
            shiftSpaceState = ShiftSpaceState()
            if forwarded {
                // The original Space-down was real; pair it with a real Space-up.
                return Unmanaged.passUnretained(event)
            }
            if !wasLayer {
                // Either Shift+Space was held from the start with no third key, or we
                // swallowed the space (post-backspace upgrade) and the user never
                // followed through. Emit the chord so apps that bind Shift+Space see it.
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
        let source = CGEventSource(stateID: .hidSystemState)
        let virtualKey = CGKeyCode(keyCode)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else {
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
        let source = CGEventSource(stateID: .hidSystemState)
        let virtualKey = CGKeyCode(KeyCodes.capsLock)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true) else {
            return
        }
        event.type = .flagsChanged
        event.flags = isEnabled ? .maskAlphaShift : []
        event.setIntegerValueField(.eventSourceUserData, value: injectedEventMarker)
        event.post(tap: .cghidEventTap)
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

    /// Cmd / Ctrl / Opt currently held - the modifiers that may be layered on top of
    /// Shift+Space and combined with the rule's output flags. Shift is excluded
    /// because it's the trigger qualifier, not an extra modifier.
    private func composableExtraFlags(_ flags: CGEventFlags) -> CGEventFlags {
        var extras: CGEventFlags = []
        if flags.contains(.maskCommand)   { extras.insert(.maskCommand) }
        if flags.contains(.maskControl)   { extras.insert(.maskControl) }
        if flags.contains(.maskAlternate) { extras.insert(.maskAlternate) }
        return extras
    }

    private func hasNonShiftUserModifiers(_ flags: CGEventFlags) -> Bool {
        let blockingFlags: [CGEventFlags] = [
            .maskCommand,
            .maskControl,
            .maskAlternate
        ]
        return blockingFlags.contains { flags.contains($0) }
    }

    private func hasAnyUserModifiers(_ flags: CGEventFlags) -> Bool {
        // Intentionally ignore .maskSecondaryFn (Fn) and .maskAlphaShift (Caps Lock LED state).
        // The OS sets Fn for arrow keys and some function-row aliases, which would otherwise
        // suppress the Tab/Caps layer for no good reason.
        let blockingFlags: [CGEventFlags] = [
            .maskShift,
            .maskCommand,
            .maskControl,
            .maskAlternate
        ]
        return blockingFlags.contains { flags.contains($0) }
    }
}
