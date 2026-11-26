#import "shiro_animation.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <math.h>

/* a key every 4 ms: core animation interpolates linearly between keys, so a
   frame of a 120 Hz screen never lands between two far apart ones */
#define MOTION_KEYS_PER_SECOND 240.0
/* a press needs about eight frames at 60 Hz to look like a movement and not like
   a flicker of the picture */
#define BOUNCE_PRESS_SECONDS 0.14
/* how far a screen travels as it comes in or goes away, as fractions of the width: the screen that
   arrives or leaves moves 18 percent, the one underneath 8 percent, as in the android build */
#define SCREEN_TRAVEL 0.18f
#define SCREEN_BACKSTEP 0.08f
/* the screen underneath dims to this while another one is over it */
#define SCREEN_DIMMED 0.6f
/* a picture may hold this many pixels, which keeps a full screen tablet picture
   from asking for 30 MB */
#define SNAPSHOT_PIXELS_MAX 4000000.0

static NSString *const kMotionKey = @"shiro.motion";
static NSString *const kEnterKey = @"shiro.enter";
static NSString *const kBounceKey = @"shiro.bounce";

BOOL ShiroReduceMotion(void) {
    BOOL (*enabled)(void) = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "UIAccessibilityIsReduceMotionEnabled");
    return enabled ? enabled() : NO;
}

/* the delegate of a move: core animation retains it for the run, the block runs
   once at the end */
@interface ShiroMotionCompletion : NSObject {
    void (^_completion)(BOOL);
}
- (id)initWithCompletion:(void (^)(BOOL))completion;
@end

@implementation ShiroMotionCompletion
- (id)initWithCompletion:(void (^)(BOOL))completion {
    if ((self = [super init])) _completion = [completion copy];
    return self;
}
- (void)dealloc {
    [_completion release];
    [super dealloc];
}
- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)finished {
    (void)animation;
    if (_completion) _completion(finished);
}
@end

/* the transform and the alpha at every key of a curve, from one state to another.
   the opacity never overshoots, even when the position of a spring does */
static CAAnimationGroup *MotionGroup(CGAffineTransform from, CGFloat fromAlpha,
                                     CGAffineTransform to, CGFloat toAlpha,
                                     shiro_motion_curve curve) {
    NSTimeInterval span = shiro_motion_duration(curve);
    NSUInteger keys = MAX((NSUInteger)2, (NSUInteger)ceil(span * MOTION_KEYS_PER_SECOND) + 1);
    NSMutableArray *transforms = [NSMutableArray arrayWithCapacity:keys];
    NSMutableArray *opacities = [NSMutableArray arrayWithCapacity:keys];
    for (NSUInteger i = 0; i < keys; ++i) {
        CGFloat progress = (CGFloat)shiro_motion_progress(curve, (double)i / (double)(keys - 1));
        CGAffineTransform value = CGAffineTransformMake(
            from.a + (to.a - from.a) * progress, from.b + (to.b - from.b) * progress,
            from.c + (to.c - from.c) * progress, from.d + (to.d - from.d) * progress,
            from.tx + (to.tx - from.tx) * progress, from.ty + (to.ty - from.ty) * progress);
        [transforms addObject:[NSValue valueWithCATransform3D:CATransform3DMakeAffineTransform(value)]];
        CGFloat shown = progress < 0.0f ? 0.0f : (progress > 1.0f ? 1.0f : progress);
        [opacities addObject:[NSNumber numberWithDouble:fromAlpha + (toAlpha - fromAlpha) * shown]];
    }
    CAKeyframeAnimation *movement = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
    movement.values = transforms;
    CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    fade.values = opacities;
    movement.duration = fade.duration = span;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.duration = span;
    group.animations = [NSArray arrayWithObjects:movement, fade, nil];
    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    return group;
}

