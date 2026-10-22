#import "theme_def.h"
extern const ShiroThemeDef kShiroThemeExpressive;
const ShiroThemeDef *const *ShiroThemeAllDefs(size_t *count) {
    static const ShiroThemeDef *const definitions[] = {&kShiroThemeExpressive};
    if (count) *count = sizeof(definitions) / sizeof(definitions[0]);
    return definitions;
}
