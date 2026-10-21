#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/stat.h>
#include <dispatch/dispatch.h>

static const char kShiroStatusStatePath[] =
    "/var/mobile/Library/Preferences/com.shiro.status.state";
/* springboard is the only process that can see which status bar this firmware
   has, and the app cannot read its log. this file is what the logs screen
   shows, so a mode or a failure never has to be guessed from the outside
   again. it is an append-only ring, not one line: a single overwritten line
   cannot show the sequence that led to a wifi glyph report after the fact */
static const char kShiroStatusLogPath[] =
    "/var/mobile/Library/Preferences/com.shiro.status.log";
#define SHIRO_STATUS_LOG_CAP (32 * 1024)
/* the app writes this when the user turns the badge off, because the status bar
   on some firmwares drops the wifi glyph to make room for it */
static const char kShiroStatusOffPath[] =
    "/var/mobile/Library/Preferences/com.shiro.status.off";
static const CFStringRef kShiroStatusNotify =
    CFSTR("com.shiro.status.changed");

static BOOL gShiroReady = NO;
static BOOL gShiroQueued = NO;
static BOOL gShiroDidApply = NO;
static BOOL gShiroLastState = NO;
static unsigned gShiroRetries = 0;
static BOOL gShiroHookFailureLogged = NO;

