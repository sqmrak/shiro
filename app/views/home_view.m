#import "home_view.h"
#import "ui_theme.h"
#import "app_common.h"
#import "selection_mark.h"
#import "material.h"

#include <math.h>

static NSString * const kShiroOrbitSpinKey = @"shiro.orbit.spin";
static NSString * const kShiroOrbitPulseKey = @"shiro.orbit.pulse";
static NSString * const kShiroOrbitFadeKey = @"shiro.orbit.fade";
static const CFTimeInterval kShiroOrbitFadeTime = 0.45;
static const CGFloat kShiroOrbitDotRest = 0.2f;

static BOOL ShiroHomeIsPad(void) {
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
}

static UIColor *ShiroHomeStateTint(NSString *key) {
    if ([key isEqualToString:@"connected"])
        return [UIColor colorWithRed:1.0 green:0.06 blue:0.39 alpha:1.0];
    if ([key isEqualToString:@"error"])
        return [UIColor colorWithRed:0.95 green:0.30 blue:0.26 alpha:1.0];
    return kAccentBlue;
}

/* seconds per lap while the tunnel is active */
static CFTimeInterval ShiroOrbitPeriod(NSString *key) {
    if ([key isEqualToString:@"connecting"]) return 1.4;
    return 4.5;
}

static CGPathRef ShiroCirclePath(CGPoint c, CGFloat r) {
    return [UIBezierPath bezierPathWithArcCenter:c radius:r startAngle:0.0f
                                        endAngle:(CGFloat)(M_PI * 2.0)
                                       clockwise:YES].CGPath;
}

@implementation ShiroOrbitButton

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.exclusiveTouch = YES;
        _stateKey = [@"idle" copy];

        _track = [[CAShapeLayer alloc] init];
        _track.fillColor = [UIColor clearColor].CGColor;
        _track.lineWidth = 1.0f;
        [self.layer addSublayer:_track];

        _halo = [[CAShapeLayer alloc] init];
        _halo.shadowOffset = CGSizeZero;
        [self.layer addSublayer:_halo];

        _face = [[CAShapeLayer alloc] init];
        _face.shadowColor = [UIColor blackColor].CGColor;
        _face.shadowOffset = CGSizeMake(0.0f, 3.0f);
        _face.shadowRadius = 5.0f;
        [self.layer addSublayer:_face];
        _faceFill = [[CAGradientLayer alloc] init];
        _faceFill.startPoint = CGPointMake(0.5f, 0.0f);
        _faceFill.endPoint = CGPointMake(0.5f, 1.0f);
        _faceFill.masksToBounds = YES;
        [self.layer addSublayer:_faceFill];
        _faceSheen = [[CAGradientLayer alloc] init];
        _faceSheen.startPoint = CGPointMake(0.5f, 0.0f);
        _faceSheen.endPoint = CGPointMake(0.5f, 1.0f);
        [_faceFill addSublayer:_faceSheen];

        _ring = [[CAShapeLayer alloc] init];
        _ring.fillColor = [UIColor clearColor].CGColor;
        _ring.shadowOffset = CGSizeZero;
/* the glow is a blur of a still stroke; caching it keeps the spinning dot from
   re-rendering the shadow on every frame of an armv7 device */
        _ring.shouldRasterize = YES;
        _ring.rasterizationScale = [UIScreen mainScreen].scale;
        [self.layer addSublayer:_ring];

        _glyph = [[CAShapeLayer alloc] init];
        _glyph.fillColor = [UIColor clearColor].CGColor;
        _glyph.lineCap = kCALineCapRound;
        [self.layer addSublayer:_glyph];

        _spinner = [[CAShapeLayer alloc] init];
        _spinner.fillColor = [UIColor clearColor].CGColor;
        _spinner.lineCap = kCALineCapRound;
        _spinner.opacity = 0.0f;
        [self.layer addSublayer:_spinner];

        _orbit = [[CALayer alloc] init];
        [self.layer addSublayer:_orbit];
        _trail = [[CAShapeLayer alloc] init];
        _trail.fillColor = [UIColor clearColor].CGColor;
        _trail.lineCap = kCALineCapRound;
        _trail.lineWidth = 2.0f;
        [_orbit addSublayer:_trail];
        _dot = [[CAShapeLayer alloc] init];
        _dot.shadowOffset = CGSizeZero;
        _dot.shadowRadius = 5.0f;
        _dot.shadowOpacity = 0.9f;
        [_orbit addSublayer:_dot];
        /* the dot starts off the ring: no tail, shrunk, transparent */
        _orbit.opacity = 0.0f;
        _trail.strokeStart = 1.0f;
        _dot.transform = CATransform3DMakeScale(kShiroOrbitDotRest, kShiroOrbitDotRest, 1.0f);

        [self applyTheme];
    }
    return self;
}

