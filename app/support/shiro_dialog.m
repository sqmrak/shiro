#import "shiro_dialog.h"
#import "app_common.h"
#import "card_kit.h"
#import "ios_compat.h"
#import "ui_theme.h"
#import "shiro_animation.h"

#import <QuartzCore/QuartzCore.h>
#include <math.h>
#import <objc/message.h>

#define DIALOG_CARD_MAX 400.0f
#define DIALOG_MARGIN 20.0f
#define DIALOG_BUTTON_H 44.0f
#define DIALOG_ITEM_H 46.0f
#define DIALOG_PAD 18.0f

#define DLG_INK() kInk
#define DLG_MUTED() kInkMuted
#define DLG_ACCENT() (kAccentBlue ? kAccentBlue : [UIColor colorWithWhite:0.4f alpha:1.0f])
#define DLG_WELL() (kWell ? kWell : [UIColor colorWithWhite:0.5f alpha:0.15f])
#define DLG_SEPARATOR() [kInk colorWithAlphaComponent:ShiroThemeIsLight() ? 0.14f : 0.22f]
#define DLG_DESTRUCTIVE() [UIColor colorWithRed:0.86f green:0.22f blue:0.22f alpha:1.0f]
#define DLG_FONT(size, bold) ShiroFontBody(size, bold)
#define DLG_TEXT_SIZE(text, font, width) ShiroTextSize(text, font, width)
#define DLG_LOCALIZED(text) ShiroLocalizedText(text)
/* the filled button is a vertical gradient of the accent, as the other controls of the app */
#define DLG_GLOSSY 1
#define DLG_BUTTON_RADIUS fmaxf(8.0f, ShiroThemeCardRadius())
#define DLG_SHADE(tone, delta) ShiroShadeColor(tone, delta)
#define DLG_ON_FILL(tone) ShiroPillLabelColor(tone)
#define DLG_MAKE_CARD(frame) [[ShiroCardView alloc] initWithFrame:frame]


/* one sticker leans over the top edge of every card. imageNamed picks the 2x or 3x file, and
   the one picture is small enough to stay cached */
static UIImage *StickerImage(void) {
    return [UIImage imageNamed:@"sticker-popup"];
}

static NSString *Localized(NSString *text) {
    return [text length] ? DLG_LOCALIZED(text) : text;
}

/* one button of the card. the filled one carries the accent, the others are
   outlined in it, so the choice reads on every theme */
@interface ShiroDialogButton : UIButton {
    ShiroDialogButtonStyle _style;
    CAGradientLayer *_fill;
}
- (id)initWithTitle:(NSString *)title style:(ShiroDialogButtonStyle)style filled:(BOOL)filled;
- (ShiroDialogButtonStyle)buttonStyle;
@end

@implementation ShiroDialogButton

- (id)initWithTitle:(NSString *)title style:(ShiroDialogButtonStyle)style filled:(BOOL)filled {
    if ((self = [super initWithFrame:CGRectZero])) {
        _style = style;
        UIColor *tone = style == ShiroDialogButtonDestructive ? DLG_DESTRUCTIVE() : DLG_ACCENT();
        self.backgroundColor = [UIColor clearColor];
        [self setTitle:title forState:UIControlStateNormal];
        self.titleLabel.font = DLG_FONT(15.0f, YES);
        self.titleLabel.numberOfLines = 1;
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.contentEdgeInsets = UIEdgeInsetsMake(0.0f, 10.0f, 0.0f, 10.0f);
        self.layer.cornerRadius = DLG_BUTTON_RADIUS;
        if (filled) {
            [self setTitleColor:DLG_ON_FILL(tone) forState:UIControlStateNormal];
            if (DLG_GLOSSY) {
                /* the classic theme draws its filled controls as glass, lighter at the top */
                _fill = [[CAGradientLayer layer] retain];
                _fill.colors = [NSArray arrayWithObjects:
                                (id)DLG_SHADE(tone, 0.20f).CGColor,
                                (id)DLG_SHADE(tone, -0.20f).CGColor, nil];
                _fill.cornerRadius = self.layer.cornerRadius;
                [self.layer insertSublayer:_fill atIndex:0];
            } else {
                self.backgroundColor = tone;
            }
        } else {
            [self setTitleColor:tone forState:UIControlStateNormal];
            self.layer.borderWidth = 1.0f;
            self.layer.borderColor = [tone colorWithAlphaComponent:0.55f].CGColor;
        }
        [self addTarget:self action:@selector(pressDown) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [self addTarget:self action:@selector(pressUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchDragExit | UIControlEventTouchCancel];
    }
    return self;
}

- (void)dealloc {
    [_fill release];
    [super dealloc];
}

- (ShiroDialogButtonStyle)buttonStyle { return _style; }

- (void)pressDown { ShiroMotionBounce(self, YES, 0.035f); }
- (void)pressUp { ShiroMotionBounce(self, NO, 0.035f); }

- (void)layoutSubviews {
    [super layoutSubviews];
    if (_fill) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _fill.frame = self.bounds;
        [CATransaction commit];
    }
}

@end

/* one row of a list of choices */
@interface ShiroDialogRow : UIButton
@end

@implementation ShiroDialogRow
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted ? [DLG_INK() colorWithAlphaComponent:0.10f] : [UIColor clearColor];
}
@end

