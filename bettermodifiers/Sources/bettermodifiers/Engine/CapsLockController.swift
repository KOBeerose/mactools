import BetterModifiersHID
import Foundation

@MainActor
final class CapsLockController {
    func syncRemap(enabled: Bool) {
        _ = bm_set_caps_lock_mapping_enabled(enabled)
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