- (void)dealloc {
    [_track release];
    [_halo release];
    [_face release];
    [_faceFill release];
    [_faceSheen release];
    [_ring release];
    [_glyph release];
    [_trail release];
    [_dot release];
    [_spinner release];
    [_orbit release];
    [_stateKey release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    if (size.width < 1.0f || size.height < 1.0f) return;
    if (CGSizeEqualToSize(size, _laidSize)) return;
    _laidSize = size;

    CGRect b = self.bounds;
    CGFloat side = MIN(size.width, size.height);
    CGPoint c = CGPointMake(size.width * 0.5f, size.height * 0.5f);
    CGFloat dotR = MAX(4.0f, side * 0.018f);
    CGFloat trackR = side * 0.5f - dotR - 3.0f;
    CGFloat ringR = trackR * 0.76f;
    CGFloat g = ringR * 0.34f;

    UIBezierPath *power = [UIBezierPath bezierPathWithArcCenter:c radius:g
        startAngle:(CGFloat)(-M_PI_2 + 0.62) endAngle:(CGFloat)(-M_PI_2 - 0.62 + M_PI * 2.0)
         clockwise:YES];
    [power moveToPoint:CGPointMake(c.x, c.y - g * 1.22f)];
    [power addLineToPoint:CGPointMake(c.x, c.y - g * 0.30f)];

    ShiroBeginSilentLayers();
    _track.frame = b;
    _halo.frame = b;
    _face.frame = b;
    _ring.frame = b;
    _glyph.frame = b;
    _orbit.bounds = b;
    _orbit.position = c;
    _trail.frame = b;
    _spinner.frame = b;
/* the dot is its own small layer so it can grow from its centre; frame is
   undefined under the scale it rests at */
    _dot.bounds = CGRectMake(0.0f, 0.0f, dotR * 2.0f, dotR * 2.0f);
    _dot.position = CGPointMake(c.x + trackR, c.y);
    _track.path = ShiroCirclePath(c, trackR);
    CGFloat faceR = ringR - 1.0f;
    _faceRadius = faceR;
/* material's ring sits in the gap between the disc and the edge of the control,
   and in a stroke as thick as its own progress indicators */
    CGFloat spinnerR = (ringR + trackR) * 0.5f;
    _spinner.path = ShiroCirclePath(c, spinnerR);
    _spinner.lineWidth = MAX(3.0f, side * 0.016f);
    CGRect faceRect = CGRectMake(c.x - faceR, c.y - faceR, faceR * 2.0f, faceR * 2.0f);
    _halo.path = ShiroCirclePath(c, ringR);
    _halo.shadowPath = _halo.path;
    _face.path = ShiroCirclePath(c, faceR);
    _face.shadowPath = _face.path;
    _faceFill.frame = faceRect;
    _faceFill.cornerRadius = faceR;
    _faceSheen.frame = CGRectMake(0.0f, 0.0f, faceR * 2.0f, faceR);
    _ring.path = ShiroCirclePath(c, ringR);
    _ring.lineWidth = MAX(2.5f, side * 0.013f);
    _glyph.path = power.CGPath;
    _glyph.lineWidth = MAX(3.0f, ringR * 0.075f);
    _trail.path = [UIBezierPath bezierPathWithArcCenter:c radius:trackR
                                             startAngle:-1.05f endAngle:0.0f
                                              clockwise:YES].CGPath;
    _dot.path = ShiroCirclePath(CGPointMake(dotR, dotR), dotR);
    _dot.shadowPath = _dot.path;
    ShiroEndSilentLayers();
}

/* at rest the button is lit only by the theme. a tunnel that is up, dialing or
   failed gives it a dim halo in its state colour */
/* a floating action button: one flat disc in the state colour that shifts to
   the next colour instead of jumping, a glyph in whichever of white and black
   reads on it, and elevation. the orbit, halo and sheen of the other themes are
   hidden */
- (void)applyMaterialTheme {
    UIColor *tint = ShiroHomeStateTint(_stateKey);
    UIColor *ink = ShiroPillLabelColor(tint);
    CAShapeLayer *shown = (CAShapeLayer *)[_face presentationLayer];
    CGColorRef before = CGColorRetain((shown ? shown : _face).fillColor);
    ShiroBeginSilentLayers();
    _track.hidden = YES;
    _halo.hidden = YES;
    _ring.hidden = YES;
    _faceFill.hidden = YES;
    _orbit.hidden = YES;
    _face.hidden = NO;
    _face.fillColor = tint.CGColor;
    _face.strokeColor = [UIColor clearColor].CGColor;
    ShiroMaterialElevate(_face, 6.0f);
    _glyph.strokeColor = ink.CGColor;
    _spinner.strokeColor = tint.CGColor;
    ShiroEndSilentLayers();
    if (before && self.window && !CGColorEqualToColor(before, tint.CGColor)) {
        CABasicAnimation *fill = [CABasicAnimation animationWithKeyPath:@"fillColor"];
        fill.fromValue = (id)before;
        fill.toValue = (id)tint.CGColor;
        fill.duration = 0.3;
        fill.timingFunction = ShiroMaterialStandardCurve();
        [_face addAnimation:fill forKey:@"shiro.fab.fill"];
    }
    if (before) CGColorRelease(before);
}

- (void)applyTheme {
    if (ShiroThemeIsMaterial()) {
        [self applyMaterialTheme];
        return;
    }
    UIColor *tint = ShiroHomeStateTint(_stateKey);
    BOOL idle = [_stateKey isEqualToString:@"idle"];
    BOOL light = ShiroThemeIsLight();
    BOOL flat = ShiroThemeIsFlat() && !ShiroThemeIsIos16();
    ShiroBeginSilentLayers();
/* a switch away from the material layout puts back what it hid and moved */
    _track.hidden = NO;
    _ring.hidden = NO;
    _faceFill.hidden = NO;
    _orbit.hidden = NO;
    _face.shadowOffset = CGSizeMake(0.0f, 3.0f);
    _face.shadowRadius = 5.0f;
    _track.strokeColor = [tint colorWithAlphaComponent:0.22f].CGColor;
    _halo.fillColor = tint.CGColor;
    _halo.shadowColor = tint.CGColor;
    _halo.shadowRadius = 14.0f;
    _halo.shadowOpacity = idle ? 0.0f : 0.32f;
    _halo.hidden = idle;
    _face.fillColor = kCellLo.CGColor;
    _face.strokeColor = [UIColor clearColor].CGColor;
    _face.shadowOpacity = flat ? 0.0f : (light ? 0.22f : 0.5f);
    BOOL connected = [_stateKey isEqualToString:@"connected"];
    UIColor *faceColor = connected ? tint : kCellHi;
    _faceFill.colors = [NSArray arrayWithObjects:
                        (id)ShiroShadeColor(faceColor, flat ? -0.03f : 0.04f).CGColor,
                        (id)ShiroShadeColor(faceColor, flat ? -0.03f : -0.14f).CGColor, nil];
    _faceSheen.hidden = flat;
    _faceSheen.colors = [NSArray arrayWithObjects:
                         (id)[UIColor colorWithWhite:1.0f alpha:light ? 0.30f : 0.12f].CGColor,
                         (id)[UIColor colorWithWhite:1.0f alpha:0.0f].CGColor, nil];
    _ring.strokeColor = tint.CGColor;
    _ring.shadowColor = tint.CGColor;
    _ring.shadowRadius = 6.0f;
    _ring.shadowOpacity = idle ? 0.0f : 0.45f;
    _glyph.strokeColor = (connected ? [UIColor whiteColor] : tint).CGColor;
    _trail.strokeColor = [tint colorWithAlphaComponent:0.45f].CGColor;
    _dot.fillColor = tint.CGColor;
    _dot.shadowColor = tint.CGColor;
    _dot.shadowOpacity = idle ? 0.35f : 0.8f;
    /* the aero wallpaper behind the orbit is sky and glass in the accent's own
       cyan, so the tinted dot and its glow vanished while connecting. a white
       rim and a navy shadow keep the state colour and read on sky and cloud */
    BOOL cased = ShiroThemeIsFrutigeraero();
    _dot.strokeColor = cased ? [UIColor whiteColor].CGColor : [UIColor clearColor].CGColor;
    _dot.lineWidth = cased ? 1.5f : 0.0f;
    if (cased) {
/* navy ink shades the dot on the sky; on the night wallpaper ink is white,
   so the shade has to be black to keep reading as a shadow */
        _dot.shadowColor = (light ? kInk : [UIColor blackColor]).CGColor;
        _dot.shadowRadius = 3.0f;
        _dot.shadowOpacity = 0.6f;
        _trail.strokeColor = [tint colorWithAlphaComponent:0.9f].CGColor;
    } else {
        _dot.shadowRadius = 5.0f;
    }
    _trail.lineWidth = cased ? 3.0f : 2.0f;
    _trail.shadowColor = kInk.CGColor;
    _trail.shadowOffset = CGSizeZero;
    _trail.shadowRadius = 2.0f;
    _trail.shadowOpacity = cased ? 0.5f : 0.0f;
/* the orbit turns every frame; a cached bitmap keeps these shadows from being
   blurred again on each one on armv7 */
    _dot.shouldRasterize = cased;
    _trail.shouldRasterize = cased;
    _dot.rasterizationScale = [UIScreen mainScreen].scale;
    _trail.rasterizationScale = [UIScreen mainScreen].scale;
    ShiroEndSilentLayers();
}

- (BOOL)orbitWanted {
    if (ShiroThemeIsMaterial()) return NO;
    return _running && ([_stateKey isEqualToString:@"connecting"] ||
                        [_stateKey isEqualToString:@"connected"]);
}

- (double)shownAngle {
    CALayer *shown = [_orbit presentationLayer];
    if (!shown) shown = _orbit;
    return [[shown valueForKeyPath:@"transform.rotation.z"] doubleValue];
}

/* the dot keeps its place when the speed changes: a new lap starts from
   wherever the old one is on screen, so a state switch never makes it jump */
- (void)stopSpin {
    double angle = [self shownAngle];
    [_orbit removeAnimationForKey:kShiroOrbitSpinKey];
    ShiroBeginSilentLayers();
    _orbit.transform = CATransform3DMakeRotation((CGFloat)angle, 0.0f, 0.0f, 1.0f);
    ShiroEndSilentLayers();
}

- (void)restartSpin {
    double angle = [self shownAngle];
    [self stopSpin];
    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.fromValue = [NSNumber numberWithDouble:angle];
    spin.toValue = [NSNumber numberWithDouble:angle + M_PI * 2.0];
    spin.duration = ShiroOrbitPeriod(_stateKey);
    spin.repeatCount = HUGE_VALF;
    spin.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [_orbit addAnimation:spin forKey:kShiroOrbitSpinKey];
}

static void ShiroOrbitTween(CALayer *layer, NSString *path, id from, id to, BOOL show) {
    CABasicAnimation *tween = [CABasicAnimation animationWithKeyPath:path];
    tween.fromValue = from;
    tween.toValue = to;
    tween.duration = kShiroOrbitFadeTime;
    tween.timingFunction = [CAMediaTimingFunction functionWithName:
        show ? kCAMediaTimingFunctionEaseOut : kCAMediaTimingFunctionEaseIn];
    [layer addAnimation:tween forKey:kShiroOrbitFadeKey];
}

/* the ring stays put; the dot grows its tail on it when a tunnel starts and
   pulls it back when the tunnel stops. it keeps circling while it fades out,
   so it never freezes in place, and a new start mid-fade turns it around from
   wherever it is on screen */
- (void)showOrbit:(BOOL)show animated:(BOOL)animated {
    if (show == _orbitShown) return;
    _orbitShown = show;
    CALayer *orbitNow = [_orbit presentationLayer];
    CAShapeLayer *trailNow = (CAShapeLayer *)[_trail presentationLayer];
    CALayer *dotNow = [_dot presentationLayer];
    NSNumber *opacityFrom = [NSNumber numberWithFloat:(orbitNow ? orbitNow : _orbit).opacity];
    NSNumber *startFrom = [NSNumber numberWithFloat:(trailNow ? trailNow : _trail).strokeStart];
    NSValue *scaleFrom = [NSValue valueWithCATransform3D:(dotNow ? dotNow : _dot).transform];
    CATransform3D scale = show ? CATransform3DIdentity
        : CATransform3DMakeScale(kShiroOrbitDotRest, kShiroOrbitDotRest, 1.0f);

    [_orbit removeAnimationForKey:kShiroOrbitFadeKey];
    [_trail removeAnimationForKey:kShiroOrbitFadeKey];
    [_dot removeAnimationForKey:kShiroOrbitFadeKey];
    ShiroBeginSilentLayers();
    _orbit.opacity = show ? 1.0f : 0.0f;
    _trail.strokeStart = show ? 0.0f : 1.0f;
    _dot.transform = scale;
    ShiroEndSilentLayers();
    if (!animated) {
        if (!show) [self stopSpin];
        return;
    }

    [CATransaction begin];
    if (!show) {
        [CATransaction setCompletionBlock:^{
            if (!_orbitShown) [self stopSpin];
        }];
    }
    ShiroOrbitTween(_orbit, @"opacity", opacityFrom,
                    [NSNumber numberWithFloat:_orbit.opacity], show);
    ShiroOrbitTween(_trail, @"strokeStart", startFrom,
                    [NSNumber numberWithFloat:_trail.strokeStart], show);
    ShiroOrbitTween(_dot, @"transform", scaleFrom,
                    [NSValue valueWithCATransform3D:scale], show);
    [CATransaction commit];
}

/* a state switch animates the dot; leaving or returning to the screen only
   puts it where it belongs */
- (void)syncOrbitAnimated:(BOOL)animated restart:(BOOL)restart {
    if ([self orbitWanted]) {
        if (restart || ![_orbit animationForKey:kShiroOrbitSpinKey]) [self restartSpin];
        [self showOrbit:YES animated:animated];
    } else {
        [self showOrbit:NO animated:animated];
    }
}

/* material's progress ring turns while the tunnel dials and nowhere else */
- (void)syncSpinner {
    BOOL want = ShiroThemeIsMaterial() && _running && [_stateKey isEqualToString:@"connecting"];
    if (want) ShiroMaterialSpinnerStart(_spinner);
    else ShiroMaterialSpinnerStop(_spinner);
}

- (void)syncPulse {
    BOOL want = _running && [_stateKey isEqualToString:@"connecting"];
    if (!want) {
        [_ring removeAnimationForKey:kShiroOrbitPulseKey];
        return;
    }
    if ([_ring animationForKey:kShiroOrbitPulseKey]) return;
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue = [NSNumber numberWithFloat:1.0f];
    pulse.toValue = [NSNumber numberWithFloat:0.35f];
    pulse.duration = 0.7;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    [_ring addAnimation:pulse forKey:kShiroOrbitPulseKey];
}

/* core animation drops layer animations while the app is in the background,
   so every state write also puts back whatever went missing */
- (void)setStateKey:(NSString *)key {
    if (![key length]) key = @"idle";
    BOOL changed = ![key isEqualToString:_stateKey];
    if (changed) {
        [_stateKey release];
        _stateKey = [key copy];
    }
    [self applyTheme];
    [self syncOrbitAnimated:changed restart:changed];
    [self syncPulse];
    [self syncSpinner];
    if (changed && ShiroThemeIsMaterial() && self.window &&
        [_stateKey isEqualToString:@"connected"])
        ShiroMaterialPulse(self.layer, CGPointMake(self.bounds.size.width * 0.5f,
                                                   self.bounds.size.height * 0.5f),
                           _faceRadius, ShiroHomeStateTint(_stateKey));
}

- (void)setRunning:(BOOL)running {
    BOOL changed = _running != running;
    _running = running;
    [self syncOrbitAnimated:NO restart:changed];
    [self syncPulse];
    [self syncSpinner];
}

/* a button lifts under the finger in material and does not shrink */
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (ShiroThemeIsMaterial())
        ShiroMaterialSetElevation(_face, highlighted ? 12.0f : 6.0f, YES);
    else
        ShiroPressPop(self, highlighted);
}

