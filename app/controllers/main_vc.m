#import "app_common.h"
#import "home_view.h"
#import "boykisser_field.h"
#import "ui_theme.h"
#import "crash_report.h"
#import "app_log.h"
#import "shiro_menus.h"
#import <objc/message.h>

@interface ShiroMainController () {
    ShiroHomeView *_home;
    ShiroBoykisserField *_foxes;
    ShiroControl *_control;
    NSTimer *_timer;
    NSDictionary *_snapshot;
    BOOL _busy;
    BOOL _visible;
    NSInteger _reportedState;
    NSString *_reportedError;
}
@end
@implementation ShiroMainController
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_foxes stop]; [_foxes release];
    [_reportedError release];
    [_timer invalidate]; [_timer release]; [_snapshot release]; [_home release]; [_control release];
    [super dealloc];
}
- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds] autorelease];
    self.view = root;
    ShiroApplyScreenChrome(root);
    _foxes = [[ShiroBoykisserField alloc] initWithFrame:root.bounds spriteName:@"shiro_fox"];
    _foxes.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [root addSubview:_foxes];
    _home = [[ShiroHomeView alloc] initWithFrame:root.bounds];
    _home.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [root addSubview:_home];
    [_home->gear addTarget:self action:@selector(settingsPressed) forControlEvents:UIControlEventTouchUpInside];
    [_home->stats addTarget:self action:@selector(statsPressed) forControlEvents:UIControlEventTouchUpInside];
    [_home->power addTarget:self action:@selector(togglePressed) forControlEvents:UIControlEventTouchUpInside];
    [_home->serverCard addTarget:self action:@selector(accountPressed) forControlEvents:UIControlEventTouchUpInside];
    [_home setServerTitle:@"Cloudflare WARP" subtitle:ShiroLocalizedText(@"Automatic endpoint") icon:[UIImage imageNamed:@"cloudflare.png"] isFlag:YES];
    [_home setProtocolLine:@"WireGuard · WARP"];
    _home->state.text = ShiroLocalizedText(@"Disconnected");
}
- (void)viewDidUnload {
    [self deactivate];
    [_foxes stop];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_foxes release]; _foxes = nil;
    [_home release]; _home = nil;
    [_control release]; _control = nil;
    [super viewDidUnload];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    _reportedState = -1;
    _control = [[ShiroControl alloc] initWithSocketPath:SHIRO_SOCK];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(appearanceChanged:) name:ShiroThemeDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(appearanceChanged:) name:ShiroLanguageDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(activate) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(deactivate) name:UIApplicationWillResignActiveNotification object:nil];
}
- (void)appearanceChanged:(NSNotification *)note {
    if (!self.isViewLoaded) return;
    ShiroApplyScreenChrome(self.view); [_home applyTheme]; [_home relocalize]; [self updateHome:nil];
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; _home.frame = self.view.bounds; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; _visible = YES; [self activate]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; _visible = NO; [self deactivate]; }
- (void)activate {
    if (!_visible) return;
    BOOL falling = ![[NSUserDefaults standardUserDefaults] objectForKey:@"ShiroFallingFoxes"] || [[NSUserDefaults standardUserDefaults] boolForKey:@"ShiroFallingFoxes"];
    _foxes.hidden = !falling;
    if (falling) [_foxes start]; else [_foxes stop];
    if (_timer) return;
    [_home->power setRunning:YES];
    _timer = [[NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(refresh) userInfo:nil repeats:YES] retain];
    [self refresh];
}
- (void)deactivate {
    /* keep the sprites visible while the next screen covers the home view */
    [_foxes setPaused:YES];
    [_timer invalidate]; [_timer release]; _timer = nil;
    [_home->power setRunning:NO];
}
- (void)refresh { [self command:@"status"]; }
- (void)command:(NSString *)command {
    if (_busy) return;
    _busy = YES;
    [_control request:[NSDictionary dictionaryWithObject:command forKey:@"command"] reply:^(NSDictionary *reply, NSString *error) {
        _busy = NO;
        if (!error) { [_snapshot release]; _snapshot = [reply copy]; }
        [self updateHome:error];
    }];
}
- (void)updateHome:(NSString *)error {
    NSInteger state = [[_snapshot objectForKey:@"state"] integerValue];
    NSString *failure = error ?: [_snapshot objectForKey:@"lastError"] ?: @"";
    if (state != _reportedState || ![_reportedError isEqualToString:failure]) {
        ShiroAppLog(@"WARP state=%ld %@", (long)state, failure.length ? failure : @"ok");
        _reportedState = state;
        [_reportedError release]; _reportedError = [failure copy];
    }
    NSArray *labels = [NSArray arrayWithObjects:@"Disconnected", @"Registering WARP account", @"Connecting", @"Connected", @"Connection failed", nil];
    NSArray *keys = [NSArray arrayWithObjects:@"idle", @"connecting", @"connecting", @"connected", @"error", nil];
    if (state < 0 || state >= (NSInteger)labels.count) state = 4;
    [_home->power setStateKey:error ? @"error" : [keys objectAtIndex:state]];
    _home->state.text = ShiroLocalizedText(error ? @"Daemon is unreachable" : [labels objectAtIndex:state]);
    NSString *detail = error ?: [_snapshot objectForKey:@"lastError"];
    if (!detail.length && state == 3) {
        detail = [NSString stringWithFormat:@"↓ %@   ↑ %@", ShiroFormatBytes([[_snapshot objectForKey:@"bytesIn"] unsignedLongLongValue]), ShiroFormatBytes([[_snapshot objectForKey:@"bytesOut"] unsignedLongLongValue])];
    }
    SetStatusDefault(_home->detail, ShiroHumanReadableError(detail ?: @""));
    _home->power.accessibilityLabel = ShiroLocalizedText(@"Connect");
    _home->power.accessibilityValue = _home->state.text;
}
- (void)togglePressed {
    NSInteger state = [[_snapshot objectForKey:@"state"] integerValue];
    [self command:state == 4 ? @"retry" : [[_snapshot objectForKey:@"enabled"] boolValue] ? @"disconnect" : @"connect"];
}
- (void)present:(UIViewController *)controller {
    controller.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closePresented)] autorelease];
    UINavigationController *nav = [[[UINavigationController alloc] initWithRootViewController:controller] autorelease];
    StyleNavBarClassic(nav); ShiroPresentModal(self, nav);
}
- (void)closePresented { ShiroDismissModal(self, nil); }
- (void)settingsPressed { [self present:[[[ShiroSettingsController alloc] init] autorelease]]; }
- (void)statsPressed { [self present:[[[ShiroStatisticsController alloc] init] autorelease]]; }
- (void)accountPressed {
    [self present:[[[ShiroAccountVC alloc] initWithControl:_control] autorelease]];
}
@end
