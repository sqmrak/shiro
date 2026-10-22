#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import "app_common.h"
#import "control_client.h"
#import "selection_mark.h"
#import "ui_theme.h"
#import "crash_report.h"
#import "card_kit.h"

enum {
    ShiroStatsState = 0,
    ShiroStatsServer,
    ShiroStatsUptime,
    ShiroStatsDown,
    ShiroStatsUp,
    ShiroStatsDownRate,
    ShiroStatsUpRate,
    ShiroStatsSessionRows
};

static NSString *ShiroStatsUptimeText(long seconds) {
    if (seconds < 0) return nil;
    long h = seconds / 3600;
    long m = (seconds % 3600) / 60;
    long s = seconds % 60;
    if (h > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", h, m, s];
    return [NSString stringWithFormat:@"%ld:%02ld", m, s];
}

static const CGFloat kStatsGap = 12.0f;

@implementation ShiroStatisticsController {
    UIScrollView *_scroll;
    ShiroCardView *_hero;
    UIView *_heroDot;
    UILabel *_heroState;
    UILabel *_heroUptime;
    UILabel *_heroServer;
    ShiroCardView *_downCard;
    ShiroCardView *_upCard;
    UIImageView *_downIcon;
    UIImageView *_upIcon;
    UILabel *_downCaption;
    UILabel *_upCaption;
    UILabel *_downValue;
    UILabel *_upValue;
    UILabel *_downRateLabel;
    UILabel *_upRateLabel;
    ShiroControl *_ctl;
    NSTimer *_timer;
    NSUInteger _generation;
    BOOL _polling;
    CFTimeInterval _pollAt;
    NSString *_state;
    NSString *_serverName;
    long _uptime;
    CFTimeInterval _uptimeAt;
    BOOL _uptimeKnown;
    BOOL _trafficKnown;
    uint64_t _up;
    uint64_t _down;
    double _upRate;
    double _downRate;
    CFTimeInterval _sampleAt;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_timer invalidate];
    [_scroll release];
    [_hero release];
    [_heroDot release];
    [_heroState release];
    [_heroUptime release];
    [_heroServer release];
    [_downCard release];
    [_upCard release];
    [_downIcon release];
    [_upIcon release];
    [_downCaption release];
    [_upCaption release];
    [_downValue release];
    [_upValue release];
    [_downRateLabel release];
    [_upRateLabel release];
    [_ctl release];
    [_state release];
    [_serverName release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = ShiroLocalizedText(@"Statistics");
    _ctl = [[ShiroControl alloc] initWithSocketPath:SHIRO_SOCK];
    _state = [@"idle" copy];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
        ((void (*)(id, SEL, NSUInteger))objc_msgSend)(self, @selector(setEdgesForExtendedLayout:), 0);
    if ([self respondsToSelector:@selector(setAutomaticallyAdjustsScrollViewInsets:)])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setAutomaticallyAdjustsScrollViewInsets:), NO);
    self.navigationItem.leftBarButtonItem =
        [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                       target:self
                                                       action:@selector(donePressed)] autorelease];
    ShiroApplyScreenChrome(self.view);

    _scroll = [[UIScrollView alloc] initWithFrame:ShiroViewBounds(self.view)];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scroll.alwaysBounceVertical = YES;
    _scroll.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_scroll];

    _hero = [[ShiroCardView alloc] initWithFrame:CGRectZero];
    [_scroll addSubview:_hero];
    _heroDot = [[UIView alloc] initWithFrame:CGRectZero];
    _heroDot.layer.cornerRadius = 5.0f;
    [_hero addSubview:_heroDot];
    _heroState = [ShiroCardLabel(_hero, ShiroFontBody(15.0f, YES), kInkMuted,
                                 NSTextAlignmentLeft) retain];
    _heroUptime = [ShiroCardLabel(_hero, ShiroFontDisplay(44.0f), kInk,
                                  NSTextAlignmentLeft) retain];
    _heroUptime.adjustsFontSizeToFitWidth = YES;
    _heroServer = [ShiroCardLabel(_hero, ShiroFontBody(15.0f, NO), kInkMuted,
                                  NSTextAlignmentLeft) retain];
    _heroServer.lineBreakMode = NSLineBreakByTruncatingTail;

    _downCard = [[ShiroCardView alloc] initWithFrame:CGRectZero];
    _upCard = [[ShiroCardView alloc] initWithFrame:CGRectZero];
    [_scroll addSubview:_downCard];
    [_scroll addSubview:_upCard];
    _downIcon = [[UIImageView alloc] initWithFrame:CGRectZero];
    _upIcon = [[UIImageView alloc] initWithFrame:CGRectZero];
    [_downCard addSubview:_downIcon];
    [_upCard addSubview:_upIcon];
    _downCaption = [ShiroCardLabel(_downCard, ShiroFontBody(14.0f, YES), kInkMuted,
                                   NSTextAlignmentLeft) retain];
    _upCaption = [ShiroCardLabel(_upCard, ShiroFontBody(14.0f, YES), kInkMuted,
                                 NSTextAlignmentLeft) retain];
    _downValue = [ShiroCardLabel(_downCard, ShiroFontBody(26.0f, YES), kInk,
                                 NSTextAlignmentLeft) retain];
    _upValue = [ShiroCardLabel(_upCard, ShiroFontBody(26.0f, YES), kInk,
                               NSTextAlignmentLeft) retain];
    _downValue.adjustsFontSizeToFitWidth = YES;
    _upValue.adjustsFontSizeToFitWidth = YES;
    _downRateLabel = [ShiroCardLabel(_downCard, ShiroFontBody(14.0f, NO), kInkMuted,
                                     NSTextAlignmentLeft) retain];
    _upRateLabel = [ShiroCardLabel(_upCard, ShiroFontBody(14.0f, NO), kInkMuted,
                                   NSTextAlignmentLeft) retain];

    [self applyColors];
    [self refreshValues];
    [self layoutStats];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeDidChange:)
                                                 name:ShiroThemeDidChangeNotification object:nil];
}

