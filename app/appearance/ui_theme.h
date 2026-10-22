#ifndef SHIRO_UI_THEME_H
#define SHIRO_UI_THEME_H

#import "ios_compat.h"
#import <QuartzCore/QuartzCore.h>

/* filled by initpalette / applycurrentpalette */
extern UIColor *kBG;
extern UIColor *kBGBot;
extern UIColor *kFelt;
extern UIColor *kConnOn;
extern UIColor *kConnOnLo;
extern UIColor *kIdleGrey;
extern UIColor *kIdleGreyLo;
extern UIColor *kInk;
extern UIColor *kInkMuted;
extern UIColor *kAccentBlue;
extern UIColor *kAccentBlueLo;
extern UIColor *kChromeHi;
extern UIColor *kChromeLo;
extern UIColor *kCellHi;
extern UIColor *kCellLo;
extern UIColor *kWell;

/* boot defaults before prefs load */
void InitPalette(void);

/* family id stored in nsuserdefaults */
NSString *ShiroThemeDefaultId(void);
NSString *ShiroThemeCurrentId(void);
NSArray  *ShiroThemeAllIds(void);
/* picker folders (ios, custom,...); stable order */
NSArray  *ShiroThemeGroupIds(void);
NSString *ShiroThemeGroupTitle(NSString *groupId);
NSArray  *ShiroThemeIdsInGroup(NSString *groupId);
NSString *ShiroThemeGroupOfId(NSString *themeId);
NSString *ShiroThemeDisplayName(NSString *themeId);
/* one-line subtitle under style name */
NSString *ShiroThemeBlurb(NSString *themeId);
/* settings row: style + light/dark */
NSString *ShiroThemeStatusLine(void);
/* apply family; posts shirothemedidchangenotification */
void ShiroThemeApplyId(NSString *themeId);
/* re-resolve the current id and repaint: a custom theme's def is rebuilt when
   its colors are saved, so the cached pointer has to be refreshed */
void ShiroThemeReapplyCurrent(void);

#define SHIRO_IOS6_THEME_ID @"shiro-ios6"
/* freeze the current screen and dissolve it, so a theme switch reads as one
   transition instead of every view repainting on its own */
void ShiroThemeCrossfadeWindows(void);
/* re-resolve the active theme after the custom theme table is rebuilt */
void ShiroThemeRebindCurrent(void);
void ShiroThemeSetLight(BOOL light);
BOOL ShiroThemeIsLight(void);
/* 0 if theme cannot go dark */
BOOL ShiroThemeAllowsDark(void);
/* 1 for ios7/ios16 (no emboss chrome) */
BOOL ShiroThemeIsFlat(void);
/* 1 for shiro-ios16 (also set on ios26 for chrome reuse) */
BOOL ShiroThemeIsIos16(void);
/* 1 for shiro-ios26 liquid glass approx */
BOOL ShiroThemeIsIos26(void);
/* 1 when solid frost fills are used (no uitoolbar blur) */
BOOL ShiroThemeUsesFrost(void);
BOOL ShiroThemeIsBoykisser(void);
/* 1 for shiro-miside (heart on, purple) */
BOOL ShiroThemeIsMiside(void);
/* 1 for shiro-frutigeraero / shiro-aero (sky gloss, light only) */
BOOL ShiroThemeIsFrutigeraero(void);
/* 1 for the material expressive theme: flat surfaces, elevation shadows, touch ripples and a
   circular progress ring on the power button (see material.h) */
BOOL ShiroThemeIsMaterial(void);
/* card corner; larger on ios16 */
CGFloat ShiroThemeCardRadius(void);
/* frost subview on host */
void ShiroInstallFrost(UIView *host);
/* solid frost fill; scroll-safe on armv7 */
void ShiroInstallFrostLite(UIView *host);
void ShiroRemoveFrost(UIView *host);
/* where anything drawn over a frosted host must live: a UIVisualEffectView
   throws NSInternalInconsistencyException if a subview is added to it
   directly instead of to its contentView. safe to call on a plain (non
   effect) view too, since it just returns the view itself */