/* the ripple spreads inside the disc, not across the square the control owns */
- (CGRect)shiroRippleBounds {
    CGFloat r = _faceRadius > 1.0f ? _faceRadius : MIN(self.bounds.size.width, self.bounds.size.height) * 0.38f;
    return CGRectMake(self.bounds.size.width * 0.5f - r, self.bounds.size.height * 0.5f - r,
                      r * 2.0f, r * 2.0f);
}

- (CGFloat)shiroRippleRadius {
    return CGRectGetWidth([self shiroRippleBounds]) * 0.5f;
}

- (UIColor *)shiroRippleColor {
    return [ShiroPillLabelColor(ShiroHomeStateTint(_stateKey)) colorWithAlphaComponent:0.30f];
}

@end

static NSString * const kShiroPlateFill = @"homePlateFill";
static NSString * const kShiroPlateSheen = @"homePlateSheen";

@interface ShiroHomePlateBackdrop : UIView
@end

@implementation ShiroHomePlateBackdrop
@end

static UIView *ShiroPlateBackdrop(UIView *plate, BOOL create) {
    for (UIView *view in plate.subviews)
        if ([view isKindOfClass:[ShiroHomePlateBackdrop class]]) return view;
    if (!create) return nil;
    UIView *view = [[[ShiroHomePlateBackdrop alloc] initWithFrame:plate.bounds] autorelease];
    view.userInteractionEnabled = NO;
    view.opaque = NO;
    view.clipsToBounds = YES;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [plate insertSubview:view atIndex:0];
    return view;
}