void ShiroMotionAnimate(UIView *view, CGAffineTransform transform, CGFloat alpha,
                        shiro_motion_curve curve, NSTimeInterval delay,
                        void (^completion)(BOOL finished)) {
    CALayer *layer = view.layer;
    CALayer *visible = [layer animationForKey:kMotionKey] ? [layer presentationLayer] : nil;
    CGAffineTransform from = visible ? CATransform3DGetAffineTransform(visible.transform) : view.transform;
    CGFloat fromAlpha = visible ? visible.opacity : view.alpha;
    [layer removeAnimationForKey:kMotionKey];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    view.transform = transform;
    view.alpha = alpha;
    [CATransaction commit];
    if (!view.window || ![UIView areAnimationsEnabled] || ShiroReduceMotion()) {
        if (completion) completion(YES);
        return;
    }
    CAAnimationGroup *group = MotionGroup(from, fromAlpha, transform, alpha, curve);
    if (delay > 0) {
        group.beginTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil] + delay;
        group.fillMode = kCAFillModeBackwards;
    }
    if (completion)
        group.delegate = (id)[[[ShiroMotionCompletion alloc] initWithCompletion:completion] autorelease];
    [layer addAnimation:group forKey:kMotionKey];
}

void ShiroMotionEnter(UIView *view, CGAffineTransform from, CGFloat fromAlpha,
                      shiro_motion_curve curve, NSTimeInterval delay) {
    CALayer *layer = view.layer;
    [layer removeAnimationForKey:kEnterKey];
    if (!(view.window || view.superview) || ![UIView areAnimationsEnabled] || ShiroReduceMotion())
        return;
    CAAnimationGroup *group = MotionGroup(from, fromAlpha, view.transform, view.alpha, curve);
    if (delay > 0) {
        group.beginTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil] + delay;
        group.fillMode = kCAFillModeBackwards;
    }
    [layer addAnimation:group forKey:kEnterKey];
}

/* the scale the layer shows at this moment, which is where a new bounce starts from */
static CGFloat BounceShownScale(CALayer *layer) {
    CALayer *shown = [layer animationForKey:kBounceKey] ? [layer presentationLayer] : nil;
    NSNumber *scale = shown ? [shown valueForKeyPath:@"transform.scale"] : nil;
    return scale ? (CGFloat)[scale doubleValue] : 1.0f;
}

static BOOL BounceAnimates(UIView *view) {
    return view.window && [UIView areAnimationsEnabled] && !ShiroReduceMotion();
}

void ShiroMotionBounce(UIView *view, BOOL pressed, CGFloat depth) {
    CALayer *layer = view.layer;
    if (pressed) {
        if (!BounceAnimates(view)) return;
        CABasicAnimation *shrink = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        shrink.fromValue = [NSNumber numberWithDouble:BounceShownScale(layer)];
        shrink.toValue = [NSNumber numberWithDouble:1.0 - depth];
        shrink.duration = BOUNCE_PRESS_SECONDS;
        shrink.fillMode = kCAFillModeForwards;
        shrink.removedOnCompletion = NO;
        shrink.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.25f :0.0f :0.15f :1.0f];
        [layer addAnimation:shrink forKey:kBounceKey];
        return;
    }
    if (![layer animationForKey:kBounceKey]) return;
    CGFloat from = BounceShownScale(layer);
    if (!BounceAnimates(view)) {
        [layer removeAnimationForKey:kBounceKey];
        return;
    }
    /* the release swings back past the size and settles on the loose spring of
       shiro_motion, which leaves at rest. the old back ease left at eight times
       its average speed, which is the snap a lifted button used to have */
    NSTimeInterval span = shiro_motion_duration(SHIRO_MOTION_WOBBLE);
    NSUInteger keys = (NSUInteger)ceil(span * MOTION_KEYS_PER_SECOND) + 1;
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:keys];
    for (NSUInteger i = 0; i < keys; ++i) {
        double progress = shiro_motion_progress(SHIRO_MOTION_WOBBLE, (double)i / (double)(keys - 1));
        [values addObject:[NSNumber numberWithDouble:from + (1.0 - from) * progress]];
    }
    CAKeyframeAnimation *spring = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    spring.values = values;
    spring.duration = span;
    spring.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [layer addAnimation:spring forKey:kBounceKey];
}

