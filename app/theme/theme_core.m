#import "theme_def.h"
#import "ui_theme.h"
#import "crash_report.h"

#include <string.h>
#include <objc/message.h>

UIColor *kBG;
UIColor *kBGBot;
UIColor *kFelt;
UIColor *kConnOn;
UIColor *kConnOnLo;
UIColor *kIdleGrey;
UIColor *kIdleGreyLo;
UIColor *kInk;
UIColor *kInkMuted;
UIColor *kAccentBlue;
UIColor *kAccentBlueLo;
UIColor *kChromeHi;
UIColor *kChromeLo;
UIColor *kCellHi;
UIColor *kCellLo;
UIColor *kWell;

NSString * const ShiroThemeDidChangeNotification = @"ShiroThemeDidChangeNotification";
NSString * const ShiroThemeIdKey = @"shiro.theme.id";
NSString * const ShiroThemeLightKey = @"shiro.theme.light";

static NSString *gThemeId;
static BOOL gLight;
static const ShiroThemeDef *gCur;

/* cached caps so scroll paths skip table lookup */
static unsigned gCaps;
static CGFloat gCardRadius;

UIColor *ShiroThemeC(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r green:g blue:b alpha:1.0];
}

UIColor *ShiroThemeCA(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

void ShiroThemeSetSlot(UIColor **slot, UIColor *color) {
    if (*slot == color) return;
    [*slot release];
    *slot = [color retain];
}

NSString *ShiroThemeDefaultId(void) {
    return @"shiro-ios6";
}

static BOOL TokenInAliases(NSString *s, const char *aliases) {
    if (!aliases || ![s length]) return NO;
    NSString *a = [[NSString stringWithUTF8String:aliases] lowercaseString];
    NSArray *parts = [a componentsSeparatedByCharactersInSet:
                      [NSCharacterSet whitespaceCharacterSet]];
    for (NSString *p in parts) {
        if (![p length]) continue;
        if ([s rangeOfString:p].location != NSNotFound)
            return YES;
    }
    return NO;
}

const ShiroThemeDef *ShiroThemeFind(NSString *tid) {
    if (![tid length]) return NULL;
    size_t n = 0;
    const ShiroThemeDef *const *tab = ShiroThemeAllDefs(&n);
    for (size_t i = 0; i < n; ++i) {
        if ([tid isEqualToString:[NSString stringWithUTF8String:tab[i]->tid]])
            return tab[i];
    }
    return NULL;
}

/* map old combined ids and loose names to a family */
const ShiroThemeDef *ShiroThemeFindMigrated(NSString *raw, BOOL *outLight) {
    size_t n = 0;
    const ShiroThemeDef *const *tab = ShiroThemeAllDefs(&n);
    NSString *s = [raw lowercaseString];
    if (!s) {
        if (outLight) *outLight = NO;
        return ShiroThemeFind(ShiroThemeDefaultId());
    }

    const ShiroThemeDef *exact = ShiroThemeFind(raw);
    if (exact) {
        if (outLight) {
            if (exact->caps & ShiroThemeCapLightOnly)
                *outLight = YES;
            else if (exact->caps & ShiroThemeCapDarkOnly)
                *outLight = NO;
            else if ([s rangeOfString:@"dark"].location != NSNotFound)
                *outLight = NO;
            else if ([s rangeOfString:@"white"].location != NSNotFound ||
                     [s rangeOfString:@"light"].location != NSNotFound)
                *outLight = YES;
            else
                *outLight = NO;
        }
        return exact;
    }

    for (size_t i = 0; i < n; ++i) {
        if (!TokenInAliases(s, tab[i]->aliases))
            continue;
        if (outLight) {
            if (tab[i]->caps & ShiroThemeCapLightOnly)
                *outLight = YES;
            else if (tab[i]->caps & ShiroThemeCapDarkOnly)
                *outLight = NO;
            else
                *outLight = ([s rangeOfString:@"dark"].location == NSNotFound);
        }
        return tab[i];
    }

    if (outLight) *outLight = NO;
    return ShiroThemeFind(ShiroThemeDefaultId());
}

const ShiroThemeDef *ShiroThemeCurrentDef(void) {
    return gCur;
}

NSString *ShiroThemeCurrentId(void) {
    if (gThemeId) return gThemeId;
    return ShiroThemeDefaultId();
}

NSArray *ShiroThemeAllIds(void) {
    size_t n = 0;
    const ShiroThemeDef *const *tab = ShiroThemeAllDefs(&n);
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:n];
    for (size_t i = 0; i < n; ++i)
        [a addObject:[NSString stringWithUTF8String:tab[i]->tid]];
    return a;
}

