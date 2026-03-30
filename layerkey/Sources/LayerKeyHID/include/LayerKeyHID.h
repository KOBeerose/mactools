#ifndef LAYERKEY_HID_H
#define LAYERKEY_HID_H

#include <stdbool.h>

bool mo_set_caps_lock_mapping_enabled(bool enabled);
bool mo_get_caps_lock_state(bool *state_out);
bool mo_set_caps_lock_state(bool enabled);

#endif