@class ShiroDialogViewController;

@interface ShiroDialog () {
    NSString *_title;
    NSString *_message;
    BOOL _backdropSet;
    BOOL _dismissOnBackdrop;
    NSMutableArray *_buttons;   /* dictionaries: title, style, handler */
    NSMutableArray *_items;     /* dictionaries: title, handler */
    UITextField *_textField;
    UIWindow *_window;
    UIWindow *_previousKey;
    ShiroDialogViewController *_controller;
    BOOL _shown;
}
- (void)runButtonAtIndex:(NSInteger)index;
- (void)runItemAtIndex:(NSInteger)index;
- (void)backdropTapped;
- (void)primaryTriggered;
- (NSArray *)buttonSpecs;
- (NSArray *)itemSpecs;
@end

/* the card and everything on it, laid out by hand: UIKit has no inline sizing
   for a plate that must stay inside the room the keyboard leaves */
@interface ShiroDialogView : UIView <UITextFieldDelegate> {
    ShiroDialog *_dialog;        /* assigned, the dialog owns the window that owns this */
    UIControl *_backdrop;
    UIView *_card;
    UIImageView *_face;
    UILabel *_titleLabel;
    UILabel *_messageLabel;
    UIScrollView *_scroll;
    NSMutableArray *_rows;
    NSMutableArray *_rules;
    NSMutableArray *_buttons;
    UITextField *_field;
    CGFloat _keyboardInset;
    BOOL _entered;
}
- (id)initWithDialog:(ShiroDialog *)dialog;
- (void)setKeyboardInset:(CGFloat)inset;
- (void)playEntrance;
- (void)focusField;
@end

@interface ShiroDialogViewController : UIViewController {
    ShiroDialog *_dialog;
    UIViewController *_host;
}
- (id)initWithDialog:(ShiroDialog *)dialog host:(UIViewController *)host;
@end

@implementation ShiroDialog
@synthesize title = _title;
@synthesize message = _message;
@synthesize textField = _textField;

+ (ShiroDialog *)dialogWithTitle:(NSString *)title message:(NSString *)message {
    ShiroDialog *dialog = [[[ShiroDialog alloc] init] autorelease];
    dialog.title = title;
    dialog.message = message;
    return dialog;
}

- (id)init {
    if ((self = [super init])) {
        _buttons = [[NSMutableArray alloc] init];
        _items = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_title release];
    [_message release];
    [_buttons release];
    [_items release];
    [_textField release];
    [_window release];
    [_previousKey release];
    [_controller release];
    [super dealloc];
}

- (BOOL)hasCancel {
    for (NSDictionary *b in _buttons)
        if ([[b objectForKey:@"style"] intValue] == ShiroDialogButtonCancel) return YES;
    return NO;
}

- (BOOL)dismissOnBackdrop {
    return _backdropSet ? _dismissOnBackdrop : [self hasCancel];
}

