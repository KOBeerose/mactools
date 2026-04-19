#ifndef BETTER_MODIFIERS_HID_H
#define BETTER_MODIFIERS_HID_H

#include <stdbool.h>

bool bm_set_caps_lock_mapping_enabled(bool enabled);
bool bm_get_caps_lock_state(bool *state_out);
bool bm_set_caps_lock_state(bool enabled);

#endif
