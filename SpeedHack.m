// SpeedHack.m – Stumble Guys Speed 15x + No Cooldown with all fallbacks
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#include "fishhook.h"

static float speedMultiplier = 15.0f;
static void (*orig_set_timeScale)(float) = NULL;
static void *orig_update_cooldown = NULL;
static void *trampoline_update_cooldown = NULL;

// Status flags for popup
static BOOL speedHookOK = NO;
static BOOL speedDlsymOK = NO;
static BOOL speedTimerOK = NO;
static BOOL cooldownHookOK = NO;

// ---------------------------------------------------------------------
// Speed hook functions
// ---------------------------------------------------------------------
void hooked_set_timeScale(float value) {
    if (orig_set_timeScale) {
        orig_set_timeScale(value * speedMultiplier);
    }
}

// Timer callback that enforces speed every 0.2 seconds
void enforceSpeedTimer(CFRunLoopTimerRef timer, void *info) {
    if (orig_set_timeScale) {
        orig_set_timeScale(speedMultiplier);
    }
}

// ---------------------------------------------------------------------
// No cooldown hook
// ---------------------------------------------------------------------
void hooked_update_cooldown(void *instance, uint64_t datetime, bool forceReset) {
    ((void (*)(void *, uint64_t, bool))trampoline_update_cooldown)(instance, datetime, true);
}

uintptr_t get_unity_framework_base(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework")) return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

void install_inline_hook(void *target, void *hook, void **orig, void **tramp) {
    if (!target || !hook) return;
    *tramp = mmap(NULL, 64, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (*tramp == MAP_FAILED) return;
    memcpy(*tramp, target, 16);
    uint8_t *tramp_code = (uint8_t *)*tramp;
    uintptr_t back_addr = (uintptr_t)target + 16;
    uintptr_t tramp_end = (uintptr_t)tramp_code + 16;
    int64_t offset = (back_addr - tramp_end) / 4;
    uint32_t branch_back = 0x14000000 | (offset & 0x03FFFFFF);
    *(uint32_t *)(tramp_code + 16) = branch_back;

    uintptr_t target_addr = (uintptr_t)target;
    uintptr_t hook_addr = (uintptr_t)hook;
    int64_t hook_offset = (hook_addr - target_addr) / 4;
    if (hook_offset < -0x02000000 || hook_offset > 0x01FFFFFF) return;
    uint32_t branch_inst = 0x14000000 | (hook_offset & 0x03FFFFFF);
    vm_protect(mach_task_self(), (vm_address_t)target, 16, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE);
    *(uint32_t *)target = branch_inst;
    vm_protect(mach_task_self(), (vm_address_t)target, 16, 0, VM_PROT_READ | VM_PROT_EXECUTE);
    *orig = target;
}

// ---------------------------------------------------------------------
// Popup
// ---------------------------------------------------------------------
void showStatusPopup(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
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

// ---------------------------------------------------------------------
// Constructor
// ---------------------------------------------------------------------
__attribute__((constructor))
static void init(void) {
    // 1) fishhook for timeScale setter
    struct rebinding rebindings[] = {
        {"_UnityEngine_Time_set_timeScale", (void *)hooked_set_timeScale, (void **)&orig_set_timeScale},
        {"UnityEngine_Time_set_timeScale", (void *)hooked_set_timeScale, (void **)&orig_set_timeScale}
    };
    rebind_symbols(rebindings, 2);
    if (orig_set_timeScale) {
        speedHookOK = YES;
    }

    // 2) dlsym direct fallback
    if (!orig_set_timeScale) {
        void *sym = dlsym(RTLD_DEFAULT, "_UnityEngine_Time_set_timeScale");
        if (!sym) sym = dlsym(RTLD_DEFAULT, "UnityEngine_Time_set_timeScale");
        if (sym) {
            orig_set_timeScale = (void (*)(float))sym;
            orig_set_timeScale(speedMultiplier);
            speedDlsymOK = YES;
        }
    }

    // 3) Timer enforcement fallback
    if (orig_set_timeScale) {
        CFRunLoopTimerRef speedTimer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent(), 0.2, 0, 0, &enforceSpeedTimer, NULL);
        if (speedTimer) {
            CFRunLoopAddTimer(CFRunLoopGetMain(), speedTimer, kCFRunLoopCommonModes);
            speedTimerOK = YES;
        }
    }

    // 4) No cooldown inline hook
    uintptr_t base = get_unity_framework_base();
    if (base) {
        void *cooldown_addr = (void *)(base + 0x42C967C);
        install_inline_hook(cooldown_addr, (void *)hooked_update_cooldown, &orig_update_cooldown, &trampoline_update_cooldown);
        if (trampoline_update_cooldown) {
            cooldownHookOK = YES;
        }
    }

    // 5) Popup with status
    NSString *status = [NSString stringWithFormat:
        @"Speed hook: %@\nDlsym fallback: %@\nTimer: %@\nCooldown hook: %@",
        speedHookOK ? @"YES" : @"NO",
        speedDlsymOK ? @"YES" : @"NO",
        speedTimerOK ? @"YES" : @"NO",
        cooldownHookOK ? @"YES" : @"NO"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        showStatusPopup(status);
    });
}