- (void)setDismissOnBackdrop:(BOOL)value {
    _backdropSet = YES;
    _dismissOnBackdrop = value;
}

- (void)addButtonWithTitle:(NSString *)title
                     style:(ShiroDialogButtonStyle)style
                   handler:(void (^)(ShiroDialog *))handler {
    NSMutableDictionary *b = [NSMutableDictionary dictionary];
    [b setObject:Localized(title) ? Localized(title) : @"" forKey:@"title"];
    [b setObject:[NSNumber numberWithInt:style] forKey:@"style"];
    if (handler) [b setObject:[[handler copy] autorelease] forKey:@"handler"];
    [_buttons addObject:b];
}

- (void)addItemWithTitle:(NSString *)title handler:(void (^)(ShiroDialog *))handler {
    NSMutableDictionary *i = [NSMutableDictionary dictionary];
    [i setObject:Localized(title) ? Localized(title) : @"" forKey:@"title"];
    if (handler) [i setObject:[[handler copy] autorelease] forKey:@"handler"];
    [_items addObject:i];
}

- (UITextField *)addTextFieldWithText:(NSString *)text
                          placeholder:(NSString *)placeholder
                             keyboard:(UIKeyboardType)keyboard {
    if (_textField) return _textField;
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 100, 40)];
    field.backgroundColor = DLG_WELL();
    field.textColor = DLG_INK();
    field.font = [UIFont systemFontOfSize:16.0f];
    field.text = text;
    field.placeholder = Localized(placeholder);
    field.keyboardType = keyboard;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.returnKeyType = UIReturnKeyDone;
    field.borderStyle = UITextBorderStyleNone;
    field.layer.cornerRadius = 8.0f;
    field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    /* a field has no inner padding of its own once its border is gone */
    UIView *pad = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)] autorelease];
    field.leftView = pad;
    field.leftViewMode = UITextFieldViewModeAlways;
    _textField = field;
    return field;
}

/* what ShiroDialogView reads, so the view never owns a second copy of the specs */
- (NSArray *)buttonSpecs { return _buttons; }
- (NSArray *)itemSpecs { return _items; }

- (void)runButtonAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)[_buttons count]) return;
    void (^handler)(ShiroDialog *) = [[_buttons objectAtIndex:index] objectForKey:@"handler"];
    [self retain];
    [self dismiss];
    if (handler) handler(self);
    [self release];
}

- (void)runItemAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)[_items count]) return;
    void (^handler)(ShiroDialog *) = [[_items objectAtIndex:index] objectForKey:@"handler"];
    [self retain];
    [self dismiss];
    if (handler) handler(self);
    [self release];
}

- (void)backdropTapped {
    if (![self dismissOnBackdrop]) return;
    for (NSUInteger i = 0; i < [_buttons count]; ++i) {
        if ([[[_buttons objectAtIndex:i] objectForKey:@"style"] intValue] == ShiroDialogButtonCancel) {
            [self runButtonAtIndex:(NSInteger)i];
            return;
        }
    }
    [self dismiss];
}

/* return on the keyboard confirms: the last normal or destructive button */
- (void)primaryTriggered {
    for (NSInteger i = (NSInteger)[_buttons count] - 1; i >= 0; --i) {
        if ([[[_buttons objectAtIndex:i] objectForKey:@"style"] intValue] != ShiroDialogButtonCancel) {
            [self runButtonAtIndex:i];
            return;
        }
    }
}

static NSMutableArray *gShownDialogs = nil;

- (void)show {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(show) withObject:nil waitUntilDone:NO];
        return;
    }
    if (_shown) return;
    _shown = YES;
    if (!gShownDialogs) gShownDialogs = [[NSMutableArray alloc] init];
    [gShownDialogs addObject:self];

    UIApplication *app = [UIApplication sharedApplication];
    _previousKey = [[app keyWindow] retain];
    UIViewController *host = _previousKey.rootViewController;
    _controller = [[ShiroDialogViewController alloc] initWithDialog:self host:host];
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    _window.windowLevel = UIWindowLevelAlert + 1.0f;
    _window.backgroundColor = [UIColor clearColor];
    _window.rootViewController = _controller;
    [_window makeKeyAndVisible];
    [(ShiroDialogView *)_controller.view playEntrance];
    [(ShiroDialogView *)_controller.view focusField];
}

