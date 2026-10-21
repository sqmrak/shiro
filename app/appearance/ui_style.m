#import "ui_theme.h"
#import "crash_report.h"
#include <math.h>
#include <objc/runtime.h>
#include <objc/message.h>

enum { kShiroFrostTag = 9107 };

static char kShiroRasterKey;

/* the veil is the previous screen held still while the palette swaps under it */
static UIView *ShiroThemeVeilForWindow(UIWindow *w) {
    /* snapshotViewAfterScreenUpdates: landed in ios 7 and copies the existing
       render tree instead of rasterizing it again. on a modern phone the
       renderInContext: path allocates a full retina bitmap of the whole window
       on the main thread, and it also flattens a UIVisualEffectView into an
       opaque tile */
    if ([w respondsToSelector:@selector(snapshotViewAfterScreenUpdates:)]) {
        UIView *snap = ((id (*)(id, SEL, BOOL))objc_msgSend)(
            w, @selector(snapshotViewAfterScreenUpdates:), NO);
        if (snap) return [snap retain];
    }

    CGSize size = w.bounds.size;
    UIGraphicsBeginImageContextWithOptions(size, YES, 0.0f);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) {
        UIGraphicsEndImageContext();
        return nil;
    }
    [w.layer renderInContext:ctx];
    UIImage *shot = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!shot) return nil;
    return [[UIImageView alloc] initWithImage:shot];
}

void ShiroThemeCrossfadeWindows(void) {
    /* block animation api landed in ios 4, and this runs on theme switches
       only, never on live palette edits */
    if (![UIView respondsToSelector:@selector(animateWithDuration:animations:completion:)])
        return;
    UIWindow *w = [[UIApplication sharedApplication] keyWindow];
    if (!w) return;
    CGSize size = w.bounds.size;
    if (size.width < 1.0f || size.height < 1.0f) return;

    UIView *veil = ShiroThemeVeilForWindow(w);
    if (!veil) return;
    veil.frame = w.bounds;
    veil.userInteractionEnabled = NO;
    veil.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [w addSubview:veil];
    [UIView animateWithDuration:0.30
                     animations:^{ veil.alpha = 0.0f; }
                     completion:^(BOOL done) {
                         (void)done;
                         [veil removeFromSuperview];
                         [veil release];
                     }];
}

/* runtime lookup keeps font-weight symbols from breaking ios 5 launches */
static UIFont *ShiroSFBold(CGFloat size) {
    if ([UIFont respondsToSelector:@selector(systemFontOfSize:weight:)]) {
        UIFont *f = ((UIFont * (*)(id, SEL, CGFloat, CGFloat))objc_msgSend)(
            [UIFont class], @selector(systemFontOfSize:weight:), size, (CGFloat)0.4);
        if (f) return f;
    }
    return [UIFont boldSystemFontOfSize:size];
}

static UIFont *ShiroSFSemibold(CGFloat size) {
    if ([UIFont respondsToSelector:@selector(systemFontOfSize:weight:)]) {
        UIFont *f = ((UIFont * (*)(id, SEL, CGFloat, CGFloat))objc_msgSend)(
            [UIFont class], @selector(systemFontOfSize:weight:), size, (CGFloat)0.3);
        if (f) return f;
    }
    return [UIFont boldSystemFontOfSize:size];
}

UIFont *ShiroFontTitle(CGFloat size) {
    if (ShiroThemeIsIos26())
        return ShiroSFBold(size);
    if (ShiroThemeIsMaterial()) {
        UIFont *medium = [UIFont fontWithName:@"HelveticaNeue-Medium" size:size];
        return medium ? medium : [UIFont boldSystemFontOfSize:size];
    }
/* the flat bars put this over a light, nearly white ground, where the ultra
   light Helvetica it used to ask for drew a grey hairline that read as a
   disabled title on ios 10. the weight is the one the system bar uses */
    if ([UIFont respondsToSelector:@selector(systemFontOfSize:weight:)])
        return ShiroSFSemibold(size);
    UIFont *medium = [UIFont fontWithName:@"HelveticaNeue-Medium" size:size];
    return medium ? medium : [UIFont boldSystemFontOfSize:size];
}

UIFont *ShiroFontBody(CGFloat size, BOOL semibold) {
    if (ShiroThemeIsIos26())
        return semibold ? ShiroSFBold(size) : ShiroSFSemibold(size);
    if (semibold) {
        UIFont *f = [UIFont fontWithName:@"HelveticaNeue-Medium" size:size];
        if (!f) f = [UIFont boldSystemFontOfSize:size];
        return f;
    }
    return [UIFont systemFontOfSize:size];
}


void ShiroRemoveFrost(UIView *host) {
    if (!host) return;
    UIView *old = [host viewWithTag:kShiroFrostTag];
    if (old) [old removeFromSuperview];
}

static UIColor *FrostTintColor(BOOL lite) {
    BOOL light = ShiroThemeIsLight();
    if (ShiroThemeIsIos26()) {
        return light
            ? [UIColor colorWithWhite:1.0 alpha:lite ? 0.62f : 0.48f]
            : [UIColor colorWithWhite:1.0 alpha:lite ? 0.14f : 0.08f];
    }
    if (lite)
        return light
            ? [UIColor colorWithRed:0.94 green:0.95 blue:0.98 alpha:0.88]
            : [UIColor colorWithRed:0.14 green:0.16 blue:0.22 alpha:0.90];
    return light
        ? [UIColor colorWithRed:0.92 green:0.94 blue:0.98 alpha:0.72]
        : [UIColor colorWithRed:0.12 green:0.14 blue:0.20 alpha:0.78];
}

void ShiroInstallFrostLite(UIView *host) {
    if (!host) return;
    if (!ShiroThemeUsesFrost() && !ShiroThemeIsIos26()) {
        ShiroRemoveFrost(host);
        return;
    }
    UIView *old = [host viewWithTag:kShiroFrostTag];
    if (old && ![old isKindOfClass:[UIToolbar class]] &&
        ![NSStringFromClass([old class]) isEqualToString:@"UIVisualEffectView"]) {
        old.frame = host.bounds;
        old.backgroundColor = FrostTintColor(YES);
        old.layer.cornerRadius = host.layer.cornerRadius;
        return;
    }
    ShiroRemoveFrost(host);
    UIView *v = [[[UIView alloc] initWithFrame:host.bounds] autorelease];
    v.tag = kShiroFrostTag;
    v.userInteractionEnabled = NO;
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    v.backgroundColor = FrostTintColor(YES);
    v.clipsToBounds = YES;
    v.layer.cornerRadius = host.layer.cornerRadius;
    [host insertSubview:v atIndex:0];
}