static CAGradientLayer *ShiroPlateLayer(UIView *plate, NSString *name, CALayer *above) {
    for (CALayer *layer in plate.layer.sublayers)
        if ([layer.name isEqualToString:name] && [layer isKindOfClass:[CAGradientLayer class]])
            return (CAGradientLayer *)layer;
    CAGradientLayer *layer = [CAGradientLayer layer];
    layer.name = name;
    layer.actions = [NSDictionary dictionaryWithObjectsAndKeys:
                     [NSNull null], @"bounds", [NSNull null], @"position",
                     [NSNull null], @"colors", [NSNull null], @"cornerRadius",
                     [NSNull null], @"hidden", nil];
    layer.startPoint = CGPointMake(0.5f, 0.0f);
    layer.endPoint = CGPointMake(0.5f, 1.0f);
    if (above) [plate.layer insertSublayer:layer above:above];
    else [plate.layer insertSublayer:layer atIndex:0];
    return layer;
}

/* the plates share the list card colours, so a theme restyles the home screen
   without a second palette. ios7 is the one theme with no light source, so it
   keeps a flat plate */
void ShiroStyleHomePlate(UIView *plate, CGFloat radius, UIColor *base) {
    UIView *backdrop = ShiroPlateBackdrop(plate, YES);
    BOOL light = ShiroThemeIsLight();
    BOOL flat = ShiroThemeIsFlat() && !ShiroThemeIsIos16();
    UIColor *top;
    UIColor *bottom;
    if (ShiroThemeIsMaterial()) {
/* a card is one opaque surface at 2dp: no rim, no sheen, no gradient. the
   surface colour is the theme's card colour unless the caller brings its own */
        top = bottom = base ? base : kCellHi;
        plate.backgroundColor = [UIColor clearColor];
        plate.layer.cornerRadius = radius;
        plate.layer.masksToBounds = NO;
        plate.layer.borderWidth = 0.0f;
        CAGradientLayer *fill = ShiroPlateLayer(backdrop, kShiroPlateFill, nil);
        fill.colors = [NSArray arrayWithObjects:(id)top.CGColor, (id)bottom.CGColor, nil];
        CAGradientLayer *sheen = ShiroPlateLayer(backdrop, kShiroPlateSheen, fill);
        sheen.hidden = YES;
        ShiroMaterialElevate(plate.layer, 2.0f);
        ShiroLayoutHomePlate(plate);
        return;
    }
    if (base) {
        top = ShiroShadeColor(base, 0.12f);
        bottom = ShiroShadeColor(base, -0.10f);
    } else if (ShiroThemeIsIos26()) {
        top = [UIColor colorWithWhite:1.0f alpha:light ? 0.42f : 0.18f];
        bottom = [UIColor colorWithWhite:1.0f alpha:light ? 0.28f : 0.08f];
    } else {
        UIColor *card = kCellHi;
        if (ShiroThemeIsMiside() || ShiroThemeIsFrutigeraero() || ShiroThemeIsBoykisser())
            card = [kCellHi colorWithAlphaComponent:0.86f];
        top = ShiroShadeColor(card, light ? 0.01f : 0.02f);
        bottom = ShiroShadeColor(card, light ? -0.08f : -0.10f);
    }
    if (flat) bottom = top;
    plate.backgroundColor = [UIColor clearColor];
    plate.layer.cornerRadius = radius;
    plate.layer.masksToBounds = NO;
    plate.layer.borderWidth = 0.5f;
    plate.layer.borderColor = (light ? [UIColor colorWithWhite:0.0f alpha:0.10f]
                                     : [UIColor colorWithWhite:1.0f alpha:0.10f]).CGColor;
    CAGradientLayer *fill = ShiroPlateLayer(backdrop, kShiroPlateFill, nil);
    fill.colors = [NSArray arrayWithObjects:(id)top.CGColor, (id)bottom.CGColor, nil];
    CAGradientLayer *sheen = ShiroPlateLayer(backdrop, kShiroPlateSheen, fill);
    sheen.hidden = flat;
    sheen.colors = [NSArray arrayWithObjects:
                    (id)[UIColor colorWithWhite:1.0f alpha:light ? 0.34f : 0.14f].CGColor,
                    (id)[UIColor colorWithWhite:1.0f alpha:0.0f].CGColor, nil];
    plate.layer.shadowColor = [UIColor blackColor].CGColor;
    plate.layer.shadowOffset = CGSizeMake(0.0f, flat ? 0.0f : 2.0f);
    plate.layer.shadowRadius = 3.0f;
    plate.layer.shadowOpacity = flat ? 0.0f : (light ? 0.18f : 0.42f);
    ShiroLayoutHomePlate(plate);
}