/* fixed folder order; themes without group fall into custom */
static const char *const kGroupOrder[] = {
    SHIRO_THEME_GROUP_IOS,
    SHIRO_THEME_GROUP_CUSTOM
};

NSArray *ShiroThemeGroupIds(void) {
    size_t n = 0;
    const ShiroThemeDef *const *tab = ShiroThemeAllDefs(&n);
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:4];
    for (size_t g = 0; g < sizeof kGroupOrder / sizeof kGroupOrder[0]; ++g) {
        NSString *gid = [NSString stringWithUTF8String:kGroupOrder[g]];
        for (size_t i = 0; i < n; ++i) {
            const char *gg = tab[i]->group ? tab[i]->group : SHIRO_THEME_GROUP_CUSTOM;
            if (strcmp(gg, kGroupOrder[g]) == 0) {
                [out addObject:gid];
                break;
            }
        }
    }
/* any unknown group ids appear after known folders */
    for (size_t i = 0; i < n; ++i) {
        const char *gg = tab[i]->group ? tab[i]->group : SHIRO_THEME_GROUP_CUSTOM;
        NSString *gid = [NSString stringWithUTF8String:gg];
        if (![out containsObject:gid])
            [out addObject:gid];
    }
    return out;
}

NSString *ShiroThemeGroupTitle(NSString *groupId) {
    if ([groupId isEqualToString:@SHIRO_THEME_GROUP_IOS])
        return @"iOS";
    if ([groupId isEqualToString:@SHIRO_THEME_GROUP_CUSTOM])
        return @"Custom";
    if (![groupId length]) return @"Custom";
    return [groupId capitalizedString];
}

NSArray *ShiroThemeIdsInGroup(NSString *groupId) {
    size_t n = 0;
    const ShiroThemeDef *const *tab = ShiroThemeAllDefs(&n);
    NSString *want = groupId ? groupId : @SHIRO_THEME_GROUP_CUSTOM;
    NSMutableArray *a = [NSMutableArray array];
    for (size_t i = 0; i < n; ++i) {
        const char *gg = tab[i]->group ? tab[i]->group : SHIRO_THEME_GROUP_CUSTOM;
        if ([want isEqualToString:[NSString stringWithUTF8String:gg]])
            [a addObject:[NSString stringWithUTF8String:tab[i]->tid]];
    }
    return a;
}

NSString *ShiroThemeGroupOfId(NSString *themeId) {
    const ShiroThemeDef *d = ShiroThemeFind(themeId);
    if (!d || !d->group) return @SHIRO_THEME_GROUP_CUSTOM;
    return [NSString stringWithUTF8String:d->group];
}

NSString *ShiroThemeDisplayName(NSString *themeId) {
    const ShiroThemeDef *d = ShiroThemeFind(themeId);
    if (!d) {
        BOOL light = NO;
        d = ShiroThemeFindMigrated(themeId, &light);
    }
    if (!d) return @"";
    return [NSString stringWithUTF8String:d->name];
}

NSString *ShiroThemeBlurb(NSString *themeId) {
    const ShiroThemeDef *d = ShiroThemeFind(themeId);
    if (!d) {
        BOOL light = NO;
        d = ShiroThemeFindMigrated(themeId, &light);
    }
    if (!d || !d->blurb)
        return @"the legacy theme for the legacy community";
    return [NSString stringWithUTF8String:d->blurb];
}

NSString *ShiroThemeStatusLine(void) {
    NSString *name = ShiroThemeDisplayName(ShiroThemeCurrentId());
    if (gCaps & ShiroThemeCapDarkOnly)
        return [NSString stringWithFormat:@"%@    Dark", name];
    if (gCaps & ShiroThemeCapLightOnly)
        return [NSString stringWithFormat:@"%@    Light", name];
    if (!ShiroThemeAllowsDark())
        return [NSString stringWithFormat:@"%@    Light", name];
    return [NSString stringWithFormat:@"%@    %@", name, gLight ? @"Light" : @"Dark"];
}