/* UIVisualEffectView owns its subview list and refuses additions to itself.
   contentView is where anything drawn over the blur has to live; the selector
   is looked up rather than called directly because the armv7 sdk predates it */
UIView *ShiroEffectContentView(UIView *effectView) {
    if (!effectView) return nil;
    SEL sel = NSSelectorFromString(@"contentView");
    if (![effectView respondsToSelector:sel]) return effectView;
    UIView *content = ((id (*)(id, SEL))objc_msgSend)(effectView, sel);
    return content ? content : effectView;
}

static int gFrostHasVE = -1;

static int ShiroFrostHasVisualEffect(void) {
    /* live glass is the only thing shiro does that reaches core image, and the
       ios 15 fault lands there. safe mode takes the painted wash instead; it
       looks flatter and it cannot fault in a render server callback */
    if (ShiroCrashSafeMode()) return 0;
    if (gFrostHasVE < 0)
        gFrostHasVE = (NSClassFromString(@"UIVisualEffectView") &&
                       NSClassFromString(@"UIBlurEffect")) ? 1 : 0;
    return gFrostHasVE;
}

/* ios 6 and 7 need a wash because UIVisualEffectView does not exist */
void ShiroInstallFrost(UIView *host) {
    if (!host) return;
    if (!ShiroThemeIsIos26()) {
        ShiroInstallFrostLite(host);
        return;
    }

    CGFloat r = host.layer.cornerRadius;
    BOOL light = ShiroThemeIsLight();
    UIColor *washColor = light
        ? [UIColor colorWithWhite:1.0 alpha:0.28]
        : [UIColor colorWithWhite:1.0 alpha:0.10];
    UIView *old = [host viewWithTag:kShiroFrostTag];

    if (ShiroFrostHasVisualEffect()) {
        Class effectViewCls = NSClassFromString(@"UIVisualEffectView");
        Class blurCls = NSClassFromString(@"UIBlurEffect");
        NSInteger style = light ? 0 : 2;
        id effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(
            blurCls, NSSelectorFromString(@"effectWithStyle:"), style);
        if (effect) {
            if (old && [old isKindOfClass:effectViewCls]) {
                if (!CGRectEqualToRect(old.frame, host.bounds))
                    old.frame = host.bounds;
                old.layer.cornerRadius = r;
                old.clipsToBounds = YES;
                if ([old respondsToSelector:NSSelectorFromString(@"setEffect:")])
                    ((void (*)(id, SEL, id))objc_msgSend)(
                        old, NSSelectorFromString(@"setEffect:"), effect);
                UIView *oldHost = ShiroEffectContentView(old);
                for (UIView *sub in oldHost.subviews) {
                    if (sub.tag == 9108)
                        sub.backgroundColor = washColor;
                }
                return;
            }
            ShiroRemoveFrost(host);
            UIView *v = ((id (*)(id, SEL, id))objc_msgSend)(
                [effectViewCls alloc],
                NSSelectorFromString(@"initWithEffect:"),
                effect);
            v.tag = kShiroFrostTag;
            v.userInteractionEnabled = NO;
            v.frame = host.bounds;
            v.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                 UIViewAutoresizingFlexibleHeight;
            v.clipsToBounds = YES;
            v.layer.cornerRadius = r;
            UIView *tint = [[[UIView alloc] initWithFrame:v.bounds] autorelease];
            tint.tag = 9108;
            tint.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                    UIViewAutoresizingFlexibleHeight;
            tint.userInteractionEnabled = NO;
            tint.backgroundColor = washColor;
/* uikit raises NSInternalInconsistencyException for a subview added to the
   effect view itself: everything on top of the blur belongs to its contentView,
   and this is what killed every launch on the glass theme */
            [ShiroEffectContentView(v) addSubview:tint];
            [host insertSubview:v atIndex:0];
            [v release];
            return;
        }
    }

/* reusing the wash prevents stacked alpha layers after theme changes */
    if (old && ![old isKindOfClass:[UIToolbar class]]) {
        if (!CGRectEqualToRect(old.frame, host.bounds))
            old.frame = host.bounds;
        old.layer.cornerRadius = r;
        old.clipsToBounds = YES;
        old.backgroundColor = washColor;
        old.opaque = NO;
        return;
    }
    ShiroRemoveFrost(host);
    UIView *wash = [[UIView alloc] initWithFrame:host.bounds];
    wash.tag = kShiroFrostTag;
    wash.userInteractionEnabled = NO;
    wash.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                            UIViewAutoresizingFlexibleHeight;
    wash.backgroundColor = washColor;
    wash.opaque = NO;
    wash.clipsToBounds = YES;
    wash.layer.cornerRadius = r;
    [host insertSubview:wash atIndex:0];
    [wash release];
}

static UIColor *DarkChromeInk(void) {
    return [UIColor colorWithRed:1.00 green:0.92 blue:0.82 alpha:1.0];
}
static UIColor *DarkChromeMuted(void) {
    return [UIColor colorWithRed:0.78 green:0.72 blue:0.64 alpha:1.0];
}
static UIColor *DarkChromeAccent(void) {
    return [UIColor colorWithRed:1.00 green:0.58 blue:0.14 alpha:1.0];
}

static void ApplyPaperShadow(UILabel *label, CGFloat darkA, CGFloat lightA) {
    if (!label) return;
    if (ShiroThemeIsFlat()) {
        label.shadowColor = nil;
        label.shadowOffset = CGSizeZero;
        return;
    }
    if (ShiroThemeIsLight()) {
        label.shadowColor = [UIColor colorWithWhite:1 alpha:lightA];
        label.shadowOffset = CGSizeMake(0, 1);
    } else {
        label.shadowColor = [UIColor colorWithWhite:0 alpha:darkA];
        label.shadowOffset = CGSizeMake(0, -1);
    }
}