- (void)dismiss {
    if (!_shown) return;
    _shown = NO;
    [self retain];
    [_textField resignFirstResponder];
    /* dismiss runs inside the action of a button on this card, so the window, its
       controller and the view stay alive until the touch has been handled */
    [[_window retain] autorelease];
    [[_controller retain] autorelease];
    [[_controller.view retain] autorelease];
    _window.hidden = YES;
    if (_previousKey && !_previousKey.hidden) [_previousKey makeKeyWindow];
    _window.rootViewController = nil;
    [gShownDialogs removeObject:self];
    [self release];
}

@end

@implementation ShiroDialogViewController

- (id)initWithDialog:(ShiroDialog *)dialog host:(UIViewController *)host {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _dialog = dialog;
        _host = host;
        /* ios 5 and 6 start a root view below the status bar, which would leave
           a strip above the dimmed card */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if ([self respondsToSelector:@selector(setWantsFullScreenLayout:)])
            self.wantsFullScreenLayout = YES;
#pragma clang diagnostic pop
    }
    return self;
}

- (void)loadView {
    self.view = [[[ShiroDialogView alloc] initWithDialog:_dialog] autorelease];
}

/* the card follows the orientations the app allows, as UIAlertView did: a
   window of its own would otherwise rotate to anything and stand sideways
   over a screen that is locked upright */
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    if (_host && [_host respondsToSelector:@selector(shouldAutorotateToInterfaceOrientation:)])
        return [_host shouldAutorotateToInterfaceOrientation:orientation];
    return YES;
}

- (BOOL)shouldAutorotate {
    if (_host && [_host respondsToSelector:@selector(shouldAutorotate)])
        return [_host shouldAutorotate];
    return YES;
}

/* the 6.1 sdk of the armv7 slice declares the mask as NSUInteger, the 9.0 sdk and later as an enum */
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
#else
- (NSUInteger)supportedInterfaceOrientations {
#endif
    if (_host && [_host respondsToSelector:@selector(supportedInterfaceOrientations)])
        return [_host supportedInterfaceOrientations];
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)prefersStatusBarHidden {
    /* ios 7 selectors, which the armv7 sdk does not declare */
    SEL hidden = @selector(prefersStatusBarHidden);
    if (_host && [_host respondsToSelector:hidden])
        return ((BOOL (*)(id, SEL))objc_msgSend)(_host, hidden);
    return NO;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    SEL style = @selector(preferredStatusBarStyle);
    if (_host && [_host respondsToSelector:style])
        return ((UIStatusBarStyle (*)(id, SEL))objc_msgSend)(_host, style);
    return UIStatusBarStyleDefault;
}

@end

@implementation ShiroDialogView

