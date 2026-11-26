#import "theme_def.h"
extern const ShiroThemeDef kShiroThemeExpressive;
extern const ShiroThemeDef kShiroThemeClassic;
/* the first entry is the default, and the modern theme keeps the id that 1.0.x installs saved */
const ShiroThemeDef *const *ShiroThemeAllDefs(size_t *count) {
    static const ShiroThemeDef *const definitions[] = {&kShiroThemeExpressive, &kShiroThemeClassic};
    if (count) *count = sizeof(definitions) / sizeof(definitions[0]);
    return definitions;
}
