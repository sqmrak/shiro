#import "theme_def.h"
#import "ui_theme.h"

/* material expressive: tonal surfaces tinted toward the rose primary, one bold
   primary, large shapes and pill controls. the light primary is deep enough
   for white text at about 6:1; the dark one is the pale tone of the same hue,
   because a saturated rose vibrates on a near black surface */
static void FillLight(void) {
    ShiroThemeSetSlot(&kBG,         ShiroThemeC(1.000, 0.973, 0.976)); /* surface */
    ShiroThemeSetSlot(&kBGBot,      ShiroThemeC(1.000, 0.973, 0.976));
    ShiroThemeSetSlot(&kFelt,       ShiroThemeC(0.992, 0.929, 0.945));
    ShiroThemeSetSlot(&kConnOn,     ShiroThemeC(0.757, 0.000, 0.376)); /* primary */
    ShiroThemeSetSlot(&kConnOnLo,   ShiroThemeC(0.580, 0.000, 0.280));
    ShiroThemeSetSlot(&kIdleGrey,   ShiroThemeC(0.800, 0.740, 0.760));
    ShiroThemeSetSlot(&kIdleGreyLo, ShiroThemeC(0.650, 0.580, 0.610));
    ShiroThemeSetSlot(&kInk,        ShiroThemeC(0.133, 0.098, 0.106));
    ShiroThemeSetSlot(&kInkMuted,   ShiroThemeC(0.350, 0.290, 0.310));
    ShiroThemeSetSlot(&kAccentBlue, ShiroThemeC(0.757, 0.000, 0.376));
    ShiroThemeSetSlot(&kAccentBlueLo, ShiroThemeC(0.580, 0.000, 0.280));
    ShiroThemeSetSlot(&kChromeHi,   ShiroThemeC(0.757, 0.000, 0.376)); /* app bar */
    ShiroThemeSetSlot(&kChromeLo,   ShiroThemeC(0.580, 0.000, 0.280));
    ShiroThemeSetSlot(&kCellHi,     ShiroThemeC(0.996, 0.918, 0.937)); /* surface container */
    ShiroThemeSetSlot(&kCellLo,     ShiroThemeC(0.996, 0.918, 0.937));
    ShiroThemeSetSlot(&kWell,       ShiroThemeC(0.970, 0.870, 0.900)); /* inset fields */
}

static void FillDark(void) {
    ShiroThemeSetSlot(&kBG,         ShiroThemeC(0.102, 0.067, 0.075)); /* surface */
    ShiroThemeSetSlot(&kBGBot,      ShiroThemeC(0.102, 0.067, 0.075));
    ShiroThemeSetSlot(&kFelt,       ShiroThemeC(0.153, 0.114, 0.125));
    ShiroThemeSetSlot(&kConnOn,     ShiroThemeC(1.000, 0.694, 0.780)); /* primary */
    ShiroThemeSetSlot(&kConnOnLo,   ShiroThemeC(0.930, 0.520, 0.660));
    ShiroThemeSetSlot(&kIdleGrey,   ShiroThemeC(0.300, 0.250, 0.270));
    ShiroThemeSetSlot(&kIdleGreyLo, ShiroThemeC(0.220, 0.180, 0.200));
    ShiroThemeSetSlot(&kInk,        ShiroThemeC(0.940, 0.880, 0.890));
    ShiroThemeSetSlot(&kInkMuted,   ShiroThemeC(0.780, 0.700, 0.730));
    ShiroThemeSetSlot(&kAccentBlue, ShiroThemeC(1.000, 0.694, 0.780));
    ShiroThemeSetSlot(&kAccentBlueLo, ShiroThemeC(0.930, 0.520, 0.660));
    ShiroThemeSetSlot(&kChromeHi,   ShiroThemeC(0.153, 0.114, 0.125)); /* app bar, a step above the page */
    ShiroThemeSetSlot(&kChromeLo,   ShiroThemeC(0.125, 0.090, 0.100));
    ShiroThemeSetSlot(&kCellHi,     ShiroThemeC(0.200, 0.150, 0.165)); /* surface container */
    ShiroThemeSetSlot(&kCellLo,     ShiroThemeC(0.200, 0.150, 0.165));
    ShiroThemeSetSlot(&kWell,       ShiroThemeC(0.075, 0.050, 0.056));
}

/* the id stays shiro-ios6 because 1.0.x installs saved it as their theme, and a
   new id would drop them back to the default on update */
const ShiroThemeDef kShiroThemeExpressive = {
    "shiro-ios6",
    "Shiro",
    "tonal color, large shapes",
    ShiroThemeCapFlat | ShiroThemeCapMaterial,
    24.0f,
    FillLight,
    FillDark,
    "ios6 white dark light expressive material",
    SHIRO_THEME_GROUP_IOS
};