static void ApplyCutInShadow(UILabel *label, CGFloat alpha) {
    if (!label) return;
    label.shadowColor = [UIColor colorWithWhite:0 alpha:alpha];
    label.shadowOffset = CGSizeMake(0, -1);
}

void ShiroStyleInkLabel(UILabel *label) {
    if (!label) return;
    label.textColor = kInk;
    ApplyPaperShadow(label, 0.70f, 0.50f);
}

void ShiroStyleMutedLabel(UILabel *label) {
    if (!label) return;
    label.textColor = kInkMuted;
    if (ShiroThemeIsLight() && !ShiroThemeIsFlat()) {
        label.shadowColor = [UIColor colorWithWhite:1 alpha:0.35f];
        label.shadowOffset = CGSizeMake(0, 1);
    } else {
        label.shadowColor = nil;
        label.shadowOffset = CGSizeZero;
    }
}

void ShiroStyleAccentLabel(UILabel *label) {
    if (!label) return;
    label.textColor = kAccentBlue;
    ApplyPaperShadow(label, 0.65f, 0.40f);
}

void ShiroStyleInkOnDark(UILabel *label) {
    if (!label) return;
    label.textColor = DarkChromeInk();
    ApplyCutInShadow(label, 0.70f);
}

void ShiroStyleMutedOnDark(UILabel *label) {
    if (!label) return;
    label.textColor = DarkChromeMuted();
    label.shadowColor = nil;
    label.shadowOffset = CGSizeZero;
}

void ShiroStyleAccentOnDark(UILabel *label) {
    if (!label) return;
    label.textColor = DarkChromeAccent();
    ApplyCutInShadow(label, 0.65f);
}

void ShiroStyleChromeTitle(UIButton *button) {
    if (!button) return;
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    if (ShiroThemeIsFlat()) {
        button.titleLabel.shadowColor = nil;
        button.titleLabel.shadowOffset = CGSizeZero;
    } else {
        button.titleLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.45];
        button.titleLabel.shadowOffset = CGSizeMake(0, -1);
    }
}

void ShiroStyleGlyphOnDark(UIButton *button) {
    if (!button) return;
    [button setTitleColor:DarkChromeInk() forState:UIControlStateNormal];
    button.titleLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.70f];
    button.titleLabel.shadowOffset = CGSizeMake(0, -1);
}

void ShiroStylePaperGlyph(UIButton *button) {
    if (!button) return;
    [button setTitleColor:kAccentBlue forState:UIControlStateNormal];
    if (ShiroThemeIsFlat()) {
        button.titleLabel.shadowColor = nil;
        button.titleLabel.shadowOffset = CGSizeZero;
    } else if (ShiroThemeIsLight()) {
        button.titleLabel.shadowColor = [UIColor colorWithWhite:1 alpha:0.45f];
        button.titleLabel.shadowOffset = CGSizeMake(0, 1);
    } else {
        button.titleLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.70f];
        button.titleLabel.shadowOffset = CGSizeMake(0, -1);
    }
}

void ShiroFillSectionGradient(CAGradientLayer *g) {
    if (!g) return;
    if (ShiroThemeIsMiside()) {
        g.colors = [NSArray arrayWithObjects:
                    (id)[UIColor colorWithRed:0.22 green:0.10 blue:0.28 alpha:0.94].CGColor,
                    (id)[UIColor colorWithRed:0.14 green:0.06 blue:0.20 alpha:0.94].CGColor, nil];
        g.opacity = 1.0f;
    } else if (ShiroThemeIsBoykisser()) {
        if (ShiroThemeIsLight()) {
            g.colors = [NSArray arrayWithObjects:
                        (id)[UIColor colorWithRed:1.00 green:0.88 blue:0.93 alpha:0.92].CGColor,
                        (id)[UIColor colorWithRed:1.00 green:0.78 blue:0.88 alpha:0.92].CGColor, nil];
        } else {
/* the plate keeps its saturation so the header still sits above the cards the
   way the pink plate does on paper */
            g.colors = [NSArray arrayWithObjects:
                        (id)[UIColor colorWithRed:0.310 green:0.110 blue:0.200 alpha:0.94].CGColor,
                        (id)[UIColor colorWithRed:0.185 green:0.058 blue:0.125 alpha:0.94].CGColor, nil];
        }
        g.opacity = 1.0f;
    } else if (ShiroThemeIsFrutigeraero()) {
        if (ShiroThemeIsLight()) {
            g.colors = [NSArray arrayWithObjects:
                        (id)[UIColor colorWithRed:0.55 green:0.88 blue:1.00 alpha:0.95].CGColor,
                        (id)[UIColor colorWithRed:0.20 green:0.68 blue:0.92 alpha:0.95].CGColor, nil];
        } else {
            g.colors = [NSArray arrayWithObjects:
                        (id)[UIColor colorWithRed:0.12 green:0.28 blue:0.58 alpha:0.94].CGColor,
                        (id)[UIColor colorWithRed:0.05 green:0.14 blue:0.36 alpha:0.94].CGColor, nil];
        }
        g.opacity = 1.0f;
    } else if (ShiroThemeIsIos26()) {
        if (ShiroThemeIsLight()) {
            g.colors = [NSArray arrayWithObjects:
                        (id)[UIColor colorWithWhite:1.0 alpha:0.36].CGColor,
                        (id)[UIColor colorWithWhite:1.0 alpha:0.14].CGColor, nil];
        } else {
            g.colors = [NSArray arrayWithObjects:
                        (id)[UIColor colorWithWhite:1.0 alpha:0.16].CGColor,
                        (id)[UIColor colorWithWhite:1.0 alpha:0.05].CGColor, nil];
        }
        g.opacity = 1.0f;
    } else if (ShiroThemeIsIos16()) {
        if (ShiroThemeIsLight()) {
            g.colors = [NSArray arrayWithObjects:
                        (id)[UIColor colorWithWhite:1.0 alpha:0.72].CGColor,
                        (id)[UIColor colorWithWhite:1.0 alpha:0.58].CGColor, nil];
        } else {
            g.colors = [NSArray arrayWithObjects:
                        (id)[UIColor colorWithWhite:1.0 alpha:0.14].CGColor,
                        (id)[UIColor colorWithWhite:1.0 alpha:0.08].CGColor, nil];
        }
        g.opacity = 1.0f;
    } else if (ShiroThemeIsFlat()) {
        UIColor *c = ShiroThemeIsLight()
            ? [UIColor colorWithRed:0.95 green:0.96 blue:0.99 alpha:0.35]
            : [UIColor colorWithRed:0.14 green:0.16 blue:0.22 alpha:0.40];
        g.colors = [NSArray arrayWithObjects:(id)c.CGColor, (id)c.CGColor, nil];
        g.opacity = 1.0f;
    } else if (ShiroThemeIsLight()) {
        g.colors = [NSArray arrayWithObjects:
                    (id)[UIColor colorWithRed:0.97 green:0.93 blue:0.86 alpha:1].CGColor,
                    (id)[UIColor colorWithRed:0.90 green:0.84 blue:0.74 alpha:1].CGColor, nil];
        g.opacity = 1.0f;
    } else {
        g.colors = [NSArray arrayWithObjects:
                    (id)[UIColor colorWithRed:0.22 green:0.14 blue:0.06 alpha:1].CGColor,
                    (id)[UIColor colorWithRed:0.09 green:0.06 blue:0.03 alpha:1].CGColor, nil];
        g.opacity = 1.0f;
    }
}