/* UIKit owns the button's layers on ios 10, so relief stays in a clipped view */
static void ShiroKeepReliefBelow(UIView *plate) {
    UIView *backdrop = ShiroPlateBackdrop(plate, NO);
    if (backdrop && [plate.subviews objectAtIndex:0] != backdrop)
        [plate sendSubviewToBack:backdrop];
}

void ShiroLayoutHomePlate(UIView *plate) {
    CGRect b = plate.bounds;
    UIView *backdrop = ShiroPlateBackdrop(plate, NO);
    if (!backdrop) return;
    CGFloat radius = plate.layer.cornerRadius;
    ShiroBeginSilentLayers();
    backdrop.frame = b;
    backdrop.layer.cornerRadius = radius;
    CGRect content = backdrop.bounds;
    ShiroKeepReliefBelow(plate);
    for (CALayer *layer in backdrop.layer.sublayers) {
        if ([layer.name isEqualToString:kShiroPlateFill]) {
            layer.frame = content;
            layer.cornerRadius = radius;
        } else if ([layer.name isEqualToString:kShiroPlateSheen]) {
            layer.frame = CGRectMake(1.0f, 1.0f, MAX(0.0f, content.size.width - 2.0f), floorf(MAX(0.0f, content.size.height) * 0.5f));
            layer.cornerRadius = radius > 1.0f ? radius - 1.0f : 0.0f;
        }
    }
/* a shadow without a path renders offscreen on every frame the screen moves */
    plate.layer.shadowPath = plate.layer.shadowOpacity > 0.0f
        ? [UIBezierPath bezierPathWithRoundedRect:b cornerRadius:radius].CGPath : NULL;
    ShiroEndSilentLayers();
}

