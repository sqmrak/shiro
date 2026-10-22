#import "screen_controller.h"
#ifndef SHIRO_APP_COMMON_H
#define SHIRO_APP_COMMON_H
#import "ios_compat.h"
#import "control_client.h"
#import "dev_table_vc.h"
#define SHIRO_SOCK @"/var/run/shiro/control.sock"
#define SHIRO_VERSION @"v1.1.0-stable"
#define SHIRO_LANGUAGE_KEY @"ShiroLanguage"
#define SHIRO_DEV_MENU_KEY @"ShiroDeveloperMenu"
#define SHIRO_FPS_OVERLAY_KEY @"ShiroDeveloperFPSOverlay"
#define SHIRO_VPN_BADGE_OFF_PATH "/var/mobile/Library/Preferences/com.shiro.status.off"
typedef NS_ENUM(NSInteger, ShiroLanguage) {
    ShiroLanguageEnglish = 0,
    ShiroLanguageRussian = 1,
    ShiroLanguageChinese = 2
};
extern NSString *const ShiroLanguageDidChangeNotification;
BOOL ShiroLanguageIsRussian(void);
BOOL ShiroLanguageIsChinese(void);
void ShiroSetLanguage(ShiroLanguage language);
NSString *ShiroLanguageName(void);
NSString *ShiroHoursText(int hours);
NSString *ShiroLocalizedText(NSString *text);
NSString *ShiroHumanReadableError(NSString *text);
NSString *ShiroRedactSecrets(NSString *text);
void ShiroLocalizationInstall(void);
void ShiroRelocalizeAllWindows(void);
BOOL ShiroDevMenuEnabled(void);
void ShiroSetDevMenuEnabled(BOOL enabled);
int ShiroDevMenuTapsLeft(void);
void ShiroDevMenuResetTaps(void);
BOOL ShiroFPSOverlayEnabled(void);
void ShiroFPSOverlaySetEnabled(BOOL enabled);
NSString *ShiroFormatBytes(unsigned long long value);
NSString *ShiroFormatRate(double value);
NSString *ShiroAboutTLSMode(void);
@interface ShiroMainController : ShiroScreenController
@end
@interface ShiroSettingsController : ShiroTableController
@end
@interface ShiroAboutController : ShiroScreenController
@end
@interface ShiroLogsController : ShiroScreenController <UISearchBarDelegate, UIActionSheetDelegate>
@end
@interface ShiroStatisticsController : ShiroScreenController
@end
#endif
