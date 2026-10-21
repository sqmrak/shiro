#ifndef SHIRO_UI_CHROME_PRIV_H
#define SHIRO_UI_CHROME_PRIV_H

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "material.h"

/* bar and dome share size/color keys so recolor skips full rebuilds */
extern char ShiroStyleSizeKey;
extern char ShiroStyleTopKey;
extern char ShiroStyleBotKey;

CAGradientLayer *ShiroNamedGradientLayer(CALayer *parent, NSString *name);
BOOL ShiroStyleSizeMatches(UIView *v, CGSize sz);
void ShiroStyleRemember(UIView *v, CGSize sz, UIColor *top, UIColor *bottom);
void ShiroApplyShadowPath(CALayer *layer, CGFloat radius);
UIBezierPath *ShiroHeartPath(CGRect r);
CAShapeLayer *ShiroHeartMaskLayer(CGRect bounds);

#endif
