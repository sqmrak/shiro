#ifndef SHIRO_ANIMATION_H
#define SHIRO_ANIMATION_H

#import <UIKit/UIKit.h>

#include "shiro_motion.h"

/* the movement of the interface, drawn by the app instead of the system. every
   move is a sampled curve of shiro_motion, so a spring wobbles the same on ios
   4.3, which has no CASpringAnimation, as on ios 16. with reduced motion, or a
   view that is not on screen, a view only takes its final state */

/* true when the person asked the system for less motion; the entry is looked up
   at run time, since ios 4.3 to 7 have no such setting */
BOOL ShiroReduceMotion(void);

/* a view takes its final transform and alpha at once and plays the way there.
   a running move of the view is retargeted from what is on screen, so a leave
   that begins during an entry never jumps. the completion runs at once when
   nothing is drawn */
void ShiroMotionAnimate(UIView *view, CGAffineTransform transform, CGFloat alpha,
                        shiro_motion_curve curve, NSTimeInterval delay,
                        void (^completion)(BOOL finished));
/* the view is already in its final state: this plays the way in from a
   transform and an alpha without touching it, and a later call replaces a run
   that has not ended */
void ShiroMotionEnter(UIView *view, CGAffineTransform from, CGFloat fromAlpha,
                      shiro_motion_curve curve, NSTimeInterval delay);

/* the press of a control: it shrinks by depth (0.05 is five percent) while a
   finger is on it and springs back past its size when the finger leaves */
void ShiroMotionAttachBounce(UIControl *control, CGFloat depth);
void ShiroMotionBounce(UIView *view, BOOL pressed, CGFloat depth);
/* a press or a release of ShiroMotionBounce is still running on the view */
BOOL ShiroMotionBouncing(UIView *view);

/* the rows of a list that is on show for the first time rise in one after the
   other, the first ten only. a table that was staggered once is left alone, so a
   reload or a return to the screen does not replay it */
void ShiroMotionStaggerRows(UITableView *table);
/* the same rise, every time it is called: for a list that comes on show again,
   such as a screen that slides over another one */
void ShiroMotionRiseRows(UITableView *table);

/* the picture of a view as it is drawn now, in an image view at the view's
   frame, or nil when the view has no size */
UIImageView *ShiroMotionSnapshot(UIView *view);

/* a screen swap, as the screens of the android build move: leaving is the picture of what was on
   screen, entering is the live screen. direction 1 is a push: entering slides in from the right
   and fades in, leaving steps back and dims. direction -1 is a pop: leaving slides off to the
   right and fades, entering returns from its step back. the picture is taken out when it is done */
void ShiroMotionSwap(UIView *leaving, UIView *entering, int direction);

/* the app's navigation controller: pushes and pops swap the screens on the
   curves above instead of the system slide. an edge swipe back keeps the system
   transition, which has to follow the finger */
@interface ShiroNavigationController : UINavigationController
@end

#endif
