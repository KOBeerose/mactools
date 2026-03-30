#include "LayerKeyHID.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hid/IOHIDProperties.h>
#include <IOKit/hid/IOHIDUsageTables.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <IOKit/hidsystem/IOHIDParameter.h>

static const uint64_t kCapsLockUsage = 0x700000039;
static const uint64_t kF18Usage = 0x70000006D;

static bool service_is_keyboard(IOHIDServiceClientRef service) {
    return IOHIDServiceClientConformsTo(service, kHIDPage_GenericDesktop, kHIDUsage_GD_Keyboard) != 0
        || IOHIDServiceClientConformsTo(service, kHIDPage_GenericDesktop, kHIDUsage_GD_Keypad) != 0;
}

static CFArrayRef create_mapping_array(bool enabled) {
    if (!enabled) {
        return CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
    }

    CFNumberRef src = NULL;
    CFNumberRef dst = NULL;
    CFDictionaryRef mapping = NULL;
    CFArrayRef result = NULL;

    src = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &kCapsLockUsage);
    dst = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &kF18Usage);
    if (!src || !dst) {
        goto cleanup;
    }

    const void *keys[] = {
        CFSTR(kIOHIDKeyboardModifierMappingSrcKey),
        CFSTR(kIOHIDKeyboardModifierMappingDstKey)
    };
    const void *values[] = { src, dst };

    mapping = CFDictionaryCreate(
        kCFAllocatorDefault,
        keys,
        values,
        2,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    if (!mapping) {
        goto cleanup;
    }

    const void *items[] = { mapping };
    result = CFArrayCreate(kCFAllocatorDefault, items, 1, &kCFTypeArrayCallBacks);

cleanup:
    if (mapping) {
        CFRelease(mapping);
    }
    if (src) {
        CFRelease(src);
    }
    if (dst) {
        CFRelease(dst);
    }

    return result;
}

bool mo_set_caps_lock_mapping_enabled(bool enabled) {
    bool success = false;
    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault);
    if (!system) {
        return false;
    }

    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);
    CFArrayRef mapping = create_mapping_array(enabled);
    if (!services || !mapping) {
        goto cleanup;
    }

    CFIndex count = CFArrayGetCount(services);
    success = true;

    for (CFIndex idx = 0; idx < count; idx++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, idx);
        if (!service || !service_is_keyboard(service)) {
            continue;
        }
        if (!IOHIDServiceClientSetProperty(service, CFSTR(kIOHIDUserKeyUsageMapKey), mapping)) {
            success = false;
        }
    }

cleanup:
    if (services) {
        CFRelease(services);
    }
    if (mapping) {
        CFRelease(mapping);
    }
    CFRelease(system);
    return success;
}

static bool with_hid_connection(io_connect_t *connect_out) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass));
    if (!service) {
        return false;
    }

    kern_return_t open_result = IOServiceOpen(service, mach_task_self(), kIOHIDParamConnectType, connect_out);
    IOObjectRelease(service);
    return open_result == KERN_SUCCESS;
}

bool mo_get_caps_lock_state(bool *state_out) {
    if (!state_out) {
        return false;
    }

    io_connect_t connection = IO_OBJECT_NULL;
    if (!with_hid_connection(&connection)) {
        return false;
    }

    bool state = false;
    kern_return_t result = IOHIDGetModifierLockState(connection, kIOHIDCapsLockState, &state);
    IOServiceClose(connection);

    if (result != KERN_SUCCESS) {
        return false;
    }

    *state_out = state;
    return true;
}

bool mo_set_caps_lock_state(bool enabled) {
    io_connect_t connection = IO_OBJECT_NULL;
    if (!with_hid_connection(&connection)) {
        return false;
    }

    kern_return_t result = IOHIDSetModifierLockState(connection, kIOHIDCapsLockState, enabled);
    IOServiceClose(connection);
    return result == KERN_SUCCESS;
}
