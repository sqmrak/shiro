#import "theme_def.h"
extern const ShiroThemeDef kShiroThemeIos6;
const ShiroThemeDef *const *ShiroThemeAllDefs(size_t *count) {
    static const ShiroThemeDef *const definitions[] = {&kShiroThemeIos6};
    if (count) *count = sizeof(definitions) / sizeof(definitions[0]);
    return definitions;
}
