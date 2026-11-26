#import "theme_def.h"
#import "ui_theme.h"

/* the classic theme: glass bars in the app colour with a lighter top and a darker foot, white
   grouped rows on a pale ground and glossy controls, the way exteria draws its classic style.
   the bar colour is the raspberry of the app, lifted a step in the light variant, where the deep
   one looks heavy next to white rows, and held deep in the dark one so the gloss still reads */
static void FillLight(void) {
    ShiroThemeSetSlot(&kBG,         ShiroThemeC(0.89, 0.90, 0.93));
    ShiroThemeSetSlot(&kBGBot,      ShiroThemeC(0.80, 0.82, 0.87));
    ShiroThemeSetSlot(&kFelt,       ShiroThemeC(0.94, 0.86, 0.90));
    ShiroThemeSetSlot(&kConnOn,     ShiroThemeC(0.88, 0.12, 0.36));
    ShiroThemeSetSlot(&kConnOnLo,   ShiroThemeC(0.65, 0.06, 0.25));
    ShiroThemeSetSlot(&kIdleGrey,   ShiroThemeC(0.93, 0.63, 0.73));
    ShiroThemeSetSlot(&kIdleGreyLo, ShiroThemeC(0.78, 0.40, 0.53));
    ShiroThemeSetSlot(&kInk,        ShiroThemeC(0.12, 0.12, 0.14));
    ShiroThemeSetSlot(&kInkMuted,   ShiroThemeC(0.43, 0.43, 0.47));
    ShiroThemeSetSlot(&kAccentBlue, ShiroThemeC(0.78, 0.03, 0.38));
    ShiroThemeSetSlot(&kAccentBlueLo, ShiroThemeC(0.59, 0.02, 0.28));
    ShiroThemeSetSlot(&kChromeHi,   ShiroThemeC(0.80, 0.30, 0.52)); /* bar colour */
    ShiroThemeSetSlot(&kChromeLo,   ShiroThemeC(0.62, 0.14, 0.38));
    ShiroThemeSetSlot(&kCellHi,     ShiroThemeC(0.99, 0.99, 1.00));
    ShiroThemeSetSlot(&kCellLo,     ShiroThemeC(0.93, 0.93, 0.95));
    ShiroThemeSetSlot(&kWell,       ShiroThemeC(0.87, 0.87, 0.90));
}

static void FillDark(void) {
    ShiroThemeSetSlot(&kBG,         ShiroThemeC(0.24, 0.13, 0.19));
    ShiroThemeSetSlot(&kBGBot,      ShiroThemeC(0.14, 0.07, 0.11));
    ShiroThemeSetSlot(&kFelt,       ShiroThemeC(0.29, 0.17, 0.23));
    ShiroThemeSetSlot(&kConnOn,     ShiroThemeC(0.96, 0.24, 0.46));
    ShiroThemeSetSlot(&kConnOnLo,   ShiroThemeC(0.72, 0.08, 0.30));
    ShiroThemeSetSlot(&kIdleGrey,   ShiroThemeC(0.42, 0.42, 0.45));
    ShiroThemeSetSlot(&kIdleGreyLo, ShiroThemeC(0.22, 0.22, 0.24));
    ShiroThemeSetSlot(&kInk,        ShiroThemeC(0.96, 0.96, 0.98));
    ShiroThemeSetSlot(&kInkMuted,   ShiroThemeC(0.73, 0.73, 0.77));
    ShiroThemeSetSlot(&kAccentBlue, ShiroThemeC(0.96, 0.16, 0.50));
    ShiroThemeSetSlot(&kAccentBlueLo, ShiroThemeC(0.73, 0.05, 0.36));
    ShiroThemeSetSlot(&kChromeHi,   ShiroThemeC(0.52, 0.10, 0.30)); /* bar colour */
    ShiroThemeSetSlot(&kChromeLo,   ShiroThemeC(0.36, 0.06, 0.21));
    ShiroThemeSetSlot(&kCellHi,     ShiroThemeC(0.33, 0.33, 0.36));
    ShiroThemeSetSlot(&kCellLo,     ShiroThemeC(0.22, 0.22, 0.25));
    ShiroThemeSetSlot(&kWell,       ShiroThemeC(0.13, 0.13, 0.15));
}

const ShiroThemeDef kShiroThemeClassic = {
    "shiro-classic",
    "Classic",
    "glass bars and glossy controls",
    ShiroThemeCapClassic,
    10.0f,
    FillLight,
    FillDark,
    "classic skeuomorphic glass",
    SHIRO_THEME_GROUP_IOS
};