@implementation ShiroReliefControl
- (void)layoutSubviews {
    [super layoutSubviews];
    ShiroLayoutHomePlate(self);
}
@end

@implementation ShiroReliefButton
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.enabled) return NO;
    /* the 40 pt header plates need finger-sized targets without enlarging their artwork */
    CGRect target = CGRectInset(self.bounds, -MAX(0.0f, (52.0f - self.bounds.size.width) * 0.5f),
                                -MAX(0.0f, (52.0f - self.bounds.size.height) * 0.5f));
    return CGRectContainsPoint(target, point);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    ShiroLayoutHomePlate(self);
}

- (void)setImage:(UIImage *)image forState:(UIControlState)state {
    [super setImage:image forState:state];
    ShiroKeepReliefBelow(self);
}
@end

static void ShiroHomePlainLabel(UILabel *label, UIColor *ink) {
    label.backgroundColor = [UIColor clearColor];
    label.textColor = ink;
    label.shadowColor = nil;
    label.shadowOffset = CGSizeZero;
}

static UILabel *ShiroHomeLabel(UIView *host, NSTextAlignment alignment) {
    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectZero] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textAlignment = alignment;
    label.userInteractionEnabled = NO;
    [host addSubview:label];
    return label;
}

CGFloat ShiroHomePlateRadius(void) {
    CGFloat r = ShiroThemeCardRadius();
    return r < 14.0f ? 14.0f : r;
}

@class ShiroHomeView;
static void ShiroHomeLayoutCard(ShiroHomeView *v, BOOL isFlag);

@implementation ShiroHomeView

- (void)pressDown:(UIView *)view { ShiroPressPop(view, YES); }
- (void)pressUp:(UIView *)view { ShiroPressPop(view, NO); }

- (void)wirePress:(UIControl *)control {
    [control addTarget:self action:@selector(pressDown:)
      forControlEvents:UIControlEventTouchDown];
    [control addTarget:self action:@selector(pressUp:)
      forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                       UIControlEventTouchCancel];
}

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                UIViewAutoresizingFlexibleHeight;

        gear = [[[ShiroReliefButton alloc] initWithFrame:CGRectZero] autorelease];
        [self wirePress:gear];
        [self addSubview:gear];
        stats = [[[ShiroReliefButton alloc] initWithFrame:CGRectZero] autorelease];
        [self wirePress:stats];
        [self addSubview:stats];

        wordmark = ShiroHomeLabel(self, NSTextAlignmentCenter);
        wordmark.text = @"shiro";
        tagline = ShiroHomeLabel(self, NSTextAlignmentCenter);
        tagline.adjustsFontSizeToFitWidth = YES;

        power = [[[ShiroOrbitButton alloc] initWithFrame:CGRectZero] autorelease];
        [self addSubview:power];

        state = ShiroHomeLabel(self, NSTextAlignmentCenter);
        detail = ShiroHomeLabel(self, NSTextAlignmentCenter);
        detail.numberOfLines = 2;
        detail.lineBreakMode = NSLineBreakByTruncatingTail;

        serverCard = [[[ShiroReliefControl alloc] initWithFrame:CGRectZero] autorelease];
        [self wirePress:serverCard];
        [self addSubview:serverCard];
        serverIcon = [[[UIImageView alloc] initWithFrame:CGRectZero] autorelease];
        serverIcon.clipsToBounds = YES;
        [serverCard addSubview:serverIcon];
        serverTitle = ShiroHomeLabel(serverCard, NSTextAlignmentLeft);
        serverSubtitle = ShiroHomeLabel(serverCard, NSTextAlignmentLeft);
        serverChevron = [[[UIImageView alloc] initWithFrame:CGRectZero] autorelease];
        serverChevron.contentMode = UIViewContentModeCenter;
        [serverCard addSubview:serverChevron];
        protocolDot = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
        [self addSubview:protocolDot];
        protocolLine = ShiroHomeLabel(self, NSTextAlignmentLeft);
        protocolLine.lineBreakMode = NSLineBreakByTruncatingTail;

        [self relocalize];
        [self applyTheme];
    }
    return self;
}