void ShiroStyleSectionPlate(UIView *plate) {
    if (!plate) return;
    CGFloat r = ShiroThemeCardRadius();
    plate.layer.cornerRadius = r;
    if (ShiroThemeIsMiside()) {
        ShiroRemoveFrost(plate);
        plate.backgroundColor = [UIColor clearColor];
        plate.layer.borderWidth = 0.5f;
        plate.layer.borderColor =
            [UIColor colorWithRed:1.0 green:0.40 blue:0.72 alpha:0.35].CGColor;
        plate.layer.shadowOpacity = 0.0f;
        plate.clipsToBounds = YES;
    } else if (ShiroThemeIsBoykisser()) {
        ShiroRemoveFrost(plate);
        plate.backgroundColor = [UIColor clearColor];
        plate.layer.borderWidth = 0.5f;
        plate.layer.borderColor =
            [UIColor colorWithRed:1.0 green:0.50 blue:0.72 alpha:0.45].CGColor;
        plate.layer.shadowOpacity = 0.0f;
        plate.layer.shadowRadius = 0;
        plate.clipsToBounds = YES;
    } else if (ShiroThemeIsFrutigeraero()) {
        ShiroRemoveFrost(plate);
        plate.backgroundColor = [UIColor clearColor];
        plate.layer.borderWidth = 0.5f;
        plate.layer.borderColor = ShiroThemeIsLight()
            ? [UIColor colorWithRed:0.20 green:0.75 blue:0.95 alpha:0.50].CGColor
            : [UIColor colorWithRed:0.34 green:0.64 blue:1.00 alpha:0.45].CGColor;
        plate.layer.shadowOpacity = 0.12f;
        plate.layer.shadowRadius = 3.0f;
        plate.layer.shadowOffset = CGSizeMake(0, 1);
        plate.clipsToBounds = YES;
    } else if (ShiroThemeIsIos26()) {
        BOOL light = ShiroThemeIsLight();
        plate.backgroundColor = [UIColor clearColor];
        plate.opaque = NO;
        plate.layer.borderWidth = 0.5f;
        plate.layer.borderColor = light
            ? [UIColor colorWithWhite:1 alpha:0.70].CGColor
            : [UIColor colorWithWhite:1 alpha:0.30].CGColor;
        plate.clipsToBounds = YES;
        plate.layer.masksToBounds = YES;
        plate.layer.shadowOpacity = 0.0f;
        plate.layer.shadowPath = nil;
/* a rasterized layer that holds a live UIVisualEffectView is re-rendered
   offscreen on every blur update, which pins the gpu and starves the rest of
   the system; the glass caches itself, so the plate must not rasterize */
        plate.layer.shouldRasterize = NO;
/* this plate is a section header inside a scrolling table, one per group on
   screen: a live UIVisualEffectView per header recomputes its blur on every
   scroll frame for however many are visible at once, which is what made the
   ios26 list stutter. the solid tinted wash keeps the glass read without
   asking an old gpu to blur several live rectangles a frame */
        ShiroInstallFrostLite(plate);
    } else if (ShiroThemeIsIos16()) {
        ShiroRemoveFrost(plate);
        plate.backgroundColor = [UIColor clearColor];
        plate.layer.borderWidth = 0;
        plate.layer.borderColor = [UIColor clearColor].CGColor;
        plate.clipsToBounds = YES;
        plate.layer.masksToBounds = NO;
        plate.layer.shadowColor = [UIColor blackColor].CGColor;
        plate.layer.shadowOpacity = ShiroThemeIsLight() ? 0.10f : 0.28f;
        plate.layer.shadowRadius = 6.0f;
        plate.layer.shadowOffset = CGSizeMake(0, 2);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:plate.bounds
                                                        cornerRadius:r];
        plate.layer.shadowPath = path.CGPath;
        plate.clipsToBounds = NO;
        plate.layer.masksToBounds = NO;
    } else if (ShiroThemeIsFlat()) {
        plate.backgroundColor = [UIColor clearColor];
        plate.layer.borderWidth = 0.5f;
        plate.layer.borderColor = ShiroThemeIsLight()
            ? [UIColor colorWithRed:0.70 green:0.74 blue:0.82 alpha:0.40].CGColor
            : [UIColor colorWithWhite:1 alpha:0.10].CGColor;
        plate.layer.shadowOpacity = 0.0f;
        plate.layer.shadowRadius = 0;
        plate.clipsToBounds = YES;
        ShiroInstallFrostLite(plate);
    } else {
        ShiroRemoveFrost(plate);
        plate.layer.borderWidth = 0.5f;
        if (ShiroThemeIsLight()) {
            plate.layer.borderColor =
                [UIColor colorWithRed:0.85 green:0.55 blue:0.28 alpha:0.35].CGColor;
            plate.layer.shadowOpacity = 0.12f;
        } else {
            plate.layer.borderColor =
                [UIColor colorWithRed:1 green:0.55 blue:0.16 alpha:0.30].CGColor;
            plate.layer.shadowOpacity = 0.20f;
        }
    }
}

