#ifndef SHIRO_HOME_VIEW_H
#define SHIRO_HOME_VIEW_H

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

/* plates that refit their relief whenever uikit resizes them */
@interface ShiroReliefControl : UIControl
@end

@interface ShiroReliefButton : UIButton
@end

/* the power control with a dot circling its rim. the dot turns on the render
   server, so an armv7 cpu pays nothing per frame while it moves. shiro-material
   draws it as a floating action button instead: a filled disc that changes
   colour with the tunnel state and a progress ring that turns while it dials */
@interface ShiroOrbitButton : UIControl {
    CAShapeLayer *_track;
    CAShapeLayer *_halo;
    CAShapeLayer *_ring;
    CAShapeLayer *_face;
    CAGradientLayer *_faceFill;
    CAGradientLayer *_faceSheen;
    CAShapeLayer *_glyph;
    CALayer      *_orbit;
    CAShapeLayer *_trail;
    CAShapeLayer *_dot;
    CAShapeLayer *_spinner;
    CGFloat       _faceRadius;
    NSString     *_stateKey;
    BOOL          _running;
    BOOL          _orbitShown;
    CGSize        _laidSize;
}
/* idle, connecting, connected or error */
- (void)setStateKey:(NSString *)key;
/* the dot leaves the ring while it cannot spin */
- (void)setRunning:(BOOL)running;
- (void)applyTheme;
@end

/* everything the home screen shows. the controller owns the behaviour and
   wires the controls; this view only places and paints them */
@interface ShiroHomeView : UIView {
@public
    UIButton         *gear;
    UIButton         *stats;
    UILabel          *wordmark;
    UILabel          *tagline;
    ShiroOrbitButton *power;
    UILabel          *state;
    UILabel          *detail;
    ShiroReliefControl *serverCard;
    UIImageView      *serverIcon;
    UILabel          *serverTitle;
    UILabel          *serverSubtitle;
    UIImageView      *serverChevron;
    UIView           *protocolDot;
    UILabel          *protocolLine;
    BOOL              _serverIconIsFlag;
}
- (void)applyTheme;
/* a server badge keeps its own colours and shadow, any other icon is a glyph
   on an accent disc */
- (void)setServerTitle:(NSString *)title
              subtitle:(NSString *)subtitle
                  icon:(UIImage *)icon
                isFlag:(BOOL)isFlag;
- (void)relocalize;
- (void)setProtocolLine:(NSString *)text;
@end

/* the rounded card every home and picker control sits on: list colours lit
   from above, a sheen and a short shadow. base nil takes the card colour */
void ShiroStyleHomePlate(UIView *plate, CGFloat radius, UIColor *base);
/* refit the fill, sheen and shadow to the plate's current size */
void ShiroLayoutHomePlate(UIView *plate);
CGFloat ShiroHomePlateRadius(void);


#endif
