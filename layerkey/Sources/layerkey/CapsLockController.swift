import Foundation
import LayerKeyHID

@MainActor
final class CapsLockController {
    private(set) var isRemapped = false

    func setRemapEnabled(_ enabled: Bool) {
        guard enabled != isRemapped else { return }
        if mo_set_caps_lock_mapping_enabled(enabled) {
            isRemapped = enabled
        }
    }

    func syncRemap(enabled: Bool) {
        if mo_set_caps_lock_mapping_enabled(enabled) {
            isRemapped = enabled
        }
    }

    func currentCapsLockState() -> Bool {
        var state = false
        if mo_get_caps_lock_state(&state) {
            return state
        }
        return false
    }

    func setCapsLockState(_ enabled: Bool) {
        _ = mo_set_caps_lock_state(enabled)
    }

    func toggleCapsLockState() {
        setCapsLockState(!currentCapsLockState())
    }
}