BOOL ShiroMotionBouncing(UIView *view) {
    return [view.layer animationForKey:kBounceKey] != nil;
}

/* the one target of every attached control, so a control needs no object of its own */
@interface ShiroBounceTarget : NSObject
+ (ShiroBounceTarget *)shared;
- (void)press:(UIControl *)control;
- (void)lift:(UIControl *)control;
@end

static char kBounceDepthKey;

@implementation ShiroBounceTarget

+ (ShiroBounceTarget *)shared {
    static ShiroBounceTarget *target = nil;
    if (!target) target = [[ShiroBounceTarget alloc] init];
    return target;
}

- (void)press:(UIControl *)control {
    ShiroMotionBounce(control, YES, (CGFloat)[objc_getAssociatedObject(control, &kBounceDepthKey) doubleValue]);
}

- (void)lift:(UIControl *)control {
    ShiroMotionBounce(control, NO, 0.0f);
}

@end

void ShiroMotionAttachBounce(UIControl *control, CGFloat depth) {
    ShiroBounceTarget *target = [ShiroBounceTarget shared];
    objc_setAssociatedObject(control, &kBounceDepthKey, [NSNumber numberWithDouble:depth],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [control addTarget:target action:@selector(press:)
      forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [control addTarget:target action:@selector(lift:)
      forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                       UIControlEventTouchCancel | UIControlEventTouchDragExit];
}

#define STAGGER_ROWS_MAX 10
#define STAGGER_STEP_SECONDS 0.03
#define STAGGER_RISE 16.0f
static char kStaggerKey;

void ShiroMotionRiseRows(UITableView *table) {
    if (!table) return;
    [table layoutIfNeeded];
    NSUInteger index = 0;
    for (UITableViewCell *cell in [table visibleCells]) {
        if (index >= STAGGER_ROWS_MAX) break;
        ShiroMotionEnter(cell, CGAffineTransformMakeTranslation(0.0f, STAGGER_RISE), 0.0f,
                         SHIRO_MOTION_ENTER, STAGGER_STEP_SECONDS * (double)index);
        ++index;
    }
}

void ShiroMotionStaggerRows(UITableView *table) {
    if (!table || objc_getAssociatedObject(table, &kStaggerKey)) return;
    [table layoutIfNeeded];
    if (![[table visibleCells] count]) return;
    objc_setAssociatedObject(table, &kStaggerKey, [NSNumber numberWithBool:YES],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ShiroMotionRiseRows(table);
}

UIImageView *ShiroMotionSnapshot(UIView *view) {
    CGSize size = view.bounds.size;
    if (size.width < 1.0f || size.height < 1.0f) return nil;
    CGFloat scale = [UIScreen mainScreen].scale;
    CGFloat limit = (CGFloat)sqrt(SNAPSHOT_PIXELS_MAX / ((double)size.width * (double)size.height));
    if (scale > limit) scale = limit;
    UIGraphicsBeginImageContextWithOptions(size, NO, scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        UIGraphicsEndImageContext();
        return nil;
    }
    [view.layer renderInContext:context];
    UIImage *picture = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!picture) return nil;
    UIImageView *shot = [[[UIImageView alloc] initWithImage:picture] autorelease];
    shot.frame = view.frame;
    shot.userInteractionEnabled = NO;
    return shot;
}

void ShiroMotionSwap(UIView *leaving, UIView *entering, int direction) {
    if (!leaving) return;
    if (!entering.window || ![UIView areAnimationsEnabled] || ShiroReduceMotion()) {
        [leaving removeFromSuperview];
        return;
    }
    CGFloat width = entering.bounds.size.width;
    void (^done)(BOOL) = ^(BOOL finished) {
        (void)finished;
        [leaving removeFromSuperview];
    };
    if (direction > 0) {
        /* the new screen slides in from the right and fades in over the old one, which steps back
           and dims. the picture lies under the new screen, so only one layer is ever transparent
           and the window behind never shows */
        ShiroMotionEnter(entering, CGAffineTransformMakeTranslation(width * SCREEN_TRAVEL, 0.0f), 0.0f,
                         SHIRO_MOTION_SCREEN_IN, 0.0);
        ShiroMotionAnimate(leaving, CGAffineTransformMakeTranslation(-width * SCREEN_BACKSTEP, 0.0f),
                           SCREEN_DIMMED, SHIRO_MOTION_SCREEN_UNDER, 0.0, done);
        return;
    }
    /* going back: the picture of the screen above slides off to the right and fades while the
       screen below returns from its step back */
    ShiroMotionEnter(entering, CGAffineTransformMakeTranslation(-width * SCREEN_BACKSTEP, 0.0f),
                     SCREEN_DIMMED, SHIRO_MOTION_SCREEN_IN, 0.0);
    ShiroMotionAnimate(leaving, CGAffineTransformMakeTranslation(width * SCREEN_TRAVEL, 0.0f), 0.0f,
                       SHIRO_MOTION_SCREEN_OUT, 0.0, done);
}

@implementation ShiroNavigationController

/* the swap needs the screen on show and a stack that already has something under
   the new top. the picture is taken before the stack changes and laid over the
   new screen, which is already in its final state */
- (BOOL)swapsScreens:(BOOL)animated {
    return animated && self.view.window && [self.viewControllers count] > 0 &&
           [UIView areAnimationsEnabled] && !ShiroReduceMotion();
}

- (void)runSwap:(int)direction change:(void (^)(void))change {
    UIImageView *shot = ShiroMotionSnapshot(self.view);
    change();
    if (!shot) return;
    UIView *content = self.topViewController.view;
    /* the picture of the old screen goes under a new screen and over a screen that returns */
    if (direction > 0 && content.superview) [content.superview insertSubview:shot belowSubview:content];
    else [self.view addSubview:shot];
    ShiroMotionSwap(shot, content, direction);
}

- (void)pushViewController:(UIViewController *)controller animated:(BOOL)animated {
    if (![self swapsScreens:animated]) {
        [super pushViewController:controller animated:animated];
        return;
    }
    [self runSwap:1 change:^{ [super pushViewController:controller animated:NO]; }];
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated {
    if (![self swapsScreens:animated] || [self.viewControllers count] < 2)
        return [super popViewControllerAnimated:animated];
    __block UIViewController *popped = nil;
    [self runSwap:-1 change:^{ popped = [super popViewControllerAnimated:NO]; }];
    return popped;
}

- (NSArray *)popToViewController:(UIViewController *)controller animated:(BOOL)animated {
    if (![self swapsScreens:animated] || self.topViewController == controller)
        return [super popToViewController:controller animated:animated];
    __block NSArray *popped = nil;
    [self runSwap:-1 change:^{ popped = [super popToViewController:controller animated:NO]; }];
    return popped;
}

- (NSArray *)popToRootViewControllerAnimated:(BOOL)animated {
    if (![self swapsScreens:animated] || [self.viewControllers count] < 2)
        return [super popToRootViewControllerAnimated:animated];
    __block NSArray *popped = nil;
    [self runSwap:-1 change:^{ popped = [super popToRootViewControllerAnimated:NO]; }];
    return popped;
}

@end

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000

/* the modal screens move as the screens of the android build do: the one that arrives slides in
   from the right and fades in, the one below steps back and dims, and on the way out the screen
   above slides off to the right while the one below returns. the real views take part, so
   nothing is left standing where a picture of it leaves */
@interface ShiroModalTransition : NSObject <UIViewControllerAnimatedTransitioning,
                                            UIViewControllerTransitioningDelegate> {
    BOOL _presenting;
}
+ (ShiroModalTransition *)shared;
@end

@implementation ShiroModalTransition

+ (ShiroModalTransition *)shared {
    static ShiroModalTransition *shared = nil;
    if (!shared) shared = [[ShiroModalTransition alloc] init];
    return shared;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                presentingController:(UIViewController *)presenting
                                                                    sourceController:(UIViewController *)source {
    (void)presented; (void)presenting; (void)source;
    ShiroModalTransition *animator = [[[ShiroModalTransition alloc] init] autorelease];
    animator->_presenting = YES;
    return animator;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    (void)dismissed;
    ShiroModalTransition *animator = [[[ShiroModalTransition alloc] init] autorelease];
    animator->_presenting = NO;
    return animator;
}

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context {
    (void)context;
    return shiro_motion_duration(_presenting ? SHIRO_MOTION_SCREEN_IN : SHIRO_MOTION_SCREEN_OUT);
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
    UIViewController *to = [context viewControllerForKey:UITransitionContextToViewControllerKey];
    UIViewController *from = [context viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIView *container = [context containerView];
    UIView *toView = to.view;
    UIView *fromView = from.view;
    CGFloat width = container.bounds.size.width;
    toView.frame = container.bounds;
    void (^finish)(BOOL) = ^(BOOL finished) {
        (void)finished;
        /* the view that stays behind must not keep the step back it was animated to */
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        fromView.transform = CGAffineTransformIdentity;
        fromView.alpha = 1.0f;
        [CATransaction commit];
        [context completeTransition:![context transitionWasCancelled]];
    };
    if (_presenting) {
        [container addSubview:toView];
        toView.transform = CGAffineTransformMakeTranslation(width * SCREEN_TRAVEL, 0.0f);
        toView.alpha = 0.0f;
        ShiroMotionAnimate(fromView, CGAffineTransformMakeTranslation(-width * SCREEN_BACKSTEP, 0.0f),
                           SCREEN_DIMMED, SHIRO_MOTION_SCREEN_UNDER, 0.0, nil);
        ShiroMotionAnimate(toView, CGAffineTransformIdentity, 1.0f, SHIRO_MOTION_SCREEN_IN, 0.0, finish);
        return;
    }
    [container insertSubview:toView belowSubview:fromView];
    toView.transform = CGAffineTransformMakeTranslation(-width * SCREEN_BACKSTEP, 0.0f);
    toView.alpha = SCREEN_DIMMED;
    ShiroMotionAnimate(toView, CGAffineTransformIdentity, 1.0f, SHIRO_MOTION_SCREEN_IN, 0.0, nil);
    ShiroMotionAnimate(fromView, CGAffineTransformMakeTranslation(width * SCREEN_TRAVEL, 0.0f), 0.0f,
                       SHIRO_MOTION_SCREEN_OUT, 0.0, finish);
}

@end

void ShiroMotionPresent(UIViewController *host, UIViewController *vc) {
    /* a card that ios 13 and later would draw over the host cannot slide like a screen, so the
       presentation covers the whole window as it always did before ios 13 */
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    vc.transitioningDelegate = [ShiroModalTransition shared];
    [host presentViewController:vc animated:YES completion:nil];
}

void ShiroMotionDismiss(UIViewController *vc, void (^completion)(void)) {
    [vc dismissViewControllerAnimated:YES completion:completion];
}

#else

/* the 6.1 sdk of the armv7 slice has no custom transitions, so the system slide runs there */
void ShiroMotionPresent(UIViewController *host, UIViewController *vc) {
    [host presentViewController:vc animated:YES completion:nil];
}

void ShiroMotionDismiss(UIViewController *vc, void (^completion)(void)) {
    [vc dismissViewControllerAnimated:YES completion:completion];
}

#endif