static void RefreshCaps(void) {
    gCaps = gCur ? gCur->caps : 0;
    gCardRadius = gCur ? gCur->cardRadius : 10.0f;
}

static void ApplyCurrentPalette(void) {
    if (!gCur) {
        gCur = ShiroThemeFind(ShiroThemeDefaultId());
        RefreshCaps();
    }
    if (gCaps & ShiroThemeCapLightOnly)
        gLight = YES;
    else if (gCaps & ShiroThemeCapDarkOnly)
        gLight = NO;

    if (gLight) {
        if (gCur->fillLight) gCur->fillLight();
    } else {
        if (gCur->fillDark) gCur->fillDark();
        else if (gCur->fillLight) gCur->fillLight();
    }
    RefreshCaps();
    ShiroThemeFlushImageCaches();
}

static void PersistAndNotify(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:gThemeId forKey:ShiroThemeIdKey];
    [d setBool:gLight forKey:ShiroThemeLightKey];
    [d synchronize];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:ShiroThemeDidChangeNotification object:gThemeId];
}

void ShiroThemeApplyId(NSString *themeId) {
    const ShiroThemeDef *def = ShiroThemeFind(themeId);
    if (!def) def = ShiroThemeFind(ShiroThemeDefaultId());
    NSString *tid = [NSString stringWithUTF8String:def->tid];
    if (gThemeId && [gThemeId isEqualToString:tid]) return;
    /* only a real switch dissolves; live palette edits repaint in place */
    ShiroThemeCrossfadeWindows();
    [gThemeId release];
    gThemeId = [tid copy];
    gCur = def;
    RefreshCaps();
    if (gCaps & ShiroThemeCapLightOnly)
        gLight = YES;
    else if (gCaps & ShiroThemeCapDarkOnly)
        gLight = NO;
    ApplyCurrentPalette();
    PersistAndNotify();
}

/* the custom theme structs are freed and rebuilt whenever the user saves,
   imports or deletes one, so a cached def pointer has to be looked up again;
   without this the next palette apply reads freed memory */
void ShiroThemeRebindCurrent(void) {
    if (!gThemeId) return;
    const ShiroThemeDef *def = ShiroThemeFind(gThemeId);
    if (def) {
        if (def == gCur) return;
        gCur = def;
        RefreshCaps();
        return;
    }
/* the active theme was deleted, so the default family takes over */
    def = ShiroThemeFind(ShiroThemeDefaultId());
    if (!def) return;
    [gThemeId release];
    gThemeId = [[NSString stringWithUTF8String:def->tid] copy];
    gCur = def;
    RefreshCaps();
    ApplyCurrentPalette();
    PersistAndNotify();
}

void ShiroThemeReapplyCurrent(void) {
    const ShiroThemeDef *def = ShiroThemeFind(ShiroThemeCurrentId());
    if (!def) def = ShiroThemeFind(ShiroThemeDefaultId());
    if (!def) return;
    NSString *tid = [NSString stringWithUTF8String:def->tid];
    if (!gThemeId || ![gThemeId isEqualToString:tid]) {
        [gThemeId release];
        gThemeId = [tid copy];
    }
    gCur = def;
    RefreshCaps();
    ApplyCurrentPalette();
    PersistAndNotify();
}

void ShiroThemeSetLight(BOOL light) {
    if (!ShiroThemeAllowsDark()) {
        BOOL fixed = (gCaps & ShiroThemeCapDarkOnly) ? NO : YES;
        if (gLight != fixed) {
            gLight = fixed;
            ApplyCurrentPalette();
            PersistAndNotify();
        }
        return;
    }
    BOOL want = light ? YES : NO;
    if (gLight == want) return;
    gLight = want;
    ApplyCurrentPalette();
    PersistAndNotify();
}

