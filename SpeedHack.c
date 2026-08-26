// SpeedHack.c – Stumble Guys Speed Multiplier + No Cooldown
// Replace the entire content of your existing SpeedHack.c with this.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#include "Dobby/include/dobby.h"

static float speedMultiplier = 5.0f; // default 5x

// Original function pointers
static void (*orig_set_timeScale)(float);
static void (*orig_update_cooldown)(void *instance, uint64_t datetime, bool forceReset);

// Hooked Unity timeScale setter – multiplies by current speedMultiplier
void hooked_set_timeScale(float value) {
    if (orig_set_timeScale) {
        orig_set_timeScale(value * speedMultiplier);
    }
}

// Hooked UpdateCooldown – forces forceReset = true
void hooked_update_cooldown(void *instance, uint64_t datetime, bool forceReset) {
    if (orig_update_cooldown) {
        orig_update_cooldown(instance, datetime, true);
    }
}

// Find UnityFramework base address
uintptr_t get_unity_framework_base(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

// Simple mod menu with speed slider
static UIWindow *menuWindow = nil;

void showSliderMenu(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (menuWindow) return;
        CGRect screen = [UIScreen mainScreen].bounds;
        menuWindow = [[UIWindow alloc] initWithFrame:screen];
        menuWindow.windowLevel = UIWindowLevelAlert + 10;
        menuWindow.backgroundColor = [UIColor clearColor];
        menuWindow.hidden = NO;

        UIViewController *vc = [[UIViewController alloc] init];
        UIView *bg = [[UIView alloc] initWithFrame:CGRectMake(20, 100, screen.size.width-40, 120)];
        bg.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.85];
        bg.layer.cornerRadius = 12;
        [vc.view addSubview:bg];

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, 200, 30)];
        label.text = @"Speed Multiplier";
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont boldSystemFontOfSize:16];
        [bg addSubview:label];

        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(20, 50, bg.bounds.size.width-40, 30)];
        slider.minimumValue = 0.1f;
        slider.maximumValue = 20.0f;
        slider.value = speedMultiplier;
        [slider addTarget:^{ speedMultiplier = slider.value; } action:@selector(invoke) forControlEvents:UIControlEventValueChanged];
        [bg addSubview:slider];

        UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 85, 200, 25)];
        valueLabel.text = [NSString stringWithFormat:@"%.1fx", speedMultiplier];
        valueLabel.textColor = [UIColor greenColor];
        valueLabel.font = [UIFont systemFontOfSize:14];
        valueLabel.tag = 99;
        [bg addSubview:valueLabel];

        [slider addTarget:^{
            UILabel *vl = (UILabel *)[bg viewWithTag:99];
            if (vl) vl.text = [NSString stringWithFormat:@"%.1fx", speedMultiplier];
        } action:@selector(invoke) forControlEvents:UIControlEventValueChanged];

        menuWindow.rootViewController = vc;
        menuWindow.userInteractionEnabled = YES;
    });
}

__attribute__((constructor))
static void init(void) {
    // Hook Unity timeScale
    void *symbol = dlsym(RTLD_DEFAULT, "_UnityEngine_Time_set_timeScale");
    if (!symbol) symbol = dlsym(RTLD_DEFAULT, "UnityEngine_Time_set_timeScale");
    if (symbol) DobbyHook(symbol, (void *)hooked_set_timeScale, (void **)&orig_set_timeScale);

    // Hook UpdateCooldown at RVA 0x42C967C (adjust if game version changes)
    uintptr_t base = get_unity_framework_base();
    if (base) {
        DobbyHook((void *)(base + 0x42C967C), (void *)hooked_update_cooldown, (void **)&orig_update_cooldown);
    }

    // Show mod menu after 3 seconds
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        showSliderMenu();
    });
}