- (void)relocalize {
    tagline.text = @"by sqmrak :3";
    gear.accessibilityLabel = ShiroLocalizedText(@"Settings");
    stats.accessibilityLabel = ShiroLocalizedText(@"Statistics");
}

- (void)applyTheme {
    CGFloat radius = ShiroHomePlateRadius();
    ShiroStyleHomePlate(gear, 12.0f, nil);
    ShiroStyleHomePlate(stats, 12.0f, nil);
    ShiroStyleHomePlate(serverCard, radius, nil);
    [gear setImage:TintedIconNamed(@"glyph-gear.png", 22.0f, kInk)
          forState:UIControlStateNormal];
    [stats setImage:TintedIconNamed(@"glyph-chart.png", 22.0f, kInk)
           forState:UIControlStateNormal];

    ShiroHomePlainLabel(wordmark, kAccentBlue);
    ShiroHomePlainLabel(tagline, kInkMuted);
    ShiroHomePlainLabel(state, kInk);
    ShiroHomePlainLabel(serverTitle, kInk);
    ShiroHomePlainLabel(serverSubtitle, kInkMuted);
    ShiroHomePlainLabel(protocolLine, kInkMuted);
    protocolDot.backgroundColor = kAccentBlue;
    serverChevron.image = ShiroIconChevron(14.0f, kInkMuted);

    ShiroHomeLayoutCard(self, _serverIconIsFlag);
    [power applyTheme];
    [self setNeedsLayout];
}

- (void)setServerTitle:(NSString *)title
              subtitle:(NSString *)subtitle
                  icon:(UIImage *)icon
                isFlag:(BOOL)isFlag {
    _serverIconIsFlag = isFlag;
    serverTitle.text = title;
    serverSubtitle.text = subtitle;
    serverIcon.image = icon;
    serverIcon.contentMode = isFlag ? UIViewContentModeScaleToFill
                                    : UIViewContentModeScaleAspectFit;
    ShiroHomeLayoutCard(self, isFlag);
}

- (void)setProtocolLine:(NSString *)text {
    protocolLine.text = text;
    protocolLine.hidden = ![text length];
    protocolDot.hidden = protocolLine.hidden;
}

static void ShiroHomeLayoutCard(ShiroHomeView *v, BOOL isFlag) {
    CGRect b = v->serverCard.bounds;
    CGFloat h = b.size.height;
    CGFloat icon = floorf(h - 24.0f);
    if (icon > 44.0f) icon = 44.0f;
    if (icon < 28.0f) icon = 28.0f;
    CGFloat x = 14.0f;
    v->serverIcon.frame = CGRectMake(x, floorf((h - icon) * 0.5f), icon, icon);
    if (isFlag) {
        v->serverIcon.layer.shadowOpacity = 0.0f;
        v->serverIcon.layer.shadowPath = NULL;
        v->serverIcon.clipsToBounds = YES;
        v->serverIcon.layer.cornerRadius = 8.0f;
        v->serverIcon.backgroundColor = [UIColor clearColor];
    } else {
        v->serverIcon.layer.shadowOpacity = 0.0f;
        v->serverIcon.layer.shadowPath = NULL;
        v->serverIcon.clipsToBounds = YES;
        v->serverIcon.layer.cornerRadius = icon * 0.5f;
        v->serverIcon.backgroundColor = [kAccentBlue colorWithAlphaComponent:0.14f];
    }
    CGFloat chevronW = 14.0f;
    v->serverChevron.frame = CGRectMake(b.size.width - 14.0f - chevronW,
                                        floorf((h - 20.0f) * 0.5f), chevronW, 20.0f);
    CGFloat tx = x + icon + 12.0f;
    CGFloat tw = CGRectGetMinX(v->serverChevron.frame) - 8.0f - tx;
    CGFloat titleSize = h >= 66.0f ? 17.0f : 15.0f;
    v->serverTitle.font = ShiroFontBody(titleSize, YES);
    v->serverSubtitle.font = ShiroFontBody(titleSize - 3.0f, NO);
    CGFloat titleH = ceilf(titleSize * 1.3f);
    CGFloat subH = ceilf((titleSize - 3.0f) * 1.35f);
    CGFloat top = floorf((h - titleH - subH) * 0.5f);
    v->serverTitle.frame = CGRectMake(tx, top, tw, titleH);
    v->serverSubtitle.frame = CGRectMake(tx, top + titleH, tw, subH);
}

/* a phone on its side has no height for a stacked screen, so the button takes
   the left half and the status and server column the right */
