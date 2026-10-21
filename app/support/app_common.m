#import "app_common.h"
#import "ui_theme.h"
#import <QuartzCore/QuartzCore.h>
/* five taps is the established gesture for a hidden screen, and nothing else in
   this app reacts to a repeated tap, so it cannot shadow a real control */
#define SHIRO_DEV_MENU_TAPS 5

BOOL ShiroDevMenuEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:SHIRO_DEV_MENU_KEY];
}

void ShiroSetDevMenuEnabled(BOOL enabled) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:enabled forKey:SHIRO_DEV_MENU_KEY];
    [d synchronize];
/* hiding the section has to take its overlay with it, or the frame counter
   outlives the only screen that can turn it off */
    if (!enabled) ShiroFPSOverlaySetEnabled(NO);
}

static int gDevMenuTaps;
static NSTimeInterval gDevMenuLastTap;

int ShiroDevMenuTapsLeft(void) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
/* a tap two seconds after the previous one is a new attempt, not the sixth tap
   of an old one */
    if (now - gDevMenuLastTap > 2.0) gDevMenuTaps = 0;
    gDevMenuLastTap = now;
    if (++gDevMenuTaps >= SHIRO_DEV_MENU_TAPS) {
        gDevMenuTaps = 0;
        return 0;
    }
    return SHIRO_DEV_MENU_TAPS - gDevMenuTaps;
}

void ShiroDevMenuResetTaps(void) {
    gDevMenuTaps = 0;
    gDevMenuLastTap = 0;
}

NSString *ShiroMaskSecret(NSString *value) {
    NSString *raw = [value stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![raw length]) return @"";
/* below nine characters the two ends would be the whole value, so there is
   nothing left to mask and the value is replaced instead */
    if ([raw length] < 9) return @"<hidden>";
    return [NSString stringWithFormat:@"%@...%@",
            [raw substringToIndex:4],
            [raw substringFromIndex:[raw length] - 4]];
}

/* one window above the app, so a push or a rotation cannot take it away and
   nothing it measures is moved by its presence */
@interface ShiroFPSOverlay : NSObject {
    UIWindow        *_window;
    UILabel         *_label;
    CADisplayLink   *_link;
    NSTimeInterval   _windowStart;
    NSUInteger       _frames;
}
+ (ShiroFPSOverlay *)shared;
- (void)setEnabled:(BOOL)enabled;
@end

@implementation ShiroFPSOverlay

+ (ShiroFPSOverlay *)shared {
    static ShiroFPSOverlay *shared;
    if (!shared) shared = [[ShiroFPSOverlay alloc] init];
    return shared;
}

- (void)tick:(CADisplayLink *)link {
    NSTimeInterval now = link.timestamp;
    if (_windowStart == 0) {
        _windowStart = now;
        _frames = 0;
        return;
    }
    ++_frames;
    NSTimeInterval span = now - _windowStart;
    if (span < 0.5) return;
    _label.text = [NSString stringWithFormat:@" %.0f fps ", (double)_frames / span];
    _windowStart = now;
    _frames = 0;
}

- (void)setEnabled:(BOOL)enabled {
    if (!enabled) {
        [_link invalidate];
        [_link release];
        _link = nil;
        _window.hidden = YES;
        [_label release];
        _label = nil;
        [_window release];
        _window = nil;
        return;
    }
    if (_window) return;
/* CADisplayLink is the only clock that counts the frames uikit actually drew,
   and it exists from ios 3.1 */
    CGRect bounds = [[UIScreen mainScreen] bounds];
    _window = [[UIWindow alloc] initWithFrame:
               CGRectMake(bounds.size.width - 76.0f, 2.0f, 74.0f, 18.0f)];
    _window.backgroundColor = [UIColor clearColor];
    _window.userInteractionEnabled = NO;
    _window.windowLevel = UIWindowLevelStatusBar + 1.0f;
    _label = [[UILabel alloc] initWithFrame:_window.bounds];
    _label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55f];
    _label.textColor = [UIColor colorWithRed:0.4f green:1.0f blue:0.5f alpha:1.0f];
    _label.font = [UIFont boldSystemFontOfSize:11.0f];
    _label.textAlignment = NSTextAlignmentRight;
    _label.text = @" -- fps ";
    [_window addSubview:_label];
    _window.hidden = NO;
    _windowStart = 0;
    _frames = 0;
    _link = [[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)] retain];
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

@end

BOOL ShiroFPSOverlayEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:SHIRO_FPS_OVERLAY_KEY];
}

void ShiroFPSOverlaySetEnabled(BOOL enabled) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:enabled forKey:SHIRO_FPS_OVERLAY_KEY];
    [d synchronize];
    [[ShiroFPSOverlay shared] setEnabled:enabled];
}

NSString *ShiroFormatBytes(unsigned long long value) {
    double amount = (double)value;
    NSArray *units = ShiroLanguageIsRussian()
        ? [NSArray arrayWithObjects:@"Б", @"КБ", @"МБ", @"ГБ", @"ТБ", nil]
        : [NSArray arrayWithObjects:@"B", @"KB", @"MB", @"GB", @"TB", nil];
    NSUInteger unit = 0;
    while (amount >= 1024.0 && unit + 1 < [units count]) {
        amount /= 1024.0;
        unit++;
    }
    NSString *number = [NSString stringWithFormat:(amount >= 10.0 || unit == 0)
        ? @"%.0f" : @"%.1f", amount];
    if (ShiroLanguageIsRussian())
        number = [number stringByReplacingOccurrencesOfString:@"." withString:@","];
    return [NSString stringWithFormat:@"%@ %@", number, [units objectAtIndex:unit]];
}

/* link speeds are quoted in bits, so the tiles read like the carrier's plan.
   the unit follows the amount: a fixed kbit/s rounded a quiet keepalive to 0 */
NSString *ShiroFormatRate(double bytesPerSecond) {
    static NSString *const units[] = { @"bit/s", @"Kbit/s", @"Mbit/s", @"Gbit/s" };
    double amount = bytesPerSecond > 0.0 ? bytesPerSecond * 8.0 : 0.0;
    size_t unit = 0;
    while (amount >= 1000.0 && unit + 1 < sizeof units / sizeof units[0]) {
        amount /= 1000.0;
        unit++;
    }
    NSString *number = [NSString stringWithFormat:(unit == 0 || amount >= 10.0)
        ? @"%.0f" : @"%.1f", amount];
    if (ShiroLanguageIsRussian())
        number = [number stringByReplacingOccurrencesOfString:@"." withString:@","];
    return [NSString stringWithFormat:@"%@ %@", number, ShiroLocalizedText(units[unit])];
}



NSString *ShiroAboutTLSMode(void) {
    return ShiroLocalizedText(@"OpenSSL, certificate chain and hostname verification");
}