UIView *ShiroEffectContentView(UIView *effectView);
/* wallpaper gradient (theme only; ios16 is 3-stop diagonal) */
void ShiroApplyBackgroundGradient(CAGradientLayer *g);
/* state ignored - wallpaper stays pure theme; glow is around connect */
void ShiroApplyBackgroundGradientForState(CAGradientLayer *g, NSString *state, BOOL animated);
/* light title / body fonts for modern themes */
UIFont *ShiroFontTitle(CGFloat size);
UIFont *ShiroFontBody(CGFloat size, BOOL semibold);
/* geometric bold wordmark face, closest available to rubik bold */
UIFont *ShiroFontDisplay(CGFloat size);
/* rendered width of one line, so a control can size itself to its own text */
CGFloat ShiroTextWidth(NSString *text, UIFont *font);
/* wrapped size of text held to one width, measured through a label so no screen
   depends on the deprecated string drawing category */
CGSize ShiroTextSize(NSString *text, UIFont *font, CGFloat width);
/* blend a palette colour toward white (delta > 0) or black (delta < 0), so a
   two stop fill has relief whatever the theme supplies */
UIColor *ShiroShadeColor(UIColor *base, CGFloat delta);
/* rgba of a uikit colour; NO for a pattern colour, which leaves opaque black */
BOOL ShiroColorComponents(UIColor *color, CGFloat *r, CGFloat *g, CGFloat *b, CGFloat *a);

extern NSString * const ShiroThemeDidChangeNotification;
extern NSString * const ShiroThemeIdKey;
extern NSString * const ShiroThemeLightKey;

/* body text for current theme */
void ShiroStyleInkLabel(UILabel *label);
void ShiroStyleMutedLabel(UILabel *label);
void ShiroStyleAccentLabel(UILabel *label);
/* light text on fixed dark plates */
void ShiroStyleInkOnDark(UILabel *label);
void ShiroStyleMutedOnDark(UILabel *label);
void ShiroStyleAccentOnDark(UILabel *label);
/* accent title color for + and similar */
void ShiroStylePaperGlyph(UIButton *button);
/* white title on filled controls */
void ShiroStyleChromeTitle(UIButton *button);
/* light title on dark section buttons */
void ShiroStyleGlyphOnDark(UIButton *button);

/* section header plate styling */
void ShiroFillSectionGradient(CAGradientLayer *g);
void ShiroStyleSectionPlate(UIView *plate);
void ShiroStyleSectionGlyph(UIButton *button);
/* terminal / config editor colors */
void ShiroStyleTerminalPlate(UIView *plate);
void ShiroStyleTerminalText(UITextView *tv);
/* translucent field / segment chrome for liquid glass */
void ShiroStyleGlassField(UITextField *field);
void ShiroStyleGlassSegmented(UISegmentedControl *seg);
/* quiet selection shared by lists on old and new UIKit */
void ShiroStyleSelectableCell(UITableViewCell *cell);
/* ios 6 rotation: view.bounds can stay portrait-shaped while device is landscape (and the reverse) */
CGRect ShiroViewBounds(UIView *view);
/* solid theme fill, or ios26 wallpaper under translucent chrome */
void ShiroApplyScreenChrome(UIView *root);
/* a list over the screen gradient instead of a flat fill */
void ShiroClearTableBackground(UITableView *table);

void SetStatusDefault(UILabel *label, NSString *text);
void SetStatusRefresh(UILabel *label, NSString *text);
UIImage *TintedIconNamed(NSString *name, CGFloat side, UIColor *tint);
/* glyphs drawn on a shared 24pt grid, cached per size and tint. drawing them
   keeps one weight across every screen and removes the png bundling step that
   silently dropped icon-refresh from the app */