void ShiroStyleSectionGlyph(UIButton *button) {
    if (!button) return;
    if (ShiroThemeIsMiside() || ShiroThemeIsBoykisser()) {
        UIColor *pink = [UIColor colorWithRed:1.00 green:0.42 blue:0.72 alpha:1.0];
        [button setTitleColor:pink forState:UIControlStateNormal];
        [button setTitleColor:[UIColor colorWithRed:0.90 green:0.28 blue:0.58 alpha:1.0]
                     forState:UIControlStateHighlighted];
        button.titleLabel.shadowColor = nil;
        button.titleLabel.shadowOffset = CGSizeZero;
    } else if (ShiroThemeIsFlat()) {
        [button setTitleColor:kAccentBlue forState:UIControlStateNormal];
        button.titleLabel.shadowColor = nil;
        button.titleLabel.shadowOffset = CGSizeZero;
    } else if (ShiroThemeIsLight()) {
        [button setTitleColor:kInk forState:UIControlStateNormal];
        button.titleLabel.shadowColor = [UIColor colorWithWhite:1 alpha:0.50f];
        button.titleLabel.shadowOffset = CGSizeMake(0, 1);
    } else {
        ShiroStyleGlyphOnDark(button);
    }
}

void ShiroStyleTerminalPlate(UIView *plate) {
    if (!plate) return;
    plate.layer.borderWidth = 0;
    plate.layer.borderColor = [UIColor clearColor].CGColor;
    plate.layer.shadowOpacity = 0.0f;
    plate.layer.shadowPath = nil;
    plate.clipsToBounds = YES;
    if (ShiroThemeUsesFrost()) {
        plate.backgroundColor = [UIColor clearColor];
        ShiroInstallFrost(plate);
        plate.layer.borderWidth = 0;
    } else {
        ShiroRemoveFrost(plate);
        if (ShiroThemeIsLight())
            plate.backgroundColor = kWell;
        else
            plate.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.10 alpha:1.0];
    }
}

void ShiroStyleTerminalText(UITextView *tv) {
    if (!tv) return;
    if ((ShiroThemeIsFlat()) && ShiroThemeIsLight()) {
        tv.textColor = [UIColor colorWithRed:0.20 green:0.20 blue:0.22 alpha:1.0];
        tv.backgroundColor = [UIColor clearColor];
    } else if ((ShiroThemeIsFlat()) && !ShiroThemeIsLight()) {
        tv.textColor = [UIColor colorWithRed:0.70 green:0.95 blue:0.70 alpha:1.0];
        tv.backgroundColor = [UIColor clearColor];
    } else if (ShiroThemeIsLight()) {
        tv.textColor = [UIColor colorWithRed:0.22 green:0.38 blue:0.24 alpha:1.0];
        tv.backgroundColor = [UIColor clearColor];
    } else {
        tv.textColor = [UIColor colorWithRed:0.55 green:0.95 blue:0.45 alpha:1.0];
        tv.backgroundColor = [UIColor clearColor];
    }
}

/* caching avoids redrawing identical glass tiles during scrolling */
static UIImage *gGlassIdleL, *gGlassIdleD, *gGlassSelL, *gGlassSelD;
static UIImage *gGlassDivL, *gGlassDivD;

static UIImage *ShiroGlassStretch(UIColor *fill, CGFloat h) {
    if (h < 1.0f) h = 28.0f;
    CGSize sz = CGSizeMake(12.0f, h);
    UIGraphicsBeginImageContextWithOptions(sz, NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx) {
        [fill setFill];
        UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, sz.width, sz.height)
                                                     cornerRadius:6.0f];
        [p fill];
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [img stretchableImageWithLeftCapWidth:6 topCapHeight:0];
}

static void ShiroGlassEnsureCache(void) {
    if (gGlassIdleL && gGlassIdleD) return;
    UIColor *idleL = [UIColor colorWithWhite:1.0 alpha:0.30];
    UIColor *idleD = [UIColor colorWithWhite:1.0 alpha:0.12];
    UIColor *selL = [UIColor colorWithRed:0.15 green:0.50 blue:1.00 alpha:0.50];
    UIColor *selD = [UIColor colorWithRed:0.25 green:0.55 blue:1.00 alpha:0.42];
    gGlassIdleL = [ShiroGlassStretch(idleL, 32.0f) retain];
    gGlassIdleD = [ShiroGlassStretch(idleD, 32.0f) retain];
    gGlassSelL = [ShiroGlassStretch(selL, 32.0f) retain];
    gGlassSelD = [ShiroGlassStretch(selD, 32.0f) retain];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(2, 32), NO, 0);
    [[UIColor colorWithWhite:1 alpha:0.40f] setFill];
    UIRectFill(CGRectMake(0, 0, 2, 32));
    gGlassDivL = [UIGraphicsGetImageFromCurrentImageContext() retain];
    UIGraphicsEndImageContext();
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(2, 32), NO, 0);
    [[UIColor colorWithWhite:1 alpha:0.22f] setFill];
    UIRectFill(CGRectMake(0, 0, 2, 32));
    gGlassDivD = [UIGraphicsGetImageFromCurrentImageContext() retain];
    UIGraphicsEndImageContext();
}

enum { kShiroScreenBgTag = 9111 };

CGRect ShiroViewBounds(UIView *view) {
    if (!view) return CGRectZero;
    CGRect b = view.bounds;
    if (b.size.width >= 1.0f && b.size.height >= 1.0f) return b;
    if (view.superview) {
        b = view.superview.bounds;
        if (b.size.width >= 1.0f && b.size.height >= 1.0f) return b;
    }
    /* applicationFrame changes its axes with the status bar before UIKit has
       sized a new controller on ios 5. screen bounds is stable until UIKit
       supplies the view's real bounds on the first layout pass */
    b = [[UIScreen mainScreen] bounds];
    b.origin = CGPointZero;
    return b;
}

void ShiroClearTableBackground(UITableView *table) {
    if (!table) return;
    table.backgroundColor = [UIColor clearColor];
/* grouped tables on ios 5 and 6 paint their own pinstripe view over the
   screen gradient unless it is removed */
    if ([table respondsToSelector:@selector(setBackgroundView:)])
        table.backgroundView = nil;
}