- (id)initWithDialog:(ShiroDialog *)dialog {
    if ((self = [super initWithFrame:[[UIScreen mainScreen] bounds]])) {
        _dialog = dialog;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.backgroundColor = [UIColor clearColor];

        _backdrop = [[UIControl alloc] initWithFrame:self.bounds];
        _backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _backdrop.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.6f];
        [_backdrop addTarget:dialog action:@selector(backdropTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_backdrop];

        _card = DLG_MAKE_CARD(CGRectMake(0, 0, 300, 200));
        [self addSubview:_card];

        _face = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 104, 104)];
        _face.contentMode = UIViewContentModeScaleAspectFit;
        _face.image = StickerImage();
        _face.userInteractionEnabled = NO;
        [self addSubview:_face];

        NSString *title = Localized(dialog.title);
        if ([title length]) {
            _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
            _titleLabel.backgroundColor = [UIColor clearColor];
            _titleLabel.font = DLG_FONT(19.0f, YES);
            _titleLabel.textColor = DLG_INK();
            _titleLabel.textAlignment = NSTextAlignmentCenter;
            _titleLabel.numberOfLines = 0;
            _titleLabel.text = title;
            [_card addSubview:_titleLabel];
        }

        _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _scroll.backgroundColor = [UIColor clearColor];
        _scroll.showsHorizontalScrollIndicator = NO;
        _scroll.showsVerticalScrollIndicator = NO;
        [_card addSubview:_scroll];

        NSString *message = Localized(dialog.message);
        if ([message length]) {
            _messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
            _messageLabel.backgroundColor = [UIColor clearColor];
            _messageLabel.font = DLG_FONT(15.0f, NO);
            _messageLabel.textColor = DLG_MUTED();
            _messageLabel.textAlignment = NSTextAlignmentCenter;
            _messageLabel.numberOfLines = 0;
            _messageLabel.text = message;
            [_scroll addSubview:_messageLabel];
        }

        _field = [dialog.textField retain];
        if (_field) {
            _field.delegate = self;
            [_scroll addSubview:_field];
        }

        _rows = [[NSMutableArray alloc] init];
        _rules = [[NSMutableArray alloc] init];
        NSArray *items = [dialog itemSpecs];
        for (NSUInteger i = 0; i < [items count]; ++i) {
            UIView *rule = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
            rule.backgroundColor = DLG_SEPARATOR();
            [_scroll addSubview:rule];
            [_rules addObject:rule];
            ShiroDialogRow *row = [ShiroDialogRow buttonWithType:UIButtonTypeCustom];
            [row setTitle:[[items objectAtIndex:i] objectForKey:@"title"] forState:UIControlStateNormal];
            [row setTitleColor:DLG_ACCENT() forState:UIControlStateNormal];
            row.titleLabel.font = DLG_FONT(16.0f, NO);
            row.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            row.tag = (NSInteger)i;
            [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
            [_scroll addSubview:row];
            [_rows addObject:row];
        }

        _buttons = [[NSMutableArray alloc] init];
        NSArray *specs = [dialog buttonSpecs];
        NSInteger primary = -1;
        for (NSInteger i = (NSInteger)[specs count] - 1; i >= 0; --i) {
            if ([[[specs objectAtIndex:i] objectForKey:@"style"] intValue] != ShiroDialogButtonCancel) {
                primary = i;
                break;
            }
        }
        for (NSUInteger i = 0; i < [specs count]; ++i) {
            NSDictionary *spec = [specs objectAtIndex:i];
            ShiroDialogButtonStyle style = (ShiroDialogButtonStyle)[[spec objectForKey:@"style"] intValue];
            ShiroDialogButton *button = [[[ShiroDialogButton alloc]
                initWithTitle:[spec objectForKey:@"title"]
                        style:style
                       filled:(NSInteger)i == primary] autorelease];
            button.tag = (NSInteger)i;
            [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [_card addSubview:button];
            [_buttons addObject:button];
        }

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardChanged:)
                                                     name:UIKeyboardWillShowNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardChanged:)
                                                     name:UIKeyboardWillHideNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _field.delegate = nil;
    [_backdrop release];
    [_card release];
    [_face release];
    [_titleLabel release];
    [_messageLabel release];
    [_scroll release];
    [_rows release];
    [_rules release];
    [_buttons release];
    [_field release];
    [super dealloc];
}

- (void)rowTapped:(UIButton *)row { [_dialog runItemAtIndex:row.tag]; }
- (void)buttonTapped:(UIButton *)button { [_dialog runButtonAtIndex:button.tag]; }

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    (void)field;
    [_dialog primaryTriggered];
    return NO;
}

