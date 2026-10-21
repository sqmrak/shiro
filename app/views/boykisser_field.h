#ifndef SHIRO_BOYKISSER_FIELD_H
#define SHIRO_BOYKISSER_FIELD_H

#import <UIKit/UIKit.h>

/* bounded falling sprites shared by the home and about screens */
@interface ShiroBoykisserField : UIView
- (id)initWithFrame:(CGRect)frame spriteName:(NSString *)name;
- (void)start;
- (void)stop;
/* pause off-screen to save cpu */
- (void)setPaused:(BOOL)paused;
- (BOOL)isRunning;
@end

#endif
