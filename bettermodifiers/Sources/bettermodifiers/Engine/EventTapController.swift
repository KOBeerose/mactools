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
    private var receivedAnyEvent = false
    private var loggedFirstEvent = false
    private var healthCheckGeneration = 0

    private(set) var isEnabled = true

    var onStatusChange: ((Status) -> Void)?
    /// Called on the main actor whenever a rule (or modifier-mode mapping) actually fires.
    /// Used by the UI to surface a "Last triggered: X" diagnostic so the user can confirm
    /// the engine is alive without having to read the system log.
    var onRuleFired: ((Trigger, UInt16, ModifierMask, UInt16) -> Void)?

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
            // and compose with the rule's output flags, so e.g. ⇧Space+⌘+J can map to
            // ⌘ + (rule output) + J without blocking.
            let extraFlags = composableExtraFlags(event.flags)
            let mode = settings.modeConfig(for: .shiftSpace)
            if mode.isEnabled {
                shiftSpaceState.usedAsLayer = true
                shiftSpaceState.consumedInputKeys.insert(keyCode)
                emitKeyEventPair(keyCode: keyCode, flags: mode.modifiers.eventFlags.union(extraFlags))
                fireDiagnostic(trigger: .shiftSpace, inputKey: keyCode, modifiers: mode.modifiers, outputKey: keyCode)
                return nil
            }
            if let rule = rules.rule(for: .shiftSpace, inputKey: keyCode) {
                shiftSpaceState.usedAsLayer = true
                shiftSpaceState.consumedInputKeys.insert(keyCode)
                emitKeyEventPair(keyCode: rule.outputKey, flags: rule.outputModifiers.eventFlags.union(extraFlags))
                fireDiagnostic(trigger: .shiftSpace, inputKey: keyCode, modifiers: rule.outputModifiers, outputKey: rule.outputKey)
                return nil
            }
            // No rule and Modifier Mode off: fall through so the third key types
            // normally (with whatever modifiers are actually held). We deliberately do
            // NOT mark usedAsLayer here, so on Space-up we still emit the fallback
            // Shift+Space chord the user implicitly intended.
        }

        if capsLockState.isPressed {
            let mode = settings.modeConfig(for: .capsLock)
            if mode.isEnabled, !hasAnyUserModifiers(event.flags) {
                capsLockState.usedAsLayer = true
                capsLockState.consumedInputKeys.insert(keyCode)
                emitKeyEventPair(keyCode: keyCode, flags: mode.modifiers.eventFlags)
                fireDiagnostic(trigger: .capsLock, inputKey: keyCode, modifiers: mode.modifiers, outputKey: keyCode)
                return nil
            }
            if !mode.isEnabled,
               let rule = rules.rule(for: .capsLock, inputKey: keyCode),
               !hasAnyUserModifiers(event.flags) {
                capsLockState.usedAsLayer = true
                capsLockState.consumedInputKeys.insert(keyCode)
                emitKeyEventPair(keyCode: rule.outputKey, flags: rule.outputModifiers.eventFlags)
                fireDiagnostic(trigger: .capsLock, inputKey: keyCode, modifiers: rule.outputModifiers, outputKey: rule.outputKey)
                return nil
            }

            capsLockState.usedAsLayer = true
        }

        if tabState.isPressed {
            let mode = settings.modeConfig(for: .tab)
            if mode.isEnabled, !hasAnyUserModifiers(event.flags) {
                tabState.usedAsLayer = true
                tabState.consumedInputKeys.insert(keyCode)
                emitKeyEventPair(keyCode: keyCode, flags: mode.modifiers.eventFlags)
                fireDiagnostic(trigger: .tab, inputKey: keyCode, modifiers: mode.modifiers, outputKey: keyCode)
                return nil
            }
            if !mode.isEnabled,
               let rule = rules.rule(for: .tab, inputKey: keyCode),
               !hasAnyUserModifiers(event.flags) {
                tabState.usedAsLayer = true
                tabState.consumedInputKeys.insert(keyCode)
                emitKeyEventPair(keyCode: rule.outputKey, flags: rule.outputModifiers.eventFlags)
                fireDiagnostic(trigger: .tab, inputKey: keyCode, modifiers: rule.outputModifiers, outputKey: rule.outputKey)
                return nil
            }

            if !tabState.forwardedTabDown {
                emitSingleKeyEvent(keyCode: KeyCodes.tab, flags: [], keyDown: true)
                tabState.forwardedTabDown = true
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func fireDiagnostic(trigger: Trigger, inputKey: UInt16, modifiers: ModifierMask, outputKey: UInt16) {
        NSLog("[BetterModifiers] fired %@ + %@ -> %@%@",
              trigger.displayName,
              KeyCodes.label(for: inputKey),
              modifiers.displaySymbols,
              KeyCodes.label(for: outputKey))
        onRuleFired?(trigger, inputKey, modifiers, outputKey)
    }

    private func handleKeyUp(event: CGEvent, keyCode: UInt16) -> Unmanaged<CGEvent>? {
        if keyCode == KeyCodes.f18, capsLockState.isPressed {
            if !capsLockState.usedAsLayer {
                let newState = !capsLockState.originalCapsLockState
                capsLockController.setCapsLockState(newState)
                postSyntheticCapsLockFlagsChanged(isEnabled: newState)
            }
            capsLockState = CapsLockLayerState()
            return nil
        }

        if keyCode == KeyCodes.tab, tabState.isPressed {
            if tabState.forwardedTabDown {
                emitSingleKeyEvent(keyCode: KeyCodes.tab, flags: [], keyDown: false)
            } else if !tabState.usedAsLayer {
                emitKeyEventPair(keyCode: KeyCodes.tab, flags: [])
            }
            tabState = TabState()
            return nil
        }

        if keyCode == KeyCodes.space, shiftSpaceState.isPressed {
            let forwarded = shiftSpaceState.forwardedSpaceDown
            let wasLayer = shiftSpaceState.usedAsLayer
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

    /// After toggling Caps Lock via IOKit, web views (Chromium/WebKit) often only refresh IME / shift state
    /// when they see a Quartz `flagsChanged` with `alphaShift`. Without this, typing in some browser fields
    /// can stay wrong until focus moves (e.g. to the address bar).
    private func postSyntheticCapsLockFlagsChanged(isEnabled: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        let virtualKey = CGKeyCode(KeyCodes.capsLock)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: isEnabled) else {
            return
        }
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
