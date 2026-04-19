import BetterModifiersHID
import Foundation

@MainActor
final class CapsLockController {
    private(set) var isRemapped = false

    func setRemapEnabled(_ enabled: Bool) {
        guard enabled != isRemapped else { return }
        if bm_set_caps_lock_mapping_enabled(enabled) {
            isRemapped = enabled
        }
    }

    func syncRemap(enabled: Bool) {
        if bm_set_caps_lock_mapping_enabled(enabled) {
            isRemapped = enabled
        }
    }

    func currentCapsLockState() -> Bool {
        var state = false
        if bm_get_caps_lock_state(&state) {
            return state
        }
        return false
    }

    func setCapsLockState(_ enabled: Bool) {
        _ = bm_set_caps_lock_state(enabled)
    }
}
