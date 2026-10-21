#import "selection_mark.h"
#import "ui_theme.h"
#include <math.h>
void ShiroStyleBadgeShadow(UIView *view, CGFloat radius) {
    view.clipsToBounds = NO;
    view.layer.masksToBounds = NO;
    view.layer.cornerRadius = 0.0f;
    view.backgroundColor = [UIColor clearColor];
    view.layer.borderWidth = 0.0f;
    view.layer.shadowColor = [UIColor blackColor].CGColor;
    view.layer.shadowOpacity = 0.35f;
    view.layer.shadowRadius = 2.0f;
    view.layer.shadowOffset = CGSizeMake(0.0f, 1.0f);
    if (view.bounds.size.width > 1.0f)
        view.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:view.bounds
                                                           cornerRadius:radius].CGPath;
}

@implementation ShiroRadioView

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        _ring = [[CAShapeLayer alloc] init];
        _ring.fillColor = [UIColor clearColor].CGColor;
        _ring.lineWidth = 1.5f;
        [self.layer addSublayer:_ring];
        _dot = [[CAShapeLayer alloc] init];
        [self.layer addSublayer:_dot];
        [self applyTheme];
    }
    return self;
}

- (void)dealloc {
    [_ring release];
    [_dot release];
    [super dealloc];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    CGFloat side = MIN(b.size.width, b.size.height);
    CGPoint c = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));
    ShiroBeginSilentLayers();
    _ring.frame = b;
    _dot.frame = b;
    _ring.path = [UIBezierPath bezierPathWithArcCenter:c radius:side * 0.5f - 1.0f
        startAngle:0.0f endAngle:(CGFloat)(M_PI * 2.0) clockwise:YES].CGPath;
    _dot.path = [UIBezierPath bezierPathWithArcCenter:c radius:side * 0.25f
        startAngle:0.0f endAngle:(CGFloat)(M_PI * 2.0) clockwise:YES].CGPath;
    ShiroEndSilentLayers();
}

- (void)applyTheme {
    ShiroBeginSilentLayers();
    _ring.strokeColor = (_checked ? kAccentBlue
                                  : [kInkMuted colorWithAlphaComponent:0.55f]).CGColor;
    _ring.lineWidth = _checked ? 2.0f : 1.5f;
    _dot.fillColor = kAccentBlue.CGColor;
    _dot.hidden = !_checked;
    ShiroEndSilentLayers();
}

- (void)setChecked:(BOOL)checked {
    _checked = checked;
    [self applyTheme];
}

@end
