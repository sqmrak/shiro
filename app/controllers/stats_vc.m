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
/* the rates of the last minute and a half, one sample a second, as in the android build */
#define STATS_HISTORY 90

/* download and upload rate over a faint grid, two filled lines. the lines are drawn in from the
   left once, when the screen opens */
@interface ShiroThroughputView : UIView {
    NSArray *_down;
    NSArray *_up;
    CGFloat _reveal;
    CADisplayLink *_link;
    CFTimeInterval _started;
}
- (void)setDown:(NSArray *)down up:(NSArray *)up;
- (double)peak;
- (void)playReveal;
@end

@implementation ShiroThroughputView

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
        _reveal = 1.0f;
    }
    return self;
}

- (void)dealloc {
    [_link invalidate];
    [_down release];
    [_up release];
    [super dealloc];
}

- (void)setDown:(NSArray *)down up:(NSArray *)up {
    [_down release];
    [_up release];
    _down = [down copy];
    _up = [up copy];
    [self setNeedsDisplay];
}

- (double)peak {
    double peak = 0.0;
    for (NSNumber *value in _down) peak = MAX(peak, [value doubleValue]);
    for (NSNumber *value in _up) peak = MAX(peak, [value doubleValue]);
    return peak;
}

/* a gentle cubic deceleration over 700 ms, the sweep curve of the android build */
- (void)playReveal {
    [_link invalidate];
    _reveal = 0.0f;
    _started = CACurrentMediaTime();
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(revealStep:)];
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)revealStep:(CADisplayLink *)link {
    double t = (CACurrentMediaTime() - _started) / 0.7;
    if (t >= 1.0) {
        _reveal = 1.0f;
        [link invalidate];
        _link = nil;
    } else {
        double rest = 1.0 - t;
        _reveal = (CGFloat)(1.0 - rest * rest * rest);
    }
    [self setNeedsDisplay];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    /* the link holds this view, so it goes when the view leaves the screen */
    if (!self.window && _link) {
        [_link invalidate];
        _link = nil;
        _reveal = 1.0f;
    }
}

- (void)plot:(NSArray *)samples peak:(double)peak color:(UIColor *)color in:(CGContextRef)ctx {
    NSUInteger count = [samples count];
    if (count < 2) return;
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height, pad = 2.0f;
    CGFloat step = w / (STATS_HISTORY - 1);
    /* the newest sample sits at the right edge, a short history starts part way across */
    CGFloat x0 = w - step * (CGFloat)(count - 1);
    CGMutablePathRef line = CGPathCreateMutable();
    CGMutablePathRef area = CGPathCreateMutable();
    for (NSUInteger i = 0; i < count; ++i) {
        CGFloat x = x0 + step * (CGFloat)i;
        CGFloat y = h - pad - (h - 2.0f * pad) * (CGFloat)([[samples objectAtIndex:i] doubleValue] / peak);
        if (i == 0) {
            CGPathMoveToPoint(line, NULL, x, y);
            CGPathMoveToPoint(area, NULL, x, h);
            CGPathAddLineToPoint(area, NULL, x, y);
        } else {
            CGPathAddLineToPoint(line, NULL, x, y);
            CGPathAddLineToPoint(area, NULL, x, y);
        }
    }
    CGPathAddLineToPoint(area, NULL, w, h);
    CGPathCloseSubpath(area);
    CGContextAddPath(ctx, area);
    CGContextSetFillColorWithColor(ctx, [color colorWithAlphaComponent:0.18f].CGColor);
    CGContextFillPath(ctx);
    CGContextAddPath(ctx, line);
    CGContextSetStrokeColorWithColor(ctx, color.CGColor);
    CGContextSetLineWidth(ctx, 2.0f);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    CGContextStrokePath(ctx);
    CGPathRelease(line);
    CGPathRelease(area);
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGContextSetLineWidth(ctx, 1.0f);
    CGContextSetStrokeColorWithColor(ctx, [kInkMuted colorWithAlphaComponent:0.25f].CGColor);
    for (int i = 0; i <= 3; ++i) {
        CGFloat y = floorf(h * (CGFloat)i / 3.0f) + 0.5f;
        CGContextMoveToPoint(ctx, 0.0f, y);
        CGContextAddLineToPoint(ctx, w, y);
        CGContextStrokePath(ctx);
    }
    double peak = MAX([self peak], 1024.0);
    CGContextSaveGState(ctx);
    CGContextClipToRect(ctx, CGRectMake(0.0f, 0.0f, w * _reveal, h));
    [self plot:_down peak:peak color:kConnOn in:ctx];
    [self plot:_up peak:peak color:kAccentBlue in:ctx];
    CGContextRestoreGState(ctx);
}

