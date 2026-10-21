#import "screen_controller.h"
#ifndef SHIRO_DEV_CONSOLE_VC_H
#define SHIRO_DEV_CONSOLE_VC_H

#import <UIKit/UIKit.h>

@class ShiroControl;

/* the control socket without ssh: type a verb, read what the daemon answered.
   shiroctl already speaks this protocol from a terminal, and needing a second
   machine to send one line is the reason this screen exists */
@interface ShiroConsoleController : ShiroScreenController <UITextFieldDelegate> {
    UITextView   *_out;
    UITextField  *_input;
    ShiroControl *_ctl;
    NSMutableArray *_history;
    NSInteger     _historyAt;
    BOOL          _busy;
}

- (id)initWithControl:(ShiroControl *)control;

@end

#endif