void InitPalette(void) {
    /* two launches in a row died before the first frame, so the theme is the
       first thing to take out of the picture: it is what decides whether the
       ui asks uikit for live glass and custom decor. the choice on disk is
       deliberately left alone, so the user gets their theme back as soon as
       one launch succeeds */
    if (ShiroCrashSafeMode()) {
        const ShiroThemeDef *plain = ShiroThemeFind(ShiroThemeDefaultId());
        if (plain) {
            [gThemeId release];
            gThemeId = [[NSString stringWithUTF8String:plain->tid] copy];
            gCur = plain;
            RefreshCaps();
            gLight = NO;
            if (gCaps & ShiroThemeCapLightOnly) gLight = YES;
            if (gCaps & ShiroThemeCapDarkOnly) gLight = NO;
            ApplyCurrentPalette();
            return;
        }
    }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *saved = [d stringForKey:ShiroThemeIdKey];
    const ShiroThemeDef *def = NULL;
    BOOL light = NO;

    if (ShiroThemeFind(saved)) {
        def = ShiroThemeFind(saved);
        if ([d objectForKey:ShiroThemeLightKey])
            light = [d boolForKey:ShiroThemeLightKey];
    } else if ([saved length]) {
        def = ShiroThemeFindMigrated(saved, &light);
    } else {
        def = ShiroThemeFind(ShiroThemeDefaultId());
        if ([d objectForKey:ShiroThemeLightKey])
            light = [d boolForKey:ShiroThemeLightKey];
        else {
            id screen = [UIScreen mainScreen];
            if ([screen respondsToSelector:@selector(traitCollection)]) {
                id traits = ((id (*)(id, SEL))objc_msgSend)(screen, @selector(traitCollection));
                if ([traits respondsToSelector:@selector(userInterfaceStyle)])
                    light = ((NSInteger (*)(id, SEL))objc_msgSend)(traits, @selector(userInterfaceStyle)) == 1;
            }
        }
    }
    if (!def) def = ShiroThemeFind(ShiroThemeDefaultId());

    [gThemeId release];
    gThemeId = [[NSString stringWithUTF8String:def->tid] copy];
    gCur = def;
    RefreshCaps();
    gLight = light;
    if (gCaps & ShiroThemeCapLightOnly) gLight = YES;
    if (gCaps & ShiroThemeCapDarkOnly) gLight = NO;
    ApplyCurrentPalette();
    [d setObject:gThemeId forKey:ShiroThemeIdKey];
    [d setBool:gLight forKey:ShiroThemeLightKey];
    [d synchronize];
}

void ShiroBeginSilentLayers(void) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
}

void ShiroEndSilentLayers(void) {
    [CATransaction commit];
}

void ShiroSetLayerFrame(CALayer *layer, CGRect frame) {
    if (!layer) return;
    if (CGRectEqualToRect(layer.frame, frame)) return;
    ShiroBeginSilentLayers();
    layer.frame = frame;
    ShiroEndSilentLayers();
}

BOOL ShiroThemeIsIos16(void) {
    return (gCaps & ShiroThemeCapIos16) != 0;
}

BOOL ShiroThemeIsIos26(void) {
    return (gCaps & ShiroThemeCapIos26) != 0;
}

BOOL ShiroThemeIsFlat(void) {
    return (gCaps & ShiroThemeCapFlat) != 0;
}

BOOL ShiroThemeUsesFrost(void) {
/* solid frostlite only; live blur is heavy on armv7 */
    return (gCaps & ShiroThemeCapFlat) != 0;
}

BOOL ShiroThemeIsBoykisser(void) {
    return (gCaps & ShiroThemeCapBoykisser) != 0;
}

BOOL ShiroThemeIsMiside(void) {
    return (gCaps & ShiroThemeCapMiside) != 0;
}

BOOL ShiroThemeIsFrutigeraero(void) {
    return (gCaps & ShiroThemeCapAero) != 0;
}

BOOL ShiroThemeIsMaterial(void) {
    return (gCaps & ShiroThemeCapMaterial) != 0;
}

BOOL ShiroThemeAllowsDark(void) {
    return (gCaps & (ShiroThemeCapLightOnly | ShiroThemeCapDarkOnly)) == 0;
}

BOOL ShiroThemeIsLight(void) {
    return gLight;
}

CGFloat ShiroThemeCardRadius(void) {
    return gCardRadius > 0.5f ? gCardRadius : 10.0f;
}