@end

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
    ShiroCardView *_chartCard;
    UILabel *_chartTitle;
    UILabel *_chartPeak;
    ShiroThroughputView *_chart;
    UIView *_swatch[2];
    UILabel *_legend[2];
    UILabel *_span;
    ShiroCardView *_detailCard;
    UILabel *_detailTitle;
    UILabel *_detailCaption[4];
    UILabel *_detailValue[4];
    NSMutableArray *_downHistory;
    NSMutableArray *_upHistory;
    double _peakDown;
    double _peakUp;
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
    [_chartCard release];
    [_chartTitle release];
    [_chartPeak release];
    [_chart release];
    for (int i = 0; i < 2; ++i) {
        [_swatch[i] release];
        [_legend[i] release];
    }
    [_span release];
    [_detailCard release];
    [_detailTitle release];
    for (int i = 0; i < 4; ++i) {
        [_detailCaption[i] release];
        [_detailValue[i] release];
    }
    [_downHistory release];
    [_upHistory release];
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

    _downHistory = [[NSMutableArray alloc] init];
    _upHistory = [[NSMutableArray alloc] init];

    _chartCard = [[ShiroCardView alloc] initWithFrame:CGRectZero];
    [_scroll addSubview:_chartCard];
    _chartTitle = [ShiroCardLabel(_chartCard, ShiroFontBody(14.0f, YES), kInkMuted,
                                  NSTextAlignmentLeft) retain];
    _chartPeak = [ShiroCardLabel(_chartCard, ShiroFontBody(13.0f, NO), kInkMuted,
                                 NSTextAlignmentRight) retain];
    _chart = [[ShiroThroughputView alloc] initWithFrame:CGRectZero];
    [_chartCard addSubview:_chart];
    for (int i = 0; i < 2; ++i) {
        _swatch[i] = [[UIView alloc] initWithFrame:CGRectZero];
        _swatch[i].layer.cornerRadius = 4.0f;
        [_chartCard addSubview:_swatch[i]];
        _legend[i] = [ShiroCardLabel(_chartCard, ShiroFontBody(12.0f, NO), kInkMuted,
                                     NSTextAlignmentLeft) retain];
    }
    _span = [ShiroCardLabel(_chartCard, ShiroFontBody(12.0f, NO), kInkMuted,
                            NSTextAlignmentRight) retain];

    _detailCard = [[ShiroCardView alloc] initWithFrame:CGRectZero];
    [_scroll addSubview:_detailCard];
    _detailTitle = [ShiroCardLabel(_detailCard, ShiroFontBody(14.0f, YES), kInkMuted,
                                   NSTextAlignmentLeft) retain];
    for (int i = 0; i < 4; ++i) {
        _detailCaption[i] = [ShiroCardLabel(_detailCard, ShiroFontBody(15.0f, NO), kInk,
                                            NSTextAlignmentLeft) retain];
        _detailValue[i] = [ShiroCardLabel(_detailCard, ShiroFontBody(15.0f, YES), kInkMuted,
                                          NSTextAlignmentRight) retain];
    }

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
    [_chartCard restyle];
    [_detailCard restyle];
    _chartTitle.textColor = _chartPeak.textColor = _span.textColor = kInkMuted;
    _chartTitle.text = ShiroLocalizedText(@"Throughput");
    _span.text = [NSString stringWithFormat:ShiroLocalizedText(@"Last %d seconds"), STATS_HISTORY];
    _swatch[0].backgroundColor = kConnOn;
    _swatch[1].backgroundColor = kAccentBlue;
    _legend[0].text = ShiroLocalizedText(@"Download");
    _legend[1].text = ShiroLocalizedText(@"Upload");
    _legend[0].textColor = _legend[1].textColor = kInkMuted;
    _detailTitle.textColor = kInkMuted;
    _detailTitle.text = ShiroLocalizedText(@"Session");
    NSArray *captions = [NSArray arrayWithObjects:@"Average speed", @"Peak download", @"Peak upload", @"Total transferred", nil];
    for (int i = 0; i < 4; ++i) {
        _detailCaption[i].textColor = kInk;
        _detailCaption[i].text = ShiroLocalizedText([captions objectAtIndex:(NSUInteger)i]);
        _detailValue[i].textColor = kInkMuted;
    }
    [_chart setNeedsDisplay];
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

    _chartCard.frame = CGRectMake(x, y, col, 196.0f);
    _chartTitle.frame = CGRectMake(16.0f, 12.0f, col - 140.0f, 22.0f);
    _chartPeak.frame = CGRectMake(col - 124.0f, 12.0f, 108.0f, 22.0f);
    _chart.frame = CGRectMake(16.0f, 44.0f, col - 32.0f, 110.0f);
    CGFloat lx = 16.0f;
    for (int i = 0; i < 2; ++i) {
        _swatch[i].frame = CGRectMake(lx, 168.0f, 8.0f, 8.0f);
        CGFloat lw = ShiroTextWidth(_legend[i].text, _legend[i].font) + 4.0f;
        _legend[i].frame = CGRectMake(lx + 13.0f, 161.0f, lw, 22.0f);
        lx += 13.0f + lw + 14.0f;
    }
    _span.frame = CGRectMake(lx, 161.0f, MAX(40.0f, col - 16.0f - lx), 22.0f);
    y += 196.0f + kStatsGap;

    _detailCard.frame = CGRectMake(x, y, col, 184.0f);
    _detailTitle.frame = CGRectMake(16.0f, 12.0f, col - 32.0f, 22.0f);
    for (int i = 0; i < 4; ++i) {
        CGFloat ry = 42.0f + 32.0f * (CGFloat)i;
        _detailCaption[i].frame = CGRectMake(16.0f, ry, floorf(col * 0.5f) - 16.0f, 24.0f);
        _detailValue[i].frame = CGRectMake(floorf(col * 0.5f), ry, col - floorf(col * 0.5f) - 16.0f, 24.0f);
    }
    y += 184.0f + kStatsGap;

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
    [_chart setDown:_downHistory up:_upHistory];
    double peak = [_chart peak];
    _chartPeak.text = peak > 0.0 ? [NSString stringWithFormat:ShiroLocalizedText(@"Peak %@"), ShiroFormatRate(peak)] : @"";
    uint64_t total = _down + _up;
    long age = _uptimeKnown ? _uptime + (long)(CACurrentMediaTime() - _uptimeAt) : 0;
    _detailValue[0].text = connected && age > 0 && total > 0 && _trafficKnown ? ShiroFormatRate((double)total / (double)age) : @"—";
    _detailValue[1].text = _peakDown > 0.0 ? ShiroFormatRate(_peakDown) : @"—";
    _detailValue[2].text = _peakUp > 0.0 ? ShiroFormatRate(_peakUp) : @"—";
    _detailValue[3].text = _trafficKnown && total > 0 ? ShiroFormatBytes(total) : @"—";
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
    [_chart playReveal];
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
    if (known && _trafficKnown && _sampleAt > 0.0 && now - _sampleAt > 0.2) {
        [_downHistory addObject:[NSNumber numberWithDouble:_downRate]];
        [_upHistory addObject:[NSNumber numberWithDouble:_upRate]];
        if ([_downHistory count] > STATS_HISTORY) [_downHistory removeObjectAtIndex:0];
        if ([_upHistory count] > STATS_HISTORY) [_upHistory removeObjectAtIndex:0];
        _peakDown = MAX(_peakDown, _downRate);
        _peakUp = MAX(_peakUp, _upRate);
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
