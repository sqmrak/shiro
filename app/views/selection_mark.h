#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
void ShiroStyleBadgeShadow(UIView *view, CGFloat radius);
@interface ShiroRadioView : UIView {
    CAShapeLayer *_ring;
    CAShapeLayer *_dot;
    BOOL _checked;
}
- (void)setChecked:(BOOL)checked;
- (void)applyTheme;
@end