UIImage *GaugeIcon(CGFloat side, UIColor *tint);
UIImage *ShiroGearIcon(CGFloat side, UIColor *tint);
UIImage *ShiroPlusIcon(CGFloat side, UIColor *tint);
UIImage *ShiroIconRefresh(CGFloat side, UIColor *tint);
UIImage *ShiroIconPower(CGFloat side, UIColor *tint);
UIImage *ShiroIconShield(CGFloat side, UIColor *tint);
UIImage *ShiroIconGlobe(CGFloat side, UIColor *tint);
UIImage *ShiroIconChevron(CGFloat side, UIColor *tint);
UIImage *ShiroIconCopy(CGFloat side, UIColor *tint);
UIImage *ShiroIconPencil(CGFloat side, UIColor *tint);
UIImage *ShiroIconTrash(CGFloat side, UIColor *tint);
UIImage *ShiroIconClose(CGFloat side, UIColor *tint);
void StyleNavBarClassic(UINavigationController *nav);
/* the status card sets the column every list plate lines up with: the rows, the
   section headers and the empty panel all sit inside the table, and the table
   already carries the card's own x and width. anything inset further than this
   reads as a second, narrower column beside the card */
#define SHIRO_LIST_PLATE_INSET 0.0f

/* the rounded plate a grouped row sits on. settings and the developer screens
   draw the same one, and both need the engraved rule between rows, so the view
   lives here instead of being copied into each */
@interface ShiroGroupCellBackground : UIView {
    UIRectCorner _roundedCorners;
    BOOL         _showsSeparator;
    CALayer     *_grooveDark;
    CALayer     *_grooveLight;
}
@property (nonatomic, assign) UIRectCorner roundedCorners;
@property (nonatomic, assign) BOOL showsSeparator;
@end

/* apply the plate to one cell: rounds the ends of the group and rules every row
   but the last. rows comes from the data source, because asking the table for it
   while it is building a cell re-enters a table that has not finished loading */
void ShiroStyleGroupCell(UITableViewCell *cell, NSIndexPath *ip, NSInteger rows);

/* give a filled control its light from above: the body darkens downward, a
   sheen sits over the top half, a hairline rim separates it from the wallpaper
   and a short shadow lifts it off. the caller owns the fill layer and passes it
   in. flat themes are left alone, because the absence of this is their point */
void ShiroApplyRelief(UIButton *button, CAGradientLayer *fill,
                      UIColor *top, UIColor *bottom, CGFloat radius);

/* capsule button; skips rebuild if size/colors match */
void StyleGlossyCapsule(UIButton *button, UIColor *top, UIColor *bottom);
/* a filled pill has to label itself against its own fill: a theme is free to
   hand over a pale idle colour that white text disappears into */
UIColor *ShiroPillLabelColor(UIColor *fill);
/* resize capsule layers without color rebuild */
void StyleGlossyCapsuleLayout(UIButton *button);
CGFloat GetTopOffset(void);
UIEdgeInsets ShiroSafeAreaInsets(UIView *view);
/* the theme gradient lives in its own autoresizing backdrop view rather than as
   a bare sublayer: a layer keeps the size the host had when the screen was
   built, which is what left a black band beside every modal screen opened in
   one orientation and rotated to the other */
enum { kShiroBackdropTag = 9112 };
CAGradientLayer *AddVGradient(UIView *view, UIColor *top, UIColor *bottom);
void ShiroSetLayerFrame(CALayer *layer, CGRect frame);

/* motion. uikit gained spring animation in ios 7, so the helpers fall back to
   a timed overshoot rather than dropping the movement on older systems */
void ShiroAnimate(NSTimeInterval duration, void (^animations)(void),
                  void (^completion)(BOOL finished));
void ShiroAnimateSpring(NSTimeInterval duration, NSTimeInterval delay,
                        void (^animations)(void),
                        void (^completion)(BOOL finished));
/* scale a view briefly, used for press feedback on cells and pills */
void ShiroPressPop(UIView *view, BOOL pressed);
/* catransaction: disable implicit animations */
void ShiroBeginSilentLayers(void);
void ShiroEndSilentLayers(void);
/* drop icon cache after theme switch */
void ShiroThemeFlushImageCaches(void);

#endif
