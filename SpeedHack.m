// SpeedHack.m – Stumble Guys Speed 15x + No Cooldown (FIXED)
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <libkern/OSCacheControl.h>
#import <sys/mman.h>
#import <string.h>

static float targetSpeed = 15.0f;

// RVAs from dump (VERIFY THESE FOR YOUR BINARY)
#define TIME_SCALE_SETTER_RVA  0x54AFB64
#define UPDATE_COOLDOWN_RVA    0x42C967C

// Trampolines
static void *trampoline_timeScale = NULL;
static void *trampoline_updateCooldown = NULL;

// =====================================================================
// Hook functions
// =====================================================================
void hooked_set_timeScale(float value) {
    // Force target speed every time the setter is called
    ((void (*)(float))trampoline_timeScale)(targetSpeed);
}

void hooked_update_cooldown(void *instance, uint64_t datetime, bool forceReset) {
    // Force reset
    ((void (*)(void *, uint64_t, bool))trampoline_updateCooldown)(instance, datetime, true);
}

// =====================================================================
// Find UnityFramework base correctly
// =====================================================================
uintptr_t get_unity_framework_base(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework")) {
            uintptr_t base = (uintptr_t)_dyld_get_image_header(i);
            NSLog(@"[SpeedHack] UnityFramework found at: 0x%lx", base);
            return base;
        }
    }
    NSLog(@"[SpeedHack] UnityFramework NOT found");
    return 0;
}

// =====================================================================
// ARM64 inline hook with proper branch encoding
// =====================================================================
BOOL install_inline_hook(void *target, void *hook, void **trampoline) {
    if (!target || !hook || !trampoline) {
        NSLog(@"[SpeedHack] Invalid parameters for hook");
        return NO;
    }

    NSLog(@"[SpeedHack] Installing hook: target=0x%lx hook=0x%lx", 
          (uintptr_t)target, (uintptr_t)hook);

    // Allocate trampoline (128 bytes, executable)
    void *tramp = mmap(NULL, 128, PROT_READ | PROT_WRITE | PROT_EXEC,
                       MAP_ANON | MAP_PRIVATE, -1, 0);
    if (tramp == MAP_FAILED) {
        NSLog(@"[SpeedHack] Failed to allocate trampoline");
        return NO;
    }
    memset(tramp, 0, 128);

    // Save first 4 instructions (16 bytes)
    memcpy(tramp, target, 16);

    // Calculate offset from end of saved instructions back to target+16
    uintptr_t back_addr = (uintptr_t)target + 16;
    uintptr_t tramp_branch_addr = (uintptr_t)tramp + 16;
    int64_t back_offset = (int64_t)(back_addr - tramp_branch_addr) / 4;

    // Verify offset is in range for 26-bit signed immediate
    if (back_offset < -0x2000000 || back_offset > 0x1FFFFFF) {
        NSLog(@"[SpeedHack] Trampoline branch offset out of range: %lld", back_offset);
        munmap(tramp, 128);
        return NO;
    }

    // Encode B (branch) instruction: 0x14000000 | (imm26 & 0x3FFFFFF)
    uint32_t branch_back = 0x14000000 | (back_offset & 0x3FFFFFF);
    *(uint32_t *)((uintptr_t)tramp + 16) = branch_back;

    NSLog(@"[SpeedHack] Trampoline: saved 16 bytes, branch back offset: 0x%llx", back_offset);

    // Calculate offset from target to hook
    uintptr_t target_addr = (uintptr_t)target;
    uintptr_t hook_addr = (uintptr_t)hook;
    int64_t hook_offset = (int64_t)(hook_addr - target_addr) / 4;

    // Verify offset is in range for 26-bit signed immediate
    if (hook_offset < -0x2000000 || hook_offset > 0x1FFFFFF) {
        NSLog(@"[SpeedHack] Hook branch offset out of range: %lld", hook_offset);
        munmap(tramp, 128);
        return NO;
    }

    // Encode B (branch) instruction to hook
    uint32_t branch_to_hook = 0x14000000 | (hook_offset & 0x3FFFFFF);

    NSLog(@"[SpeedHack] Hook branch instruction: 0x%x (offset: 0x%llx)", branch_to_hook, hook_offset);

    // Make target writable
    kern_return_t kr = vm_protect(mach_task_self(), (vm_address_t)target, 16, 
                                   FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        NSLog(@"[SpeedHack] vm_protect (make writable) failed: %d", kr);
        munmap(tramp, 128);
        return NO;
    }

    // Patch target with branch to hook
    *(uint32_t *)target = branch_to_hook;

    // Flush instruction cache
    sys_icache_invalidate((void *)target, 16);

    // Make target read+execute again
    kr = vm_protect(mach_task_self(), (vm_address_t)target, 16, 
                    FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        NSLog(@"[SpeedHack] vm_protect (make executable) failed: %d", kr);
        munmap(tramp, 128);
        return NO;
    }

    *trampoline = tramp;
    NSLog(@"[SpeedHack] Hook installed successfully");
    return YES;
}

