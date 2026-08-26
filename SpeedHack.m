// SpeedHack.m – Stumble Guys Speed + No Cooldown (fishhook + inline hook)
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#include "fishhook.h"

static float speedMultiplier = 5.0f;
static void (*orig_set_timeScale)(float);
static void *orig_update_cooldown = NULL;
static void *trampoline_update_cooldown = NULL;

@interface SliderController : NSObject
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *valueLabel;
- (void)sliderValueChanged:(UISlider *)sender;
@end

@implementation SliderController
- (void)sliderValueChanged:(UISlider *)sender {
    speedMultiplier = sender.value;
    if (self.valueLabel) {
        self.valueLabel.text = [NSString stringWithFormat:@"%.1fx", speedMultiplier];
    }
}
@end

void hooked_set_timeScale(float value) {
    if (orig_set_timeScale) orig_set_timeScale(value * speedMultiplier);
}

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
        [bg addSubview:slider];

        UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 85, 200, 25)];
        valueLabel.text = [NSString stringWithFormat:@"%.1fx", speedMultiplier];
        valueLabel.textColor = [UIColor greenColor];
        valueLabel.font = [UIFont systemFontOfSize:14];
        [bg addSubview:valueLabel];

        SliderController *controller = [[SliderController alloc] init];
        controller.slider = slider;
        controller.valueLabel = valueLabel;
        [slider addTarget:controller action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];

        menuWindow.rootViewController = vc;
        menuWindow.userInteractionEnabled = YES;
    });
}

__attribute__((constructor))
static void init(void) {
    struct rebinding rebindings[] = {
        {"_UnityEngine_Time_set_timeScale", (void *)hooked_set_timeScale, (void **)&orig_set_timeScale},
        {"UnityEngine_Time_set_timeScale", (void *)hooked_set_timeScale, (void **)&orig_set_timeScale}
    };
    rebind_symbols(rebindings, 2);

    uintptr_t base = get_unity_framework_base();
    if (base) {
        void *cooldown_addr = (void *)(base + 0x42C967C);
        install_inline_hook(cooldown_addr, (void *)hooked_update_cooldown, &orig_update_cooldown, &trampoline_update_cooldown);
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        showSliderMenu();
    });
}
