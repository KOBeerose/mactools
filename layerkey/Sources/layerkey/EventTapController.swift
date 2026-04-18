import ApplicationServices
import Foundation

@MainActor
final class EventTapController {
    enum Status: Equatable {
        case inactive
        case running
        case missingPermissions
        case failedToCreateTap

        var displayText: String {
            switch self {
            case .inactive:
                return "Disabled"
            case .running:
                return "Active"
            case .missingPermissions:
                return "Accessibility required"
            case .failedToCreateTap:
                return "Failed to start event tap"
            }
        }
    }

    private struct TabState {
        var isPressed = false
        var forwardedTabDown = false
        var usedAsLayer = false
    }

    private struct CapsLockState {
        var isPressed = false
        var usedAsLayer = false
        var originalCapsLockState = false
    }

    private let settings: SettingsStore
    private let permissions: PermissionsController
    private let capsLockController: CapsLockController
    private let injectedEventMarker: Int64 = 0x4d4f544142

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tabState = TabState()
    private var capsLockState = CapsLockState()

    var onStatusChange: ((Status) -> Void)?

    private(set) var status: Status = .inactive {
        didSet {
            guard status != oldValue else { return }
            onStatusChange?(status)
        }
    }

    init(settings: SettingsStore, permissions: PermissionsController, capsLockController: CapsLockController) {
        self.settings = settings
        self.permissions = permissions
        self.capsLockController = capsLockController
    }

    func refresh() {
        stop()

        guard settings.isEnabled else {
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
        capsLockState = CapsLockState()

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        capsLockController.syncRemap(enabled: settings.enabledTriggers.contains(.capsLock))
        status = .running
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
        capsLockState = CapsLockState()
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

        if event.getIntegerValueField(.eventSourceUserData) == injectedEventMarker {
            return Unmanaged.passUnretained(event)
        }

        guard settings.isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .keyDown:
            return handleKeyDown(event: event, keyCode: keyCode)
        case .keyUp:
            return handleKeyUp(event: event, keyCode: keyCode)
        case .flagsChanged:
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(event: CGEvent, keyCode: Int64) -> Unmanaged<CGEvent>? {
        if keyCode == KeyCodeMap.f18, settings.enabledTriggers.contains(.capsLock) {
            capsLockState.isPressed = true
            capsLockState.usedAsLayer = false
            capsLockState.originalCapsLockState = capsLockController.currentCapsLockState()
            return nil
        }

        if keyCode == KeyCodeMap.tab, settings.enabledTriggers.contains(.tab), isPlainTabLayerTrigger(event: event) {
            tabState.isPressed = true
            tabState.forwardedTabDown = false
            tabState.usedAsLayer = false
            return nil
        }

        if capsLockState.isPressed {
            if KeyCodeMap.isDigit(keyCode), !hasAnyUserModifiers(event.flags) {
                capsLockState.usedAsLayer = true
                emitKeyEventPair(keyCode: keyCode, flags: settings.outputModifier.eventFlags)
                return nil
            }

            capsLockState.usedAsLayer = true
        }

        if tabState.isPressed {
            if KeyCodeMap.isDigit(keyCode), !hasAnyUserModifiers(event.flags) {
                tabState.usedAsLayer = true
                emitKeyEventPair(keyCode: keyCode, flags: settings.outputModifier.eventFlags)
                return nil
            }

            if !tabState.forwardedTabDown {
                emitSingleKeyEvent(keyCode: KeyCodeMap.tab, flags: [], keyDown: true)
                tabState.forwardedTabDown = true
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyUp(event: CGEvent, keyCode: Int64) -> Unmanaged<CGEvent>? {
        if keyCode == KeyCodeMap.f18, capsLockState.isPressed {
            if !capsLockState.usedAsLayer {
                let newState = !capsLockState.originalCapsLockState
                capsLockController.setCapsLockState(newState)
                postSyntheticCapsLockFlagsChanged(isEnabled: newState)
            }
            capsLockState = CapsLockState()
            return nil
        }

        if keyCode == KeyCodeMap.tab, tabState.isPressed {
            if tabState.forwardedTabDown {
                emitSingleKeyEvent(keyCode: KeyCodeMap.tab, flags: [], keyDown: false)
            } else if !tabState.usedAsLayer {
                emitKeyEventPair(keyCode: KeyCodeMap.tab, flags: [])
            }
            tabState = TabState()
            return nil
        }

        if (tabState.isPressed || capsLockState.isPressed) && KeyCodeMap.isDigit(keyCode) {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func emitKeyEventPair(keyCode: Int64, flags: CGEventFlags) {
        emitSingleKeyEvent(keyCode: keyCode, flags: flags, keyDown: true)
        emitSingleKeyEvent(keyCode: keyCode, flags: flags, keyDown: false)
    }

    private func emitSingleKeyEvent(keyCode: Int64, flags: CGEventFlags, keyDown: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        let virtualKey = CGKeyCode(keyCode)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else {
            return
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: injectedEventMarker)
        event.post(tap: .cghidEventTap)
    }

    /// After toggling Caps Lock via IOKit, web views (Chromium/WebKit) often only refresh IME / shift state when they see a Quartz `flagsChanged` with `alphaShift`. Without this, typing in some browser fields can stay wrong until focus moves (e.g. to the address bar).
    private func postSyntheticCapsLockFlagsChanged(isEnabled: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        let virtualKey = CGKeyCode(KeyCodeMap.capsLock)
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
        let blockingFlags: [CGEventFlags] = [
            .maskShift,
            .maskCommand,
            .maskControl,
            .maskAlternate,
            .maskSecondaryFn
        ]
        return blockingFlags.contains { flags.contains($0) }
    }
}