// =====================================================================
// Popup/Status display
// =====================================================================
void showStatusPopup(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isKeyWindow) { 
                keyWindow = window; 
                break; 
            }
        }
        
        if (!keyWindow) {
            keyWindow = [UIApplication sharedApplication].windows.firstObject;
        }

        UIViewController *rootVC = keyWindow ? keyWindow.rootViewController : nil;
        
        if (rootVC) {
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"SpeedHack"
                message:message
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                style:UIAlertActionStyleDefault handler:nil]];
            [rootVC presentViewController:alert animated:YES completion:nil];
        } else if (keyWindow) {
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, 260, 120)];
            label.text = message;
            label.numberOfLines = 0;
            label.backgroundColor = [UIColor blackColor];
            label.textColor = [UIColor greenColor];
            label.textAlignment = NSTextAlignmentCenter;
            label.layer.cornerRadius = 8;
            label.clipsToBounds = YES;
            label.font = [UIFont systemFontOfSize:14];
            [keyWindow addSubview:label];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                dispatch_get_main_queue(), ^{
                    [label removeFromSuperview];
                });
        }
    });
}

// =====================================================================
// Constructor - Entry point
// =====================================================================
__attribute__((constructor))
static void init(void) {
    NSLog(@"[SpeedHack] Constructor called, waiting for Unity to load...");
    
    // Wait for Unity to load
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
            BOOL speedHookOK = NO;
            BOOL cooldownHookOK = NO;
            BOOL baseFound = NO;

            uintptr_t base = get_unity_framework_base();
            if (base) {
                baseFound = YES;

                // Hook Time.timeScale setter
                void *setterAddr = (void *)(base + TIME_SCALE_SETTER_RVA);
                NSLog(@"[SpeedHack] Time.timeScale setter at: 0x%lx", (uintptr_t)setterAddr);
                
                if (install_inline_hook(setterAddr, (void *)hooked_set_timeScale,
                                        &trampoline_timeScale)) {
                    speedHookOK = YES;
                    NSLog(@"[SpeedHack] Speed hook installed successfully");
                } else {
                    NSLog(@"[SpeedHack] Speed hook installation FAILED");
                }

                // Hook UpdateCooldown
                void *cooldownAddr = (void *)(base + UPDATE_COOLDOWN_RVA);
                NSLog(@"[SpeedHack] UpdateCooldown at: 0x%lx", (uintptr_t)cooldownAddr);
                
                if (install_inline_hook(cooldownAddr, (void *)hooked_update_cooldown,
                                        &trampoline_updateCooldown)) {
                    cooldownHookOK = YES;
                    NSLog(@"[SpeedHack] Cooldown hook installed successfully");
                } else {
                    NSLog(@"[SpeedHack] Cooldown hook installation FAILED");
                }
            }

            NSString *status = [NSString stringWithFormat:
                @"UnityBase: %@\nSpeed hook: %@\nCooldown hook: %@\n\nSpeed: 15x",
                baseFound ? @"✓ FOUND" : @"✗ NOT FOUND",
                speedHookOK ? @"✓ YES" : @"✗ NO",
                cooldownHookOK ? @"✓ YES" : @"✗ NO"];
            
            NSLog(@"[SpeedHack] Status: %@", status);
            showStatusPopup(status);
        });
}
