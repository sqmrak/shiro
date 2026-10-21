#import "app_common.h"
#import "ui_theme.h"
#import "crash_report.h"
#import "app_log.h"
#import <objc/message.h>
@interface ShiroAppDelegate : NSObject <UIApplicationDelegate> {
    UIWindow *_window;
}
@property (nonatomic, retain) UIWindow *window;
@end
@implementation ShiroAppDelegate
@synthesize window = _window;
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    InitPalette();
    _window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _window.backgroundColor = kBG;
    ShiroMainController *home = [[[ShiroMainController alloc] init] autorelease];
    _window.rootViewController = home;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:ShiroThemeDidChangeNotification object:nil];
    [_window makeKeyAndVisible];
    [self themeChanged:nil];
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{ ShiroCrashLaunchComplete(); }];
    [CATransaction commit];
    if (ShiroDevMenuEnabled() && ShiroFPSOverlayEnabled()) ShiroFPSOverlaySetEnabled(YES);
    return YES;
}
- (void)themeChanged:(NSNotification *)note {
    _window.backgroundColor = kBG;
    ShiroAppLog(@"appearance light=%d", ShiroThemeIsLight());
    BOOL modern = [UIViewController instancesRespondToSelector:NSSelectorFromString(@"setNeedsStatusBarAppearanceUpdate")];
    UIStatusBarStyle style = ShiroThemeIsLight() ? UIStatusBarStyleDefault : (UIStatusBarStyle)(modern ? 1 : 2);
    [[UIApplication sharedApplication] setStatusBarStyle:style animated:NO];
    SEL selector = NSSelectorFromString(@"setOverrideUserInterfaceStyle:");
    if ([_window respondsToSelector:selector]) ((void (*)(id, SEL, NSInteger))objc_msgSend)(_window, selector, ShiroThemeIsLight() ? 1 : 2);
}
- (void)applicationDidBecomeActive:(UIApplication *)application { ShiroAppLog(@"lifecycle active"); }
- (void)applicationWillResignActive:(UIApplication *)application { ShiroAppLog(@"lifecycle inactive"); }
- (void)applicationDidEnterBackground:(UIApplication *)application { ShiroAppLog(@"lifecycle background"); }
- (void)applicationWillTerminate:(UIApplication *)application { ShiroAppLog(@"lifecycle terminate"); }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [_window release]; [super dealloc]; }
@end
int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [[NSUserDefaults standardUserDefaults] registerDefaults:
        [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:ShiroLanguageEnglish] forKey:SHIRO_LANGUAGE_KEY]];
    ShiroCrashInstall(); ShiroLocalizationInstall();
    ShiroAppLog(@"launch version=%@ ios=%@ safe_mode=%d", SHIRO_VERSION, [[UIDevice currentDevice] systemVersion], ShiroCrashSafeMode());
    int result = UIApplicationMain(argc, argv, nil, @"ShiroAppDelegate");
    [pool drain]; return result;
}