static void ShiroWriteStatus(NSString *line) {
    if (![line length]) return;
    NSString *stamped = [NSString stringWithFormat:@"%.0f thread=%p %@",
                          [[NSDate date] timeIntervalSince1970],
                          (void *)pthread_self(), line];
    const char *text = [stamped UTF8String];
    if (!text) return;

    struct stat st;
    /* a bounded ring: past the cap the log starts over instead of growing
       forever on a device nobody restarts for months */
    if (stat(kShiroStatusLogPath, &st) == 0 && st.st_size > SHIRO_STATUS_LOG_CAP) {
        int trunc = open(kShiroStatusLogPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (trunc >= 0) close(trunc);
    }

    int fd = open(kShiroStatusLogPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    (void)write(fd, text, strlen(text));
    (void)write(fd, "\n", 1);
    close(fd);
    NSLog(@"shiro status: %@", line);
}

static NSString *ShiroOSVersion(void) {
    NSDictionary *system = [NSDictionary dictionaryWithContentsOfFile:
        @"/System/Library/CoreServices/SystemVersion.plist"];
    NSString *version = [system objectForKey:@"ProductVersion"];
    return version ? version : @"unknown";
}

static BOOL ShiroReadVPNState(void) {
    char buf[8];
    int fd = open(kShiroStatusStatePath, O_RDONLY);
    if (fd < 0) return NO;
    ssize_t n = read(fd, buf, sizeof buf);
    close(fd);
    return n > 0 && buf[0] == '1';
}

static id ShiroSharedObject(NSString *className, SEL first, SEL second) {
    Class cls = NSClassFromString(className);
    if (!cls) return nil;

    if ([cls respondsToSelector:first]) {
        IMP imp = [cls methodForSelector:first];
        id (*call)(id, SEL) = (id (*)(id, SEL))imp;
        return call((id)cls, first);
    }
    if ([cls respondsToSelector:second]) {
        IMP imp = [cls methodForSelector:second];
        id (*call)(id, SEL) = (id (*)(id, SEL))imp;
        return call((id)cls, second);
    }
    return nil;
}

static BOOL ShiroCallVoid(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return NO;
    IMP imp = [obj methodForSelector:sel];
    void (*call)(id, SEL) = (void (*)(id, SEL))imp;
    call(obj, sel);
    return YES;
}

static BOOL gShiroVPNForced = NO;
/* answer yes only while the status bar is recomputing its vpn item */
static BOOL (*gShiroOrigUsingVPN)(id, SEL) = NULL;
static void (*gShiroOrigUpdateVPNItem)(id, SEL) = NULL;

static pthread_key_t gShiroUpdateDepthKey;
static pthread_once_t gShiroUpdateDepthOnce = PTHREAD_ONCE_INIT;

static void ShiroUpdateDepthKeyInit(void) {
    pthread_key_create(&gShiroUpdateDepthKey, free);
}

/* one counter per thread, not a process-wide flag: statuskit does not promise
   the vpn item is recomputed on the main thread, and a global would let a
   forced answer leak into a getter call a different thread makes for an
   unrelated item while this thread is still inside its own update */
static long *ShiroUpdateDepthSlot(void) {
    pthread_once(&gShiroUpdateDepthOnce, ShiroUpdateDepthKeyInit);
    long *slot = pthread_getspecific(gShiroUpdateDepthKey);
    if (!slot) {
        slot = calloc(1, sizeof(long));
        if (slot) pthread_setspecific(gShiroUpdateDepthKey, slot);
    }
    return slot;
}

static NSString * const kShiroAggregators[] = {
    @"SBStatusBarStateAggregator", @"STStatusBarStateAggregator"
};

/* the tunnel is not a system vpn, so somebody has to answer for it. on ios 13
   and later the status bar derives the wifi glyph from the same telephony
   manager, and answering yes to every caller told it the link was a vpn rather
   than wifi: the glyph went away for as long as the tunnel was up. the forced
   answer is now scoped to the calling thread's own run of the method that
   paints the vpn item */
static BOOL ShiroUsingVPNConnection(id self, SEL _cmd) {
    BOOL original = gShiroOrigUsingVPN ? gShiroOrigUsingVPN(self, _cmd) : NO;
    if (!gShiroVPNForced) return original;
    long *depth = ShiroUpdateDepthSlot();
    if (!depth || *depth <= 0) return original;
    return YES;
}

/* springboard recomputes the item on its own whenever the network changes, and
   it walks through here every time, so the icon survives a rebuild without the
   answer leaking to the rest of the status bar. the depth counter (rather than
   a bool) keeps nested calls on the same thread scoped correctly too */
static void ShiroUpdateVPNItem(id self, SEL _cmd) {
    long *depth = ShiroUpdateDepthSlot();
    if (depth) (*depth)++;
    if (gShiroOrigUpdateVPNItem) gShiroOrigUpdateVPNItem(self, _cmd);
    if (depth) (*depth)--;
}

/* ios 6 and 7 keep the same item on the data manager instead of an aggregator */
static NSString * const kShiroItemOwners[] = {
    @"SBStatusBarStateAggregator", @"STStatusBarStateAggregator",
    @"SBStatusBarDataManager"
};

static SEL gShiroItemSel = NULL;

/* the item method is not named the same on every firmware and no ios 10
   springboard is at hand to read it from, so the class is asked for a void
   method of no arguments with VPN in its name. the first run also logs every
   such name, which is what a missing badge report needs */
static Method ShiroFindItemMethod(Class cls, NSString *owner) {
    static const char *names[] = { "_updateVPNItem", "updateVPNItem", NULL };
    for (size_t n = 0; names[n]; ++n) {
        Method method = class_getInstanceMethod(cls, sel_registerName(names[n]));
        if (!method) continue;
        const char *types = method_getTypeEncoding(method);
        if (types && types[0] != 'v') continue;
        return method;
    }
    unsigned count = 0;
    Method *list = class_copyMethodList(cls, &count);
    Method found = NULL;
    NSMutableString *seen = [NSMutableString string];
    for (unsigned i = 0; list && i < count; ++i) {
        const char *name = sel_getName(method_getName(list[i]));
        if (!strcasestr(name, "vpn")) continue;
        [seen appendFormat:@" %s", name];
        if (found || method_getNumberOfArguments(list[i]) != 2) continue;
        char ret[4] = "";
        method_getReturnType(list[i], ret, sizeof ret);
        if (ret[0] == 'v' && (strcasestr(name, "update") || strcasestr(name, "refresh")))
            found = list[i];
    }
    free(list);
    if ([seen length])
        ShiroWriteStatus([NSString stringWithFormat:@"%@ vpn methods:%@", owner, seen]);
    return found;
}

static BOOL ShiroInstallItemHook(void) {
    if (gShiroOrigUpdateVPNItem) return YES;
    for (size_t i = 0; i < sizeof kShiroItemOwners / sizeof kShiroItemOwners[0]; ++i) {
        Class cls = NSClassFromString(kShiroItemOwners[i]);
        if (!cls) continue;
        Method method = ShiroFindItemMethod(cls, kShiroItemOwners[i]);
        if (!method) continue;
        gShiroItemSel = method_getName(method);
        gShiroOrigUpdateVPNItem = (void (*)(id, SEL))
            method_setImplementation(method, (IMP)ShiroUpdateVPNItem);
        ShiroWriteStatus([NSString stringWithFormat:
            @"badge scoped to -[%@ %s]; wifi glyph untouched",
            kShiroItemOwners[i], sel_getName(gShiroItemSel)]);
        return YES;
    }
    return NO;
}

static BOOL ShiroInstallVPNHook(void) {
    static const char *names[] = {
        "isUsingVPNConnection", "usingVPNConnection", "isVPNActive", NULL
    };
    /* the item hook decides whether the forced answer can be contained, so it
       goes in before the getter can be asked anything. without it the answer
       would reach every consumer of the getter, and on ios 13 and later that
       includes the data network item the wifi glyph is drawn from. a decorative
       badge is not worth replacing system network state, so shiro goes without
       the badge instead */
    if (!ShiroInstallItemHook()) {
        if (!gShiroHookFailureLogged) {
            gShiroHookFailureLogged = YES;
            ShiroWriteStatus(@"no vpn item update on this firmware; badge stays "
                             @"pending while springboard initializes");
        }
        return NO;
    }
    if (gShiroOrigUsingVPN) return YES;
    Class cls = NSClassFromString(@"SBTelephonyManager");
    if (cls) {
        for (size_t i = 0; names[i]; ++i) {
            SEL sel = sel_registerName(names[i]);
            Method method = class_getInstanceMethod(cls, sel);
            if (!method) continue;
            const char *types = method_getTypeEncoding(method);
/* both BOOL encodings return one byte in the same register; anything else
   would be a different method wearing the same name */
            if (types && types[0] != 'c' && types[0] != 'B') continue;
            gShiroOrigUsingVPN = (BOOL (*)(id, SEL))
                method_setImplementation(method, (IMP)ShiroUsingVPNConnection);
            return YES;
        }
    }
/* the item hook is in place but springboard has not published the getter yet */
    if (!gShiroHookFailureLogged) {
        gShiroHookFailureLogged = YES;
        ShiroWriteStatus(@"SBTelephonyManager has no vpn getter; badge stays "
                         @"pending while springboard initializes");
    }
    return NO;
}

/* springboard draws the wifi glyph only while configd's primary interface is
   the wifi interface: SBWiFiManager -_primaryInterfaceChanged: sets the flag
   SBTelephonyManager -dataConnectionType reads (ios 6.1 springboard). a shiro
   tunnel is primary while it carries the system dns, so the glyph and the vpn
   badge beside it vanished for as long as it ran. the tunnel still leaves by
   wifi, and shirod writes which interface it rides into the state file */
static void (*gShiroOrigPrimaryChanged)(id, SEL, BOOL) = NULL;
static BOOL gShiroWiFiHookTried = NO;

static BOOL ShiroTunnelRidesWiFi(void) {
    char buf[32];
    int fd = open(kShiroStatusStatePath, O_RDONLY);
    if (fd < 0) return NO;
    ssize_t n = read(fd, buf, sizeof buf - 1);
    close(fd);
    if (n < 4) return NO;
    buf[n] = '\0';
    /* ios names its wifi interface en0; cellular is pdp_ip */
    return buf[0] == '1' && buf[1] == ' ' && strncmp(buf + 2, "en", 2) == 0;
}

static NSString *ShiroNetworkFacts(void);

static void ShiroPrimaryInterfaceChanged(id self, SEL _cmd, BOOL primary) {
    if (!primary && ShiroTunnelRidesWiFi()) {
        primary = YES;
        ShiroWriteStatus(@"configd made the tunnel primary; wifi kept, the tunnel rides it");
        gShiroOrigPrimaryChanged(self, _cmd, primary);
        ShiroWriteStatus(ShiroNetworkFacts());
        return;
    }
    gShiroOrigPrimaryChanged(self, _cmd, primary);
}

static BOOL ShiroCallBool(id obj, SEL sel, BOOL *out) {
    if (!obj || ![obj respondsToSelector:sel]) return NO;
    BOOL (*call)(id, SEL) = (BOOL (*)(id, SEL))[obj methodForSelector:sel];
    *out = call(obj, sel);
    return YES;
}

/* what the status bar will draw: 8 is wifi on the ios 5.1.1 and 6.1
   springboards, -1 when this firmware has no such getter */
static int ShiroDataConnectionType(void);

/* the three facts the wifi glyph is drawn from, for the log */
static NSString *ShiroNetworkFacts(void) {
    id wifi = ShiroSharedObject(@"SBWiFiManager", @selector(sharedInstance),
                                @selector(sharedWiFiManager));
    id telephony = ShiroSharedObject(@"SBTelephonyManager",
                                     @selector(sharedTelephonyManager),
                                     @selector(sharedInstance));
    BOOL primary = NO, have_primary = ShiroCallBool(wifi, sel_registerName("isPrimaryInterface"), &primary);
    int using_wifi = -1;
    Ivar ivar = telephony ? class_getInstanceVariable([telephony class], "_usingWifi") : NULL;
    if (ivar) using_wifi = (*((unsigned char *)telephony + ivar_getOffset(ivar))) & 1;
    return [NSString stringWithFormat:@"data=%d wifi_primary=%d using_wifi=%d",
            ShiroDataConnectionType(), have_primary ? (int)primary : -1, using_wifi];
}

static int ShiroDataConnectionType(void) {
    id telephony = ShiroSharedObject(@"SBTelephonyManager",
                                     @selector(sharedTelephonyManager),
                                     @selector(sharedInstance));
    SEL sel = sel_registerName("dataConnectionType");
    if (!telephony || ![telephony respondsToSelector:sel]) return -1;
    int (*call)(id, SEL) = (int (*)(id, SEL))[telephony methodForSelector:sel];
    return call(telephony, sel);
}

static void ShiroInstallWiFiHook(void) {
    if (gShiroOrigPrimaryChanged || gShiroWiFiHookTried) return;
    Class cls = NSClassFromString(@"SBWiFiManager");
    if (!cls) return; /* springboard may publish it later */
    gShiroWiFiHookTried = YES;
    SEL sel = sel_registerName("_primaryInterfaceChanged:");
    Method method = class_getInstanceMethod(cls, sel);
    char ret[4] = "", arg[4] = "";
    if (method) {
        method_getReturnType(method, ret, sizeof ret);
        if (method_getNumberOfArguments(method) == 3)
            method_getArgumentType(method, 2, arg, sizeof arg);
    }
    /* a void method taking one BOOL, whichever of the two encodings */
    if (!method || ret[0] != 'v' || (arg[0] != 'c' && arg[0] != 'B')) {
        ShiroWriteStatus(@"no -[SBWiFiManager _primaryInterfaceChanged:] on this "
                         @"firmware; the wifi glyph follows configd alone");
        return;
    }
    gShiroOrigPrimaryChanged = (void (*)(id, SEL, BOOL))
        method_setImplementation(method, (IMP)ShiroPrimaryInterfaceChanged);
    ShiroWriteStatus(@"wifi glyph kept while a tunnel rides wifi");
}

/* configd already told springboard the tunnel is primary by the time shirod
   writes the state file, so the flag is set again here rather than waiting for
   the next network change */
static void ShiroRefreshWiFi(void) {
    ShiroInstallWiFiHook();
    if (!gShiroOrigPrimaryChanged || !ShiroTunnelRidesWiFi()) return;
    id wifi = ShiroSharedObject(@"SBWiFiManager", @selector(sharedInstance),
                                @selector(sharedWiFiManager));
    if (!wifi) return;
    ShiroPrimaryInterfaceChanged(wifi, sel_registerName("_primaryInterfaceChanged:"), YES);
}

static BOOL ShiroApplyStatus(BOOL enabled) {
    /* springboard can publish its status classes after the injected library is
       loaded, so an early missing selector must remain retryable */
    if (!ShiroInstallVPNHook()) return NO;
    gShiroVPNForced = enabled;

/* the aggregator was renamed when statuskit took over the status bar, so both
   names are tried and whichever one the system has answers. only the vpn item
   is refreshed: rebuilding the data network or service items dropped the wifi
   glyph until the next system update */
    BOOL refreshed = NO;
    NSString *via = @"none";
    for (size_t i = 0; i < sizeof kShiroAggregators / sizeof kShiroAggregators[0]; ++i) {
        id aggregator = ShiroSharedObject(kShiroAggregators[i],
                                          @selector(sharedInstance),
                                          @selector(sharedAggregator));
        if (!aggregator) continue;
        if (ShiroCallVoid(aggregator, gShiroItemSel)) {
            refreshed = YES;
            via = kShiroAggregators[i];
        }
    }

/* ios 6 and 7 have no aggregator; the data manager owns the same item there */
    if (!refreshed) {
        id data = ShiroSharedObject(@"SBStatusBarDataManager",
                                    @selector(sharedDataManager),
                                    @selector(sharedInstance));
        if (ShiroCallVoid(data, gShiroItemSel)) {
            refreshed = YES;
            via = @"SBStatusBarDataManager";
        }
    }

/* old status bars have no item refresh and need the telephony republish. modern
   statuskit uses the same republish to rebuild the wifi item, so never call it
   when an aggregator exists */
    BOOL result = refreshed;
    BOOL modernStatusKit = NSClassFromString(@"SBStatusBarStateAggregator") != nil ||
        NSClassFromString(@"STStatusBarStateAggregator") != nil;
    if (!refreshed && !modernStatusKit) {
        id telephony = ShiroSharedObject(@"SBTelephonyManager",
                                         @selector(sharedTelephonyManager),
                                         @selector(sharedInstance));
        result = ShiroCallVoid(telephony, @selector(updateSpringBoard));
        if (result) via = @"SBTelephonyManager.updateSpringBoard";
    }

/* one line per apply, not just the first hook install: the only way a future
   wifi glyph report turns into evidence instead of another guess */
    ShiroWriteStatus([NSString stringWithFormat:
        @"apply enabled=%d via=%@ ios=%@ %@", enabled, via, ShiroOSVersion(),
        ShiroNetworkFacts()]);
    return result;
}

@interface ShiroStatusBridge : NSObject
+ (void)markReady;
+ (void)applyLater;
+ (void)applyNow;
@end

@implementation ShiroStatusBridge

+ (void)markReady {
    if (gShiroReady) return;
    gShiroReady = YES;
    [self applyLater];
}

+ (void)applyLater {
    if (gShiroQueued) return;
    gShiroQueued = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(applyNow)
                                               object:nil];
    [self performSelector:@selector(applyNow) withObject:nil afterDelay:0.2];
}

+ (void)applyNow {
    gShiroQueued = NO;
    if (!gShiroReady) return;

    BOOL enabled = ShiroReadVPNState() && access(kShiroStatusOffPath, F_OK) != 0;
    if (gShiroDidApply && gShiroLastState == enabled) {
        ShiroRefreshWiFi();
        return;
    }
    BOOL applied = ShiroApplyStatus(enabled);
    /* ios 6 can recalculate the wifi item while publishing the vpn item, so
       restore the physical link after that publication */
    ShiroRefreshWiFi();
    if (applied) {
        gShiroDidApply = YES;
        gShiroLastState = enabled;
        gShiroRetries = 0;
        return;
    }
    if (gShiroRetries++ < 30) {
        [self performSelector:@selector(applyLater) withObject:nil afterDelay:1.0];
    }
}

@end

static void ShiroStatusNotify(CFNotificationCenterRef center,
                               void *observer,
                               CFStringRef name,
                               const void *object,
                               CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        [ShiroStatusBridge applyLater];
    });
}

__attribute__((constructor))
static void ShiroStatusInit(void) {
    @autoreleasepool {
        NSString *bundle = [[NSBundle mainBundle] bundleIdentifier];
        if (![bundle isEqualToString:@"com.apple.springboard"]) return;
        ShiroWriteStatus([NSString stringWithFormat:@"loaded in springboard ios=%@",
                          ShiroOSVersion()]);

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        ShiroStatusNotify,
                                        kShiroStatusNotify,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        [[NSNotificationCenter defaultCenter] addObserver:[ShiroStatusBridge class]
                                                 selector:@selector(markReady)
                                                     name:UIApplicationDidFinishLaunchingNotification
                                                   object:nil];

        [ShiroStatusBridge performSelector:@selector(markReady)
                                  withObject:nil
                                  afterDelay:2.0];
    }
}
