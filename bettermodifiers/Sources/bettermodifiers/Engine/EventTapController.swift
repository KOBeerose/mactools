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

    private let rules: RulesStore
    private let settings: SettingsStore
    private let permissions: PermissionsController
    private let capsLockController: CapsLockController
    private let injectedEventMarker: Int64 = 0x4245544d4f44 // "BETMOD"

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tabState = TabState()
    private var capsLockState = CapsLockLayerState()
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
        case .flagsChanged: return Unmanaged.passUnretained(event)
        default: return Unmanaged.passUnretained(event)
        }
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

        if tabState.consumedInputKeys.contains(keyCode) {
            tabState.consumedInputKeys.remove(keyCode)
            return nil
        }

        if capsLockState.consumedInputKeys.contains(keyCode) {
            capsLockState.consumedInputKeys.remove(keyCode)
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
