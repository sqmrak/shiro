#import "app_log.h"
#import "app_common.h"
#include "shiro_log.h"
#include "shiro_paths.h"
#include <stdarg.h>
#include <time.h>
#include <unistd.h>

void ShiroAppLog(NSString *format, ...) {
    if (!format) return;
    @autoreleasepool {
        va_list args;
        va_start(args, format);
        NSString *message = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
        va_end(args);
        NSString *safe = ShiroRedactSecrets(message);
        if (safe.length > 2048) safe = [[safe substringToIndex:2048] stringByAppendingString:@" [truncated]"];
        time_t seconds = time(NULL);
        struct tm utc;
        char stamp[32];
        gmtime_r(&seconds, &utc);
        strftime(stamp, sizeof(stamp), "%Y-%m-%dT%H:%M:%SZ", &utc);
        NSString *line = [NSString stringWithFormat:@"%s pid=%d %@\n", stamp, (int)getpid(), safe];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (!data || shiro_log_append(SHIRO_APP_LOG, data.bytes, data.length, 65536) != SHIRO_OK)
            NSLog(@"shiro: could not write the application log");
    }
}
