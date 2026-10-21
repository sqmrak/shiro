#import "theme_def.h"
#import "ui_theme.h"

typedef struct {
    CGFloat connOn[3], connOnLo[3], idle[3], idleLo[3], accent[3], accentLo[3];
} ShiroAccent;

static const ShiroAccent kLightAccent = {
    {0.88f,0.12f,0.36f}, {0.65f,0.06f,0.25f},
    {0.93f,0.63f,0.73f}, {0.78f,0.40f,0.53f},
    {0.78f,0.03f,0.38f}, {0.59f,0.02f,0.28f}
};
static const ShiroAccent kDarkAccent = {
    {0.96f,0.24f,0.46f}, {0.72f,0.08f,0.30f}, {0}, {0},
    {0.96f,0.16f,0.50f}, {0.73f,0.05f,0.36f}
};

static UIColor *Pick(const CGFloat *c) {
    return ShiroThemeC(c[0], c[1], c[2]);
}

static void FillLight(void) {
    ShiroThemeSetSlot(&kBG,         ShiroThemeC(0.97, 0.90, 0.93));
    ShiroThemeSetSlot(&kBGBot,      ShiroThemeC(0.90, 0.79, 0.84));
    ShiroThemeSetSlot(&kFelt,       ShiroThemeC(0.94, 0.86, 0.90));
    const ShiroAccent *a = &kLightAccent;
    ShiroThemeSetSlot(&kConnOn,     Pick(a->connOn));
    ShiroThemeSetSlot(&kConnOnLo,   Pick(a->connOnLo));
    ShiroThemeSetSlot(&kIdleGrey,   Pick(a->idle)); /* tinted, not the flat grey disc */
    ShiroThemeSetSlot(&kIdleGreyLo, Pick(a->idleLo));
    ShiroThemeSetSlot(&kInk,        ShiroThemeC(0.12, 0.12, 0.14));
    ShiroThemeSetSlot(&kInkMuted,   ShiroThemeC(0.43, 0.43, 0.47));
    ShiroThemeSetSlot(&kAccentBlue, Pick(a->accent));
    ShiroThemeSetSlot(&kAccentBlueLo, Pick(a->accentLo));
    ShiroThemeSetSlot(&kChromeHi,   ShiroThemeC(0.94, 0.94, 0.96));
    ShiroThemeSetSlot(&kChromeLo,   ShiroThemeC(0.75, 0.75, 0.79));
    ShiroThemeSetSlot(&kCellHi,     ShiroThemeC(0.99, 0.99, 1.00));
    ShiroThemeSetSlot(&kCellLo,     ShiroThemeC(0.93, 0.93, 0.95));
    ShiroThemeSetSlot(&kWell,       ShiroThemeC(0.87, 0.87, 0.90));
}

static void FillDark(void) {
    ShiroThemeSetSlot(&kBG,         ShiroThemeC(0.24, 0.13, 0.19));
    ShiroThemeSetSlot(&kBGBot,      ShiroThemeC(0.14, 0.07, 0.11));
    ShiroThemeSetSlot(&kFelt,       ShiroThemeC(0.29, 0.17, 0.23));
    const ShiroAccent *a = &kDarkAccent;
    ShiroThemeSetSlot(&kConnOn,     Pick(a->connOn));
    ShiroThemeSetSlot(&kConnOnLo,   Pick(a->connOnLo));
    ShiroThemeSetSlot(&kIdleGrey,   ShiroThemeC(0.42, 0.42, 0.45));
    ShiroThemeSetSlot(&kIdleGreyLo, ShiroThemeC(0.22, 0.22, 0.24));
    ShiroThemeSetSlot(&kInk,        ShiroThemeC(0.96, 0.96, 0.98));
    ShiroThemeSetSlot(&kInkMuted,   ShiroThemeC(0.73, 0.73, 0.77));
    ShiroThemeSetSlot(&kAccentBlue, Pick(a->accent));
    ShiroThemeSetSlot(&kAccentBlueLo, Pick(a->accentLo));
    ShiroThemeSetSlot(&kChromeHi,   ShiroThemeC(0.39, 0.39, 0.42));
    ShiroThemeSetSlot(&kChromeLo,   ShiroThemeC(0.22, 0.22, 0.25));
    ShiroThemeSetSlot(&kCellHi,     ShiroThemeC(0.33, 0.33, 0.36));
    ShiroThemeSetSlot(&kCellLo,     ShiroThemeC(0.22, 0.22, 0.25));
    ShiroThemeSetSlot(&kWell,       ShiroThemeC(0.13, 0.13, 0.15));
}

const ShiroThemeDef kShiroThemeIos6 = {
    "shiro-ios6",
    "Shiro-iOS6",
    "the legacy theme for the legacy community",
    0,
    10.0f,
    FillLight,
    FillDark,
    "ios6 white dark light",
    SHIRO_THEME_GROUP_IOS

};