- (void)layoutWideFrom:(CGFloat)x0 to:(CGFloat)x1
                   top:(CGFloat)top bottom:(CGFloat)bottom {
    CGFloat H = self.bounds.size.height;
    tagline.hidden = YES;
    CGFloat leftW = floorf((x1 - x0) * 0.44f);
    CGFloat availH = H - top - bottom;
    CGFloat side = MIN(availH, leftW);
    if (side < 80.0f) side = 80.0f;
    power.frame = CGRectMake(x0 + floorf((leftW - side) * 0.5f),
                             top + floorf((availH - side) * 0.5f), side, side);

    CGFloat rx = x0 + leftW + 14.0f;
    CGFloat rw = x1 - rx;
    CGFloat stateH = 24.0f, detailH = 18.0f, cardH = 56.0f, gap = 10.0f;
    CGFloat protocolH = 22.0f;
    CGFloat blockH = stateH + detailH + gap + cardH + gap + protocolH;
    CGFloat y = top + floorf((availH - blockH) * 0.5f);
    if (y < top) y = top;
    state.font = ShiroFontBody(19.0f, YES);
    state.frame = CGRectMake(rx, y, rw, stateH);
    y += stateH;
    detail.numberOfLines = 1;
    detail.frame = CGRectMake(rx, y, rw, detailH);
    y += detailH + gap;
    serverCard.frame = CGRectMake(rx, y, rw, cardH);
    y += cardH + gap;
    protocolDot.frame = CGRectMake(rx + 8.0f, y + 8.0f, 6.0f, 6.0f);
    protocolDot.layer.cornerRadius = 3.0f;
    protocolLine.font = ShiroFontBody(13.0f, NO);
    protocolLine.frame = CGRectMake(rx + 22.0f, y, rw - 22.0f, protocolH);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    CGFloat W = b.size.width;
    CGFloat H = b.size.height;
    if (W < 1.0f || H < 1.0f) return;

    BOOL pad = ShiroHomeIsPad();
    UIEdgeInsets safe = ShiroSafeAreaInsets(self);
    CGFloat top = MAX(safe.top, GetTopOffset());
    CGFloat bottom = safe.bottom + (pad ? 28.0f : 14.0f);
    CGFloat margin = pad ? 28.0f : (W <= 320.0f ? 14.0f : 18.0f);
    CGFloat x0 = safe.left + margin;
    CGFloat x1 = W - safe.right - margin;
    BOOL wide = W > H && H < 560.0f;
    BOOL compact = !pad && !wide && H <= 500.0f;

    CGFloat btn = pad ? 46.0f : 40.0f;
    CGFloat headerY = top + (pad ? 14.0f : 8.0f);
    gear.frame = CGRectMake(x0, headerY, btn, btn);
    stats.frame = CGRectMake(x1 - btn, headerY, btn, btn);

    CGFloat wordSize = pad ? 58.0f : ((compact || wide) ? 32.0f : 44.0f);
    wordmark.font = ShiroFontDisplay(wordSize);
    CGFloat wordH = ceilf(wordSize * 1.2f);
    CGFloat wordX = x0 + btn + 6.0f;
    CGFloat wordW = x1 - x0 - (btn + 6.0f) * 2.0f;
    BOOL wordInHeader = compact || wide;
    CGFloat wordY = wordInHeader ? headerY + floorf((btn - wordH) * 0.5f)
                                 : headerY + btn - 6.0f;
    wordmark.frame = CGRectMake(wordX, wordY, wordW, wordH);

    ShiroHomeLayoutCard(self, _serverIconIsFlag);
    if (wide) {
        [self layoutWideFrom:x0 to:x1 top:headerY + btn + 6.0f bottom:bottom];
        ShiroHomeLayoutCard(self, _serverIconIsFlag);
        return;
    }
    tagline.hidden = NO;
    CGFloat tagSize = pad ? 17.0f : (compact ? 12.0f : 14.0f);
    tagline.font = ShiroFontBody(tagSize, NO);
    CGFloat tagH = ceilf(tagSize * 1.4f);
    CGFloat tagY = wordInHeader ? headerY + btn - 2.0f : wordY + wordH - 4.0f;
    tagline.frame = CGRectMake(wordX, tagY, wordW, tagH);
    CGFloat orbTop = tagY + tagH + (compact ? 4.0f : 12.0f);

    CGFloat colW = x1 - x0;
    if (colW > (pad ? 480.0f : 440.0f)) colW = pad ? 480.0f : 440.0f;
    CGFloat colX = floorf((W - colW) * 0.5f);
    CGFloat cardH = pad ? 78.0f : (compact ? 58.0f : 68.0f);
    CGFloat protocolH = compact ? 20.0f : 24.0f;
    CGFloat y = H - bottom - protocolH;
    protocolDot.frame = CGRectMake(colX + 8.0f, y + floorf((protocolH - 6.0f) * 0.5f),
                                   6.0f, 6.0f);
    protocolDot.layer.cornerRadius = 3.0f;
    protocolLine.font = ShiroFontBody(pad ? 15.0f : 13.0f, NO);
    protocolLine.frame = CGRectMake(colX + 22.0f, y, colW - 22.0f, protocolH);
    y -= (compact ? 6.0f : 10.0f) + cardH;
    serverCard.frame = CGRectMake(colX, y, colW, cardH);

    CGFloat detailSize = pad ? 16.0f : 14.0f;
    CGFloat detailH = compact ? ceilf(detailSize * 1.3f) : ceilf(detailSize * 2.5f);
    detail.numberOfLines = compact ? 1 : 2;
    y -= (compact ? 8.0f : 14.0f) + detailH;
    detail.frame = CGRectMake(colX, y, colW, detailH);
    CGFloat stateSize = pad ? 26.0f : (compact ? 19.0f : 22.0f);
    state.font = ShiroFontBody(stateSize, YES);
    CGFloat stateH = ceilf(stateSize * 1.3f);
    y -= stateH;
    state.frame = CGRectMake(colX, y, colW, stateH);

    CGFloat avail = y - (compact ? 4.0f : 10.0f) - orbTop;
    CGFloat side = MIN(avail, colW * (pad ? 0.7f : 0.82f));
    CGFloat maxSide = pad ? 380.0f : 320.0f;
    if (side > maxSide) side = maxSide;
    if (side < 90.0f) side = 90.0f;
    power.frame = CGRectMake(floorf((W - side) * 0.5f),
                             orbTop + floorf((avail - side) * 0.5f), side, side);

    ShiroHomeLayoutCard(self, _serverIconIsFlag);
}

@end
