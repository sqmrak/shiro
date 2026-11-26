#ifndef SHIRO_DIALOG_H
#define SHIRO_DIALOG_H

#import <UIKit/UIKit.h>

/* the app's own popup: a plate in the colours of the current theme with a sticker leaning over
   its top edge. it replaces
   UIAlertView, UIAlertController and UIActionSheet, which draw differently on
   every ios from 5 to 16, ignore the theme and cannot be animated on the app's
   own curves. it lives in a window of its own, so it covers modal screens and
   keeps working while the host rotates */

typedef enum {
    ShiroDialogButtonNormal = 0,
    ShiroDialogButtonCancel,
    ShiroDialogButtonDestructive
} ShiroDialogButtonStyle;

@interface ShiroDialog : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *message;
/* a tap outside the card runs the cancel button, or only closes the card when
   there is none. yes by default only for a dialog that has a cancel button */
@property (nonatomic, assign) BOOL dismissOnBackdrop;
/* the field added by addTextField, nil before that */
@property (nonatomic, readonly) UITextField *textField;

+ (ShiroDialog *)dialogWithTitle:(NSString *)title message:(NSString *)message;

/* every button closes the card first and then runs its handler. a cancel button
   sits on the left, the last normal button is the filled one */
- (void)addButtonWithTitle:(NSString *)title
                     style:(ShiroDialogButtonStyle)style
                   handler:(void (^)(ShiroDialog *dialog))handler;
/* one row of a list of choices, the way an action sheet shows them */
- (void)addItemWithTitle:(NSString *)title
                 handler:(void (^)(ShiroDialog *dialog))handler;
- (UITextField *)addTextFieldWithText:(NSString *)text
                          placeholder:(NSString *)placeholder
                             keyboard:(UIKeyboardType)keyboard;

- (void)show;
/* closes the card without running any handler */
- (void)dismiss;

@end

/* the questions the screens ask. every string goes through the app's
   localization here, so a screen passes the english text */
void ShiroDialogAlert(NSString *title, NSString *message);
void ShiroDialogConfirm(NSString *title, NSString *message, NSString *action,
                      BOOL destructive, void (^confirm)(void));
/* a list of choices and a cancel button. the block gets the index of the label,
   or -1 when the card was closed without a pick */
void ShiroDialogMenu(NSString *title, NSString *message, NSArray *labels,
                   void (^pick)(NSInteger index));
/* one line of text. the block gets the text as typed, or nil when the card was
   closed with the cancel button */
void ShiroDialogPrompt(NSString *title, NSString *message, NSString *text,
                     NSString *placeholder, UIKeyboardType keyboard, NSString *action,
                     void (^done)(NSString *text));

#endif
