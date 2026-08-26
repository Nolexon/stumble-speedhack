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
        self.valueLabel.text = [NSString stringWithFormat:@"Speed: %.1fx", speedMultiplier];
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
        menuWindow.windowLevel = UIWindowLevelAlert + 100;
        menuWindow.backgroundColor = [UIColor clearColor];
        menuWindow.hidden = NO;
        menuWindow.userInteractionEnabled = YES;

        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.backgroundColor = [UIColor clearColor];
        vc.view.frame = screen;
        
        // Centered popup container
        UIView *popupContainer = [[UIView alloc] initWithFrame:CGRectMake(screen.size.width / 2 - 150, screen.size.height / 2 - 100, 300, 200)];
        popupContainer.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.2 alpha:0.98];
        popupContainer.layer.cornerRadius = 20;
        popupContainer.layer.borderColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:0.8].CGColor;
        popupContainer.layer.borderWidth = 2;
        popupContainer.layer.shadowColor = [UIColor blackColor].CGColor;
        popupContainer.layer.shadowOpacity = 0.9;
        popupContainer.layer.shadowOffset = CGSizeMake(0, 10);
        popupContainer.layer.shadowRadius = 20;
        popupContainer.layer.masksToBounds = NO;
        popupContainer.transform = CGAffineTransformMakeScale(0.1, 0.1);
        popupContainer.alpha = 0;
        [vc.view addSubview:popupContainer];

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 15, 270, 35)];
        titleLabel.text = @"⚡ Speed Hack";
        titleLabel.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
        titleLabel.font = [UIFont boldSystemFontOfSize:22];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        [popupContainer addSubview:titleLabel];

        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(20, 60, 260, 30)];
        slider.minimumValue = 0.1f;
        slider.maximumValue = 20.0f;
        slider.value = speedMultiplier;
        slider.minimumTrackTintColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0];
        slider.maximumTrackTintColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:0.5];
        slider.thumbTintColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0];
        [popupContainer addSubview:slider];

        UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 100, 270, 30)];
        valueLabel.text = [NSString stringWithFormat:@"Speed: %.1fx", speedMultiplier];
        valueLabel.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.5 alpha:1.0];
        valueLabel.font = [UIFont boldSystemFontOfSize:18];
        valueLabel.textAlignment = NSTextAlignmentCenter;
        [popupContainer addSubview:valueLabel];

        UILabel *infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 135, 270, 50)];
        infoLabel.text = @"Slide to adjust speed multiplier";
        infoLabel.textColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:0.7];
        infoLabel.font = [UIFont systemFontOfSize:12];
        infoLabel.textAlignment = NSTextAlignmentCenter;
        infoLabel.numberOfLines = 2;
        [popupContainer addSubview:infoLabel];

        SliderController *controller = [[SliderController alloc] init];
        controller.slider = slider;
        controller.valueLabel = valueLabel;
        [slider addTarget:controller action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];

        menuWindow.rootViewController = vc;
        
        // Spring pop-up animation
        [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.8 options:UIViewAnimationOptionCurveEaseOut animations:^{
            popupContainer.transform = CGAffineTransformMakeScale(1.0, 1.0);
            popupContainer.alpha = 1.0;
        } completion:nil];
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

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        showSliderMenu();
    });
}