/* the text, dot and icons take their colours from the palette, which a theme
   switch replaces */
- (void)applyColors {
    [_hero restyle];
    [_downCard restyle];
    [_upCard restyle];
    _heroState.textColor = kInkMuted;
    _heroUptime.textColor = kInk;
    _heroServer.textColor = kInkMuted;
    _downCaption.textColor = _upCaption.textColor = kInkMuted;
    _downValue.textColor = _upValue.textColor = kInk;
    _downRateLabel.textColor = _upRateLabel.textColor = kInkMuted;
    _downCaption.text = ShiroLocalizedText(@"Downloaded");
    _upCaption.text = ShiroLocalizedText(@"Uploaded");
    _downIcon.image = TintedIconNamed(@"glyph-arrow-down.png", 20.0f, kConnOn);
    _upIcon.image = TintedIconNamed(@"glyph-arrow-up.png", 20.0f, kAccentBlue);
}

- (void)themeDidChange:(NSNotification *)n {
    (void)n;
    ShiroApplyScreenChrome(self.view);
    if (self.navigationController) StyleNavBarClassic(self.navigationController);
    [self applyColors];
    [self refreshValues];
    [self layoutStats];
}

- (void)layoutStats {
    CGRect b = ShiroViewBounds(self.view);
    if (b.size.width < 2.0f) return;
    UIEdgeInsets safe = ShiroSafeAreaInsets(self.view);
    CGFloat col = ShiroCardColumnWidth(b.size.width);
    CGFloat x = floorf((b.size.width - col) * 0.5f);
    CGFloat y = 16.0f;

    _hero.frame = CGRectMake(x, y, col, 132.0f);
    _heroDot.frame = CGRectMake(18.0f, 21.0f, 10.0f, 10.0f);
    _heroState.frame = CGRectMake(36.0f, 15.0f, col - 54.0f, 22.0f);
    _heroUptime.frame = CGRectMake(16.0f, 40.0f, col - 32.0f, 52.0f);
    _heroServer.frame = CGRectMake(18.0f, 98.0f, col - 36.0f, 22.0f);
    y += 132.0f + kStatsGap;

    CGFloat half = floorf((col - kStatsGap) * 0.5f);
    CGRect left = CGRectMake(x, y, half, 112.0f);
    CGRect right = CGRectMake(x + col - half, y, half, 112.0f);
    _downCard.frame = left;
    _upCard.frame = right;
    UIView *cards[2] = { _downCard, _upCard };
    UIImageView *icons[2] = { _downIcon, _upIcon };
    UILabel *caps[2] = { _downCaption, _upCaption };
    UILabel *vals[2] = { _downValue, _upValue };
    UILabel *rates[2] = { _downRateLabel, _upRateLabel };
    for (int i = 0; i < 2; ++i) {
        CGFloat w = cards[i].bounds.size.width;
        icons[i].frame = CGRectMake(14.0f, 14.0f, 20.0f, 20.0f);
        caps[i].frame = CGRectMake(40.0f, 13.0f, w - 52.0f, 22.0f);
        vals[i].frame = CGRectMake(14.0f, 44.0f, w - 28.0f, 32.0f);
        rates[i].frame = CGRectMake(14.0f, 80.0f, w - 28.0f, 20.0f);
    }
    y += 112.0f + kStatsGap;

    _scroll.contentSize = CGSizeMake(b.size.width, y + 8.0f + safe.bottom);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _scroll.frame = ShiroViewBounds(self.view);
    [self layoutStats];
}

