#ifndef SHIRO_THEME_DEF_H
#define SHIRO_THEME_DEF_H

#import <UIKit/UIKit.h>

/* capability bits; registry caches these after apply */
enum {
    ShiroThemeCapFlat      = 1u << 0, /* ios7/ios16 chrome */
    ShiroThemeCapIos16     = 1u << 1,
    ShiroThemeCapBoykisser = 1u << 2,
    ShiroThemeCapMiside    = 1u << 3,
    ShiroThemeCapAero      = 1u << 4,
    ShiroThemeCapLightOnly = 1u << 5,
    ShiroThemeCapDarkOnly  = 1u << 6,
    ShiroThemeCapIos26     = 1u << 7, /* glass; pairs with capios16 paths */
    ShiroThemeCapMaterial  = 1u << 8  /* flat surfaces that rise on shadows, ripples */
};

/* picker folders; themesvc groups by this id */
#define SHIRO_THEME_GROUP_IOS    "ios"
#define SHIRO_THEME_GROUP_CUSTOM "custom"

typedef void (*ShiroThemeFillFn)(void);

/* one theme family */
typedef struct ShiroThemeDef {
    const char *tid; /* stored id, e.g. shiro-ios6 */
    const char *name; /* picker title */
    const char *blurb; /* picker subtitle */
    unsigned caps;
    CGFloat cardRadius;
    ShiroThemeFillFn fillLight;
    ShiroThemeFillFn fillDark; /* may equal filllight */
/* lowercase tokens matched on legacy prefs; space separated, or null */
    const char *aliases;
/* shiro_theme_group_ios / custom / future */
    const char *group;
} ShiroThemeDef;

/* palette writers used only inside theme fills */
void ShiroThemeSetSlot(UIColor **slot, UIColor *color);
UIColor *ShiroThemeC(CGFloat r, CGFloat g, CGFloat b);
UIColor *ShiroThemeCA(CGFloat r, CGFloat g, CGFloat b, CGFloat a);

/* lookup; returns null if unknown */
const ShiroThemeDef *ShiroThemeFind(NSString *tid);
const ShiroThemeDef *ShiroThemeFindMigrated(NSString *raw, BOOL *outLight);
const ShiroThemeDef *const *ShiroThemeAllDefs(size_t *outCount);
const ShiroThemeDef *ShiroThemeCurrentDef(void);

#endif
