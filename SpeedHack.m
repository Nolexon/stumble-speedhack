// SpeedHack.m – Stumble Guys Speed 15x + No Cooldown (RVA-based inline hooks)
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#include "fishhook.h"

static float targetSpeed = 15.0f;

// Original function pointers
static void (*orig_set_timeScale)(float) = NULL;
static void *orig_update_cooldown = NULL;
static void *trampoline_update_cooldown = NULL;

// RVAs from your dump
#define TIME_SCALE_SETTER_RVA  0x54AFB64
#define UPDATE_COOLDOWN_RVA    0x42C967C

static uintptr_t unityFrameworkBase = 0;

// Speed hook: force targetSpeed
void hooked_set_timeScale(float value) {
    if (orig_set_timeScale) {
        orig_set_timeScale(targetSpeed);
    }
}

// No cooldown hook: forceReset = true
void hooked_update_cooldown(void *instance, uint64_t datetime, bool forceReset) {
    ((void (*)(void *, uint64_t, bool))trampoline_update_cooldown)(instance, datetime, true);
}

// Find UnityFramework or main executable base
uintptr_t get_unity_framework_base(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework") ||
            strstr(name, "StumbleGuys") ||
            strstr(name, "Unity")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

// Simple ARM64 inline hook: patches first instruction with branch to hook
// Returns trampoline that executes original first 16 bytes then branches back.
void install_inline_hook(void *target, void *hook, void **orig, void **tramp) {
    if (!target || !hook) return;

    // Allocate trampoline (64 bytes)
    *tramp = mmap(NULL, 64, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (*tramp == MAP_FAILED) {
        *tramp = NULL;
        return;
    }

    // Copy first 4 instructions (16 bytes) to trampoline
    memcpy(*tramp, target, 16);

    // Add branch back from trampoline to target+16
    uint8_t *tramp_code = (uint8_t *)*tramp;
    uintptr_t back_addr = (uintptr_t)target + 16;
    uintptr_t tramp_end = (uintptr_t)tramp_code + 16;
    int64_t offset = (back_addr - tramp_end) / 4;
    uint32_t branch_back = 0x14000000 | (offset & 0x03FFFFFF);
    *(uint32_t *)(tramp_code + 16) = branch_back;

    // Patch target with branch to hook
    uintptr_t target_addr = (uintptr_t)target;
    uintptr_t hook_addr = (uintptr_t)hook;
    int64_t hook_offset = (hook_addr - target_addr) / 4;
    if (hook_offset < -0x02000000 || hook_offset > 0x01FFFFFF) {
        munmap(*tramp, 64);
        *tramp = NULL;
        return;
    }
    uint32_t branch_inst = 0x14000000 | (hook_offset & 0x03FFFFFF);

    // Change memory protection to executable + writable
    vm_protect(mach_task_self(), (vm_address_t)target, 16, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE);
    *(uint32_t *)target = branch_inst;
    // Flush instruction cache (important on ARM64)
    sys_cache_control(kCacheFunctionPrepareForExecution, target, 16);
    vm_protect(mach_task_self(), (vm_address_t)target, 16, 0, VM_PROT_READ | VM_PROT_EXECUTE);

    *orig = target;
}

// Popup
void showStatusPopup(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isKeyWindow) { keyWindow = window; break; }
        }
        UIViewController *rootVC = keyWindow ? keyWindow.rootViewController : nil;
        if (rootVC) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SpeedHack" message:message preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [rootVC presentViewController:alert animated:YES completion:nil];
        } else {
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, 240, 100)];
            label.text = message;
            label.numberOfLines = 0;
            label.backgroundColor = [UIColor blackColor];
            label.textColor = [UIColor greenColor];
            label.textAlignment = NSTextAlignmentCenter;
            label.layer.cornerRadius = 8;
            label.clipsToBounds = YES;
            [keyWindow addSubview:label];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [label removeFromSuperview];
            });
        }
    });
}

// Initialization
__attribute__((constructor))
static void init(void) {
    // Delay until game is loaded
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        unityFrameworkBase = get_unity_framework_base();

        BOOL speedHookOK = NO;
        BOOL cooldownHookOK = NO;

        // Hook Time.timeScale setter at RVA 0x54AFB64
        if (unityFrameworkBase) {
            void *setterAddr = (void *)(unityFrameworkBase + TIME_SCALE_SETTER_RVA);
            install_inline_hook(setterAddr, (void *)hooked_set_timeScale, (void **)&orig_set_timeScale, (void **)&trampoline_update_cooldown); // reuse tramp variable? Actually separate
            if (orig_set_timeScale) speedHookOK = YES;

            // Hook UpdateCooldown at RVA 0x42C967C
            void *cooldownAddr = (void *)(unityFrameworkBase + UPDATE_COOLDOWN_RVA);
            install_inline_hook(cooldownAddr, (void *)hooked_update_cooldown, &orig_update_cooldown, &trampoline_update_cooldown);
            if (trampoline_update_cooldown) cooldownHookOK = YES;
        }

        // Popup with status
        NSString *status = [NSString stringWithFormat:
            @"Speed hook: %@\nCooldown hook: %@",
            speedHookOK ? @"YES" : @"NO",
            cooldownHookOK ? @"YES" : @"NO"];
        showStatusPopup(status);
    });
}