/* everything that changes once a second is a label: nothing is rebuilt */
- (void)refreshValues {
    BOOL connected = [_state isEqualToString:@"connected"];
    BOOL connecting = [_state isEqualToString:@"connecting"];
    _heroDot.backgroundColor = connected ? kConnOn
        : connecting ? [UIColor colorWithRed:0.95f green:0.65f blue:0.15f alpha:1.0f]
        : kIdleGrey;
    _heroState.text = connected ? ShiroLocalizedText(@"Connected")
        : connecting ? ShiroLocalizedText(@"Connecting") : ShiroLocalizedText(@"Disconnected");
    NSString *uptime = nil;
    if (_uptimeKnown)
        uptime = ShiroStatsUptimeText(_uptime + (long)(CACurrentMediaTime() - _uptimeAt));
    _heroUptime.text = uptime ? uptime : @"—";
    NSString *server = _serverName;
    _heroServer.text = connected && server ? server : (server ? server : @"—");
    _downValue.text = _trafficKnown ? ShiroFormatBytes(_down) : @"—";
    _upValue.text = _trafficKnown ? ShiroFormatBytes(_up) : @"—";
    _downRateLabel.text = _trafficKnown ? ShiroFormatRate(_downRate) : @"—";
    _upRateLabel.text = _trafficKnown ? ShiroFormatRate(_upRate) : @"—";
}

- (void)viewWillAppear:(BOOL)animated {
    ShiroCrashScreen("statistics");
    [super viewWillAppear:animated];
    [_serverName release];
    _serverName = [@"Cloudflare WARP" copy];
    [self refreshValues];
    [self layoutStats];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self poll];
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self
                                            selector:@selector(poll)
                                            userInfo:nil repeats:YES];
}

/* the timer holds this controller, so it goes with the screen */
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_timer invalidate];
    _timer = nil;
    _generation++;
    _polling = NO;
}

- (void)donePressed {
    ShiroDismissModal(self, nil);
}

- (void)setStateText:(NSString *)state {
    [_state release];
    _state = [(state ? state : @"idle") copy];
}

- (void)applyTrafficKnown:(BOOL)known up:(uint64_t)up down:(uint64_t)down {
    CFTimeInterval now = CACurrentMediaTime();
    if (known && _trafficKnown && _sampleAt > 0.0 && now - _sampleAt > 0.2 &&
        up >= _up && down >= _down) {
        _upRate = (double)(up - _up) / (now - _sampleAt);
        _downRate = (double)(down - _down) / (now - _sampleAt);
    } else if (!known) {
        _upRate = _downRate = 0.0;
    }
    _trafficKnown = known;
    _up = up;
    _down = down;
    _sampleAt = known ? now : 0.0;
}

/* one status and one counter request per second at most: a poll still in
   flight when the timer fires again is not doubled up, unless it has been
   silent for long enough that its reply is not coming (a packet tunnel
   extension that restarted never answers its provider message) */
- (void)poll {
    if (_polling) return;
    _polling = YES;
    NSUInteger generation = ++_generation;
    [_ctl request:[NSDictionary dictionaryWithObject:@"status" forKey:@"command"] reply:^(NSDictionary *reply, NSString *error) {
        if (generation != _generation) return;
        _polling = NO;
        NSInteger state = [[reply objectForKey:@"state"] integerValue];
        [self setStateText:!error && state == 3 ? @"connected" : !error && (state == 1 || state == 2) ? @"connecting" : @"idle"];
        _uptimeKnown = !error && state == 3;
        _uptime = [[reply objectForKey:@"uptimeMs"] longLongValue] / 1000;
        _uptimeAt = CACurrentMediaTime();
        [self applyTrafficKnown:!error up:[[reply objectForKey:@"bytesOut"] unsignedLongLongValue] down:[[reply objectForKey:@"bytesIn"] unsignedLongLongValue]];
        [self refreshValues];
        if (error) _heroServer.text = ShiroHumanReadableError(error);
    }];
}
@end