void ShiroApplyScreenChrome(UIView *root) {
    if (!root) return;
    UIView *old = [root viewWithTag:kShiroScreenBgTag];
/* builds before the backdrop view left the gradient as a bare sublayer, and a
   theme change would otherwise stack a second one on top of it. a layer that
   backs a view has a delegate and must never be pulled out from under it */
    NSArray *subs = [NSArray arrayWithArray:root.layer.sublayers];
    for (CALayer *L in subs) {
        if (L.delegate) continue;
        if ([L.name isEqualToString:@"bgGrad"] || [L.name isEqualToString:@"vgrad"])
            [L removeFromSuperlayer];
    }
    if (!ShiroThemeIsIos26()) {
        if (old) [old removeFromSuperview];
        root.backgroundColor = kBG;
        ShiroApplyBackgroundGradient(AddVGradient(root, kBG, kBGBot));
        return;
    }
    [[root viewWithTag:kShiroBackdropTag] removeFromSuperview];
    BOOL light = ShiroThemeIsLight();
    NSString *name = light ? @"ios26-bg-light" : @"ios26-bg-dark";
    UIImage *img = [UIImage imageNamed:[name stringByAppendingString:@".jpg"]];
    if (!img) {
        NSString *p = [[NSBundle mainBundle] pathForResource:name ofType:@"jpg"];
        if (p) img = [UIImage imageWithContentsOfFile:p];
    }
    root.backgroundColor = light
        ? [UIColor colorWithWhite:0.92 alpha:1]
        : [UIColor colorWithWhite:0.06 alpha:1];
    if (!img) {
        if (old) [old removeFromSuperview];
        return;
    }
    UIImageView *bg = (UIImageView *)old;
    if (![bg isKindOfClass:[UIImageView class]]) {
        if (old) [old removeFromSuperview];
        bg = [[[UIImageView alloc] initWithImage:img] autorelease];
        bg.tag = kShiroScreenBgTag;
        bg.contentMode = UIViewContentModeScaleAspectFill;
        bg.clipsToBounds = YES;
        bg.userInteractionEnabled = NO;
        bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [root insertSubview:bg atIndex:0];
    } else {
        bg.image = img;
        bg.hidden = NO;
    }
    bg.frame = root.bounds;
/* an opaque cover avoids full-screen blending on old gpus */
    bg.opaque = YES;
    bg.backgroundColor = root.backgroundColor;
    [root sendSubviewToBack:bg];
}

void ShiroStyleGlassField(UITextField *field) {
    if (!field) return;
    BOOL light = ShiroThemeIsLight();
    if (!ShiroThemeIsIos26()) {
        field.borderStyle = UITextBorderStyleRoundedRect;
        field.backgroundColor = kWell;
        field.textColor = kInk;
        return;
    }
/* removing the system bezel prevents a solid white ios 6 button background */
    field.borderStyle = UITextBorderStyleNone;
    field.opaque = NO;
    field.backgroundColor = light
        ? [UIColor colorWithWhite:1.0 alpha:0.32]
        : [UIColor colorWithWhite:1.0 alpha:0.14];
    field.textColor = kInk;
    field.layer.cornerRadius = 8.0f;
    field.clipsToBounds = YES;
    field.layer.borderWidth = 0.5f;
    field.layer.borderColor = light
        ? [UIColor colorWithWhite:1 alpha:0.65].CGColor
        : [UIColor colorWithWhite:1 alpha:0.30].CGColor;
    if (!field.leftView) {
        UIView *pad = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 28)] autorelease];
        pad.userInteractionEnabled = NO;
        field.leftView = pad;
        field.leftViewMode = UITextFieldViewModeAlways;
    }
}

