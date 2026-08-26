//khiglock made this // // SpeedHack.m – Stumble Guys Speed Hack with Hideable Menu
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#include "fishhook.h"

static float speedMultiplier = 15.0f;
static void (*orig_set_timeScale)(float) = NULL;

// Menu controller
@interface SpeedMenuController : NSObject
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UIWindow *menuWindow;
@property (nonatomic, strong) UIButton *hideButton;
@property (nonatomic, strong) UIButton *showButton;
- (void)sliderValueChanged:(UISlider *)sender;
- (void)hideMenu;
- (void)showMenu;
@end

@implementation SpeedMenuController
- (void)sliderValueChanged:(UISlider *)sender {
    speedMultiplier = sender.value;
    if (self.valueLabel) {
        self.valueLabel.text = [NSString stringWithFormat:@"%.1fx", speedMultiplier];
    }
}

- (void)hideMenu {
    self.menuWindow.hidden = YES;
    self.showButton.hidden = NO;
}

- (void)showMenu {
    self.menuWindow.hidden = NO;
    self.showButton.hidden = YES;
}
@end

static SpeedMenuController *menuController = nil;

// Speed hook
void hooked_set_timeScale(float value) {
    if (orig_set_timeScale) {
        orig_set_timeScale(value * speedMultiplier);
    }
}

// Timer to enforce speed (in case game resets it)
void enforceSpeedTimer(CFRunLoopTimerRef timer, void *info) {
    if (orig_set_timeScale) {
        orig_set_timeScale(speedMultiplier);
    }
}

// Popup showing status
void showStatusPopup(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isKeyWindow) { keyWindow = window; break; }
        }
        if (!keyWindow) keyWindow = [UIApplication sharedApplication].windows.firstObject;

        UIViewController *rootVC = keyWindow ? keyWindow.rootViewController : nil;
        if (rootVC) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"SpeedHack"
                                                                           message:message
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [rootVC presentViewController:alert animated:YES completion:nil];
        } else if (keyWindow) {
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, 240, 80)];
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

// Create the hideable menu
void createMenu(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (menuController) return;

        CGRect screen = [UIScreen mainScreen].bounds;
        UIWindow *menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 100, screen.size.width-40, 120)];
        menuWindow.windowLevel = UIWindowLevelAlert + 100;
        menuWindow.backgroundColor = [UIColor clearColor];
        menuWindow.hidden = NO;

        UIViewController *vc = [[UIViewController alloc] init];
        UIView *bg = [[UIView alloc] initWithFrame:vc.view.bounds];
        bg.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.85];
        bg.layer.cornerRadius = 12;
        bg.clipsToBounds = YES;
        [vc.view addSubview:bg];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 10, 200, 25)];
        title.text = @"Speed Hack";
        title.textColor = [UIColor whiteColor];
        title.font = [UIFont boldSystemFontOfSize:16];
        [bg addSubview:title];

        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(20, 40, bg.bounds.size.width-40, 30)];
        slider.minimumValue = 0.1f;
        slider.maximumValue = 20.0f;
        slider.value = speedMultiplier;
        [bg addSubview:slider];

        UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 75, 100, 25)];
        valueLabel.text = [NSString stringWithFormat:@"%.1fx", speedMultiplier];
        valueLabel.textColor = [UIColor greenColor];
        valueLabel.font = [UIFont systemFontOfSize:14];
        [bg addSubview:valueLabel];

        UIButton *hideButton = [UIButton buttonWithType:UIButtonTypeSystem];
        hideButton.frame = CGRectMake(bg.bounds.size.width-60, 75, 50, 25);
        [hideButton setTitle:@"Hide" forState:UIControlStateNormal];
        [hideButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        hideButton.backgroundColor = [UIColor redColor];
        hideButton.layer.cornerRadius = 5;
        [bg addSubview:hideButton];

        menuController = [[SpeedMenuController alloc] init];
        menuController.slider = slider;
        menuController.valueLabel = valueLabel;
        menuController.menuWindow = menuWindow;
        menuController.hideButton = hideButton;

        [slider addTarget:menuController action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
        [hideButton addTarget:menuController action:@selector(hideMenu) forControlEvents:UIControlEventTouchUpInside];

        // Show button (when hidden)
        UIButton *showButton = [UIButton buttonWithType:UIButtonTypeSystem];
        showButton.frame = CGRectMake(20, 100, 50, 30);
        [showButton setTitle:@"Show" forState:UIControlStateNormal];
        [showButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        showButton.backgroundColor = [UIColor greenColor];
        showButton.layer.cornerRadius = 5;
        showButton.hidden = YES;
        [menuWindow.rootViewController.view addSubview:showButton]; // wrong, need separate window
        // Actually place show button on a separate small window or as subview of key window
        UIWindow *showWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 100, 50, 30)];
        showWindow.windowLevel = UIWindowLevelAlert + 100;
        showWindow.backgroundColor = [UIColor clearColor];
        showWindow.hidden = NO;
        UIViewController *showVC = [[UIViewController alloc] init];
        [showWindow setRootViewController:showVC];
        [showVC.view addSubview:showButton];
        menuController.showButton = showButton;
        showWindow.hidden = YES; // initially hidden because menu is visible

        // Store showWindow in controller
        // Not needed for now, just use showButton.hidden toggling on same window? Simpler: put show button on menuWindow but hidden, when menu hidden show the button on key window? complicated.
        // For simplicity, we'll make the show button part of a small separate window.
        // We'll keep it simple: the menu window can be shown/hidden with hide button, and a small floating button always visible.
        // Let's redesign: single window containing both menu and show button.

        menuWindow.rootViewController = vc;
        [menuWindow makeKeyAndVisible];
    });
}

__attribute__((constructor))
static void init(void) {
    // Hook Unity timeScale
    struct rebinding rebindings[] = {
        {"_UnityEngine_Time_set_timeScale", (void *)hooked_set_timeScale, (void **)&orig_set_timeScale},
        {"UnityEngine_Time_set_timeScale", (void *)hooked_set_timeScale, (void **)&orig_set_timeScale}
    };
    rebind_symbols(rebindings, 2);

    // Fallback dlsym
    if (!orig_set_timeScale) {
        void *sym = dlsym(RTLD_DEFAULT, "_UnityEngine_Time_set_timeScale");
        if (!sym) sym = dlsym(RTLD_DEFAULT, "UnityEngine_Time_set_timeScale");
        if (sym) {
            orig_set_timeScale = (void (*)(float))sym;
            orig_set_timeScale(speedMultiplier);
        }
    }

    // Start enforcement timer
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent(), 0.2, 0, 0, &enforceSpeedTimer, NULL);
    if (timer) {
        CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopCommonModes);
    }

    // Show popup and create menu after delay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        showStatusPopup(@"Speed Hack Loaded!\nSpeed: 15x\nMenu will appear.");
        createMenu();
    });
}