- (void)keyboardChanged:(NSNotification *)note {
    CGFloat inset = 0.0f;
    if ([[note name] isEqualToString:UIKeyboardWillShowNotification] && self.window) {
        CGRect end = [[[note userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
        /* the frame is in screen space and the window may be turned */
        CGRect inWindow = [self.window convertRect:end fromWindow:nil];
        CGRect inSelf = [self convertRect:inWindow fromView:nil];
        inset = fmaxf(0.0f, CGRectGetMaxY(self.bounds) - inSelf.origin.y);
    }
    [self setKeyboardInset:inset];
}

- (void)setKeyboardInset:(CGFloat)inset {
    if (inset == _keyboardInset) return;
    _keyboardInset = inset;
    [self setNeedsLayout];
    [UIView animateWithDuration:0.25 animations:^{ [self layoutIfNeeded]; }];
}

- (void)focusField {
    if (!_field) return;
    [self layoutIfNeeded];
    [_field becomeFirstResponder];
}

- (CGFloat)stickerSide {
    return self.bounds.size.height < 460.0f ? 64.0f : 104.0f;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat side = [self stickerSide];
    CGFloat overlap = side * 0.75f;
    CGFloat cardW = fminf(DIALOG_CARD_MAX, bounds.size.width - 2.0f * DIALOG_MARGIN);
    CGFloat innerW = cardW - 2.0f * DIALOG_PAD;
    CGFloat topPad = side - overlap + 6.0f;

    CGFloat titleH = 0.0f;
    if (_titleLabel) {
        titleH = ceilf(DLG_TEXT_SIZE(_titleLabel.text, _titleLabel.font, innerW).height);
        _titleLabel.frame = CGRectMake(DIALOG_PAD, topPad, innerW, titleH);
    }

    /* the middle of the card scrolls, so a long message keeps the buttons in reach */
    CGFloat y = 4.0f;
    if (_messageLabel) {
        CGFloat h = ceilf(DLG_TEXT_SIZE(_messageLabel.text, _messageLabel.font, innerW).height);
        _messageLabel.frame = CGRectMake(0, y + 8.0f, innerW, h);
        y += 8.0f + h + 4.0f;
    }
    if (_field) {
        _field.frame = CGRectMake(0, y + 6.0f, innerW, 40.0f);
        y += 6.0f + 40.0f + 4.0f;
    }
    for (NSUInteger i = 0; i < [_rows count]; ++i) {
        UIView *rule = [_rules objectAtIndex:i];
        rule.frame = CGRectMake(0, y, innerW, 0.5f);
        UIView *row = [_rows objectAtIndex:i];
        row.frame = CGRectMake(0, y + 0.5f, innerW, DIALOG_ITEM_H);
        y += 0.5f + DIALOG_ITEM_H;
    }
    CGFloat scrollContent = y;

    /* one or two buttons share a row, more stack, so no title is squeezed */
    NSUInteger count = [_buttons count];
    BOOL stacked = count > 2;
    CGFloat buttonsH = 0.0f;
    if (count) buttonsH = stacked ? count * DIALOG_BUTTON_H + (count - 1) * 8.0f : DIALOG_BUTTON_H;
    CGFloat buttonsGap = count ? 14.0f : 0.0f;

    CGFloat available = bounds.size.height - _keyboardInset - 16.0f;
    CGFloat fixed = overlap + topPad + titleH + buttonsGap + buttonsH + 14.0f;
    CGFloat cap = fminf(bounds.size.height * 0.55f, available - fixed);
    if (cap < 60.0f) cap = 60.0f;
    CGFloat scrollH = fminf(scrollContent, cap);
    _scroll.frame = CGRectMake(DIALOG_PAD, topPad + titleH, innerW, scrollH);
    _scroll.contentSize = CGSizeMake(innerW, scrollContent);
    _scroll.scrollEnabled = scrollContent > scrollH + 0.5f;

    CGFloat by = topPad + titleH + scrollH + buttonsGap;
    if (count) {
        if (stacked) {
            /* the action first, the way out last */
            NSMutableArray *order = [NSMutableArray array];
            for (ShiroDialogButton *b in [_buttons reverseObjectEnumerator]) [order addObject:b];
            for (NSUInteger i = 0; i < count; ++i) {
                UIView *b = [order objectAtIndex:i];
                b.frame = CGRectMake(DIALOG_PAD, by + i * (DIALOG_BUTTON_H + 8.0f), innerW, DIALOG_BUTTON_H);
            }
        } else {
            CGFloat bw = (innerW - (count - 1) * 8.0f) / (CGFloat)count;
            NSMutableArray *order = [NSMutableArray array];
            /* a cancel button on the left, the action on the right */
            for (ShiroDialogButton *b in _buttons)
                if ([b buttonStyle] == ShiroDialogButtonCancel) [order addObject:b];
            for (ShiroDialogButton *b in _buttons)
                if ([b buttonStyle] != ShiroDialogButtonCancel) [order addObject:b];
            for (NSUInteger i = 0; i < count; ++i) {
                UIView *b = [order objectAtIndex:i];
                b.frame = CGRectMake(DIALOG_PAD + i * (bw + 8.0f), by, bw, DIALOG_BUTTON_H);
            }
        }
    }
    CGFloat cardH = by + buttonsH + 14.0f;

    CGFloat total = overlap + cardH;
    CGFloat top = floorf((bounds.size.height - _keyboardInset - total) * 0.5f);
    if (top < 8.0f) top = 8.0f;
    CGFloat left = floorf((bounds.size.width - cardW) * 0.5f);
    _card.frame = CGRectMake(left, top + overlap, cardW, cardH);
    _face.frame = CGRectMake(floorf((bounds.size.width - side) * 0.5f), top, side, side);
}

/* the backdrop fades in, the card rises on the popup curve of shiro_motion and the sticker pops in */
- (void)playEntrance {
    if (_entered) return;
    _entered = YES;
    [self layoutIfNeeded];
    ShiroMotionEnter(_backdrop, CGAffineTransformIdentity, 0.0f, SHIRO_MOTION_ENTER, 0.0);
    ShiroMotionEnter(_card, CGAffineTransformMakeTranslation(0.0f, 18.0f), 0.0f,
                   SHIRO_MOTION_POPUP_ENTER, 0.0);
    /* the sticker pops in a moment after the card on the loose spring */
    ShiroMotionEnter(_face, CGAffineTransformMakeScale(0.4f, 0.4f), 0.0f, SHIRO_MOTION_WOBBLE, 0.06);
}

@end

void ShiroDialogAlert(NSString *title, NSString *message) {
    ShiroDialog *dialog = [ShiroDialog dialogWithTitle:title message:message];
    [dialog addButtonWithTitle:@"OK" style:ShiroDialogButtonNormal handler:nil];
    [dialog show];
}

void ShiroDialogConfirm(NSString *title, NSString *message, NSString *action,
                      BOOL destructive, void (^confirm)(void)) {
    ShiroDialog *dialog = [ShiroDialog dialogWithTitle:title message:message];
    [dialog addButtonWithTitle:@"Cancel" style:ShiroDialogButtonCancel handler:nil];
    [dialog addButtonWithTitle:action
                         style:destructive ? ShiroDialogButtonDestructive : ShiroDialogButtonNormal
                       handler:^(ShiroDialog *d) {
        (void)d;
        if (confirm) confirm();
    }];
    [dialog show];
}

void ShiroDialogMenu(NSString *title, NSString *message, NSArray *labels,
                   void (^pick)(NSInteger index)) {
    ShiroDialog *dialog = [ShiroDialog dialogWithTitle:title message:message];
    for (NSUInteger i = 0; i < [labels count]; ++i) {
        NSInteger index = (NSInteger)i;
        [dialog addItemWithTitle:[labels objectAtIndex:i] handler:^(ShiroDialog *d) {
            (void)d;
            if (pick) pick(index);
        }];
    }
    [dialog addButtonWithTitle:@"Cancel" style:ShiroDialogButtonCancel handler:^(ShiroDialog *d) {
        (void)d;
        if (pick) pick(-1);
    }];
    [dialog show];
}

void ShiroDialogPrompt(NSString *title, NSString *message, NSString *text,
                     NSString *placeholder, UIKeyboardType keyboard, NSString *action,
                     void (^done)(NSString *text)) {
    ShiroDialog *dialog = [ShiroDialog dialogWithTitle:title message:message];
    [dialog addTextFieldWithText:text placeholder:placeholder keyboard:keyboard];
    [dialog addButtonWithTitle:@"Cancel" style:ShiroDialogButtonCancel handler:^(ShiroDialog *d) {
        (void)d;
        if (done) done(nil);
    }];
    [dialog addButtonWithTitle:action style:ShiroDialogButtonNormal handler:^(ShiroDialog *d) {
        NSString *typed = d.textField.text ? d.textField.text : @"";
        if (done) done(typed);
    }];
    [dialog show];
}