/* ios 5 title attributes are kept for the shared segmented-control renderer */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
void ShiroStyleGlassSegmented(UISegmentedControl *seg) {
    if (!seg) return;
    if (!ShiroThemeIsIos26()) return;
    BOOL light = ShiroThemeIsLight();

    seg.segmentedControlStyle = UISegmentedControlStyleBar;
    seg.opaque = NO;
    seg.backgroundColor = [UIColor clearColor];
    if ([seg respondsToSelector:@selector(setTintColor:)])
        seg.tintColor = [UIColor clearColor];

    ShiroGlassEnsureCache();
    UIImage *idleImg = light ? gGlassIdleL : gGlassIdleD;
    UIImage *selImg = light ? gGlassSelL : gGlassSelD;
    UIImage *div = light ? gGlassDivL : gGlassDivD;
    if ([seg respondsToSelector:@selector(setBackgroundImage:forState:barMetrics:)]) {
        [seg setBackgroundImage:idleImg forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
        [seg setBackgroundImage:selImg forState:UIControlStateSelected barMetrics:UIBarMetricsDefault];
        [seg setBackgroundImage:selImg forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
        [seg setBackgroundImage:selImg forState:(UIControlState)(UIControlStateSelected | UIControlStateHighlighted)
                     barMetrics:UIBarMetricsDefault];
    }
    if (div && [seg respondsToSelector:@selector(setDividerImage:forLeftSegmentState:rightSegmentState:barMetrics:)]) {
        [seg setDividerImage:div
         forLeftSegmentState:UIControlStateNormal
           rightSegmentState:UIControlStateNormal
                  barMetrics:UIBarMetricsDefault];
        [seg setDividerImage:div
         forLeftSegmentState:UIControlStateSelected
           rightSegmentState:UIControlStateNormal
                  barMetrics:UIBarMetricsDefault];
        [seg setDividerImage:div
         forLeftSegmentState:UIControlStateNormal
           rightSegmentState:UIControlStateSelected
                  barMetrics:UIBarMetricsDefault];
    }
    /* the attribute keys are ios 5 symbols and read as null on ios 4.3 */
    if ([seg respondsToSelector:@selector(setTitleTextAttributes:forState:)]) {
        NSDictionary *titleN = [NSDictionary dictionaryWithObjectsAndKeys:
                                kInk, UITextAttributeTextColor,
                                [UIFont boldSystemFontOfSize:13], UITextAttributeFont, nil];
        NSDictionary *titleS = [NSDictionary dictionaryWithObjectsAndKeys:
                                [UIColor whiteColor], UITextAttributeTextColor,
                                [UIFont boldSystemFontOfSize:13], UITextAttributeFont, nil];
        [seg setTitleTextAttributes:titleN forState:UIControlStateNormal];
        [seg setTitleTextAttributes:titleS forState:UIControlStateSelected];
    }
}

#pragma clang diagnostic pop

void ShiroStyleSelectableCell(UITableViewCell *cell) {
    if (!cell) return;
    UIView *selected = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
    selected.backgroundColor = [kAccentBlue colorWithAlphaComponent:
        ShiroThemeIsMaterial() ? (ShiroThemeIsLight() ? 0.08f : 0.14f)
                               : (ShiroThemeIsLight() ? 0.13f : 0.20f)];
    selected.opaque = NO;
    cell.selectedBackgroundView = selected;
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
}

/* relative luminance of an sRGB channel, as the wcag contrast formula defines it */
static double ShiroChannelLuminance(CGFloat c) {
    double v = c;
    return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4);
}

/* a fixed accent prevents status color jumps while refresh changes state */
UIColor *ShiroPillLabelColor(UIColor *fill) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (ShiroThemeIsMaterial()) {
/* material picks the label by contrast, not by a brightness cut. the teal
   secondary is bright enough to pass a luma test and still gives white text
   a contrast of 1.6, which is what made its buttons vanish. black takes over
   below 3:1, the floor for large text and icons */
        if (!ShiroColorComponents(fill, &r, &g, &b, &a)) return [UIColor whiteColor];
        double lum = 0.2126 * ShiroChannelLuminance(r) + 0.7152 * ShiroChannelLuminance(g) +
                     0.0722 * ShiroChannelLuminance(b);
        double white = 1.05 / (lum + 0.05);
        return white >= 3.0 ? [UIColor whiteColor] : [UIColor colorWithWhite:0.08f alpha:1.0f];
    }
/* on a dark theme every filled control carries white, whatever its own fill
   does: a bright accent under dark text was the one thing on the screen reading
   as a light control, and the screen is not a light one */
    if (!ShiroThemeIsLight()) return [UIColor whiteColor];
    if (!ShiroColorComponents(fill, &r, &g, &b, &a)) return [UIColor whiteColor];
/* a light theme still picks by the fill, because a pale pill there needs dark
   text and a saturated one does not */
    CGFloat luma = 0.299f * r + 0.587f * g + 0.114f * b;
    return luma > 0.62f ? [UIColor colorWithWhite:0.10f alpha:1.0f]
                        : [UIColor whiteColor];
}

/* the home screen's line under the tunnel state. a resting line reads as a
   caption, a line reporting work in progress takes the accent */
void SetStatusDefault(UILabel *label, NSString *text) {
    if (ShiroThemeIsIos26() || ShiroThemeIsIos16())
        label.font = ShiroFontBody(13, NO);
    else
        label.font = [UIFont systemFontOfSize:14];
    ShiroStyleMutedLabel(label);
    label.shadowColor = nil;
    label.shadowOffset = CGSizeZero;
    label.text = text;
}

void SetStatusRefresh(UILabel *label, NSString *text) {
    if (ShiroThemeIsIos26())
        label.font = ShiroFontBody(13, YES);
    else if (ShiroThemeIsIos16())
        label.font = ShiroFontBody(13, YES);
    else if (ShiroThemeIsFlat())
        label.font = [UIFont systemFontOfSize:13];
    else
        label.font = [UIFont boldSystemFontOfSize:13];
    ShiroStyleAccentLabel(label);
    label.shadowColor = nil;
    label.shadowOffset = CGSizeZero;
    label.text = text;
}

/* caching prevents section headers from retinting identical icons while scrolling */

/* motion helpers. every entry point degrades instead of skipping the movement:
   ios 5 has block animation but no spring curve, so the fallback plays the
   overshoot as two timed steps */

void ShiroAnimate(NSTimeInterval duration, void (^animations)(void),
                  void (^completion)(BOOL finished)) {
    if (!animations) return;
    if (![UIView respondsToSelector:@selector(animateWithDuration:animations:completion:)]) {
        animations();
        if (completion) completion(YES);
        return;
    }
    [UIView animateWithDuration:duration
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionCurveEaseOut
                     animations:animations
                     completion:completion];
}

void ShiroAnimateSpring(NSTimeInterval duration, NSTimeInterval delay,
                        void (^animations)(void),
                        void (^completion)(BOOL finished)) {
    if (!animations) return;
    SEL spring = @selector(animateWithDuration:delay:usingSpringWithDamping:
                           initialSpringVelocity:options:animations:completion:);
    if ([UIView respondsToSelector:spring]) {
        /* the armv7 slice builds against an sdk that predates the spring api,
           so the call goes through a typed send instead of an implicit
           declaration that would pass the damping floats in the wrong slots */
        typedef void (*ShiroSpringFn)(id, SEL, NSTimeInterval, NSTimeInterval,
                                      CGFloat, CGFloat, NSUInteger,
                                      void (^)(void), void (^)(BOOL));
        ((ShiroSpringFn)objc_msgSend)([UIView class], spring, duration, delay,
                                      0.78f, 0.45f,
                                      UIViewAnimationOptionBeginFromCurrentState,
                                      animations, completion);
        return;
    }
    if (![UIView respondsToSelector:@selector(animateWithDuration:animations:completion:)]) {
        animations();
        if (completion) completion(YES);
        return;
    }
    [UIView animateWithDuration:duration
                          delay:delay
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionCurveEaseOut
                     animations:animations
                     completion:completion];
}

/* a rasterized layer rebuilds its cache on every step of a scale, which is what
   makes a press feel expensive on an armv7 device. the cache is dropped for the
   duration and restored once the view is at rest again */
static void SuspendRasterization(UIView *view) {
    if (!view.layer.shouldRasterize) return;
    objc_setAssociatedObject(view, &kShiroRasterKey, [NSNumber numberWithBool:YES],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.layer.shouldRasterize = NO;
}

static void RestoreRasterization(UIView *view) {
    if (![objc_getAssociatedObject(view, &kShiroRasterKey) boolValue]) return;
    objc_setAssociatedObject(view, &kShiroRasterKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.layer.rasterizationScale = [UIScreen mainScreen].scale;
    view.layer.shouldRasterize = YES;
}

void ShiroPressPop(UIView *view, BOOL pressed) {
    if (!view) return;
/* material shows a press as a ripple, and a surface there never changes size */
    if (ShiroThemeIsMaterial()) return;
    CGAffineTransform target = pressed
        ? CGAffineTransformMakeScale(0.965f, 0.965f)
        : CGAffineTransformIdentity;
    if (CGAffineTransformEqualToTransform(view.transform, target)) return;
    SuspendRasterization(view);
    /* the release has to spring, the press must not: a bouncy press feels
       like lag when the finger is still down */
    if (pressed) {
        ShiroAnimate(0.10, ^{ view.transform = target; }, NULL);
    } else {
        ShiroAnimateSpring(0.30, 0, ^{ view.transform = target; }, ^(BOOL done) {
            (void)done;
            /* an older release animation can finish after a second press. do
               not freeze that pressed frame into the raster cache */
            if (CGAffineTransformIsIdentity(view.transform))
                RestoreRasterization(view);
        });
    }
}

/* the header wordmark wants a geometric bold close to Rubik. no ios ships that
   face, so the ladder walks from the roundest system face down to what ios 5
   actually has and stops at the first one the device can create. every symbol
   past ios 6 is resolved at runtime because the armv7 slice builds against an
   sdk that has neither UIFontDescriptor nor the rounded design */
UIFont *ShiroFontDisplay(CGFloat size) {
    UIFont *base = [UIFont boldSystemFontOfSize:size];
    SEL descSel = @selector(fontDescriptor);
    SEL designSel = NSSelectorFromString(@"fontDescriptorWithDesign:");
    SEL makeSel = NSSelectorFromString(@"fontWithDescriptor:size:");
    if ([base respondsToSelector:descSel] && [UIFont respondsToSelector:makeSel]) {
        id desc = ((id (*)(id, SEL))objc_msgSend)(base, descSel);
        if ([desc respondsToSelector:designSel]) {
            id rounded = ((id (*)(id, SEL, NSString *))objc_msgSend)
                (desc, designSel, @"NSCTFontUIFontDesignRounded");
            if (rounded) {
                UIFont *f = ((id (*)(id, SEL, id, CGFloat))objc_msgSend)
                    ([UIFont class], makeSel, rounded, size);
                if (f) return f;
            }
        }
    }
    static NSString * const kFaces[] = {
        @"AvenirNext-Bold", @"Avenir-Black", @"HelveticaNeue-Bold"
    };
    for (size_t i = 0; i < sizeof kFaces / sizeof kFaces[0]; ++i) {
        UIFont *f = [UIFont fontWithName:kFaces[i] size:size];
        if (f) return f;
    }
    return base;
}

/* a label lays out text the same way every screen here draws it, and it is the
   one measurement that exists unchanged from ios 5 to ios 16. the string
   drawing category cannot be used instead: -sizeWithAttributes: returns a
   struct through objc_msgSend, which is the wrong call on armv7, and
   -sizeWithFont:constrainedToSize:lineBreakMode: takes an unbounded height
   that newer text layout does not accept */
CGSize ShiroTextSize(NSString *text, UIFont *font, CGFloat width) {
    static UILabel *gauge = nil;
    if (![text length] || !font || width < 1.0f) return CGSizeZero;
    if (!gauge) {
        gauge = [[UILabel alloc] initWithFrame:CGRectZero];
        gauge.numberOfLines = 0;
        gauge.lineBreakMode = NSLineBreakByWordWrapping;
        gauge.backgroundColor = [UIColor clearColor];
    }
    gauge.font = font;
    gauge.text = text;
    CGSize fit = [gauge sizeThatFits:CGSizeMake(width, 100000.0f)];
    if (fit.width > width) fit.width = width;
    fit.width = ceilf(fit.width);
    fit.height = ceilf(fit.height);
    return fit;
}

/* measuring the string is the only way to stop a control from ellipsing its own
   title */
CGFloat ShiroTextWidth(NSString *text, UIFont *font) {
    return ShiroTextSize(text, font, 100000.0f).width;
}

/* a palette is free to hand over two nearly identical stops, which paints a
   flat slab where the design asks for a gradient. these derive the stops from
   one colour so every theme gets the same amount of relief */
BOOL ShiroColorComponents(UIColor *color, CGFloat *r, CGFloat *g, CGFloat *b, CGFloat *a) {
    *r = *g = *b = 0.0f;
    *a = 1.0f;
    if (!color) return NO;
    /* getRed: also converts colourspaces the CGColor path cannot read */
    if ([color respondsToSelector:@selector(getRed:green:blue:alpha:)] &&
        [color getRed:r green:g blue:b alpha:a])
        return YES;
    /* ios 4.3 has no getRed:, and ios 5 refuses it for white colourspace colours */
    *r = *g = *b = 0.0f;
    *a = 1.0f;
    CGColorRef cg = [color CGColor];
    const CGFloat *c = cg ? CGColorGetComponents(cg) : NULL;
    if (!c) return NO;
    CGColorSpaceModel model = CGColorSpaceGetModel(CGColorGetColorSpace(cg));
    size_t n = CGColorGetNumberOfComponents(cg);
    if (model == kCGColorSpaceModelRGB && n == 4) {
        *r = c[0]; *g = c[1]; *b = c[2]; *a = c[3];
        return YES;
    }
    if (model == kCGColorSpaceModelMonochrome && n == 2) {
        *r = *g = *b = c[0];
        *a = c[1];
        return YES;
    }
    return NO;
}

UIColor *ShiroShadeColor(UIColor *base, CGFloat delta) {
    if (!base) return nil;
    CGFloat r, g, b, a;
    if (!ShiroColorComponents(base, &r, &g, &b, &a)) return base;
    CGFloat target = delta > 0.0f ? 1.0f : 0.0f;
    CGFloat mix = delta < 0.0f ? -delta : delta;
    if (mix > 1.0f) mix = 1.0f;
    return [UIColor colorWithRed:r + (target - r) * mix
                           green:g + (target - g) * mix
                            blue:b + (target - b) * mix
                           alpha:a];
}
