#import <Foundation/Foundation.h>
#import "ShiroSession.h"
#import "ShiroControl.h"
#include "shiro_tunnel.h"
#include "shiro_warp.h"
#include "legacy_ios.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>
#include <errno.h>

static Shiro *vpn;
static dispatch_source_t signalSource;
static dispatch_source_t logTimer;

static NSDictionary *failure(NSString *message) {
    return [NSDictionary dictionaryWithObject:message forKey:@"error"];
}

static NSString *tailFile(NSString *path, NSUInteger cap) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return @"";
    unsigned long long length = [handle seekToEndOfFile];
    [handle seekToFileOffset:length > cap ? length - cap : 0];
    NSData *data = [handle readDataOfLength:cap];
    [handle closeFile];
    if (length > cap) {
        const uint8_t *bytes = data.bytes;
        const uint8_t *newline = memchr(bytes, '\n', data.length);
        if (newline) data = [data subdataWithRange:NSMakeRange((NSUInteger)(newline - bytes) + 1, data.length - (NSUInteger)(newline - bytes) - 1)];
    }
    NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!text) text = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    return text ?: @"";
}

static NSDictionary *command(NSDictionary *request) {
    NSString *name = [request objectForKey:@"command"];
    if (![name isKindOfClass:[NSString class]]) return failure(@"invalid command");
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([name isEqualToString:@"connect"]) [vpn setEnabled:YES];
    else if ([name isEqualToString:@"disconnect"]) [vpn setEnabled:NO];
    else if ([name isEqualToString:@"retry"]) [vpn retry];
    else if ([name isEqualToString:@"reconnect"]) [vpn reconnect];
    else if ([name isEqualToString:@"registrationProxy"]) {
        id url = [request objectForKey:@"url"];
        if (![url isKindOfClass:[NSString class]]) return failure(@"Invalid registration proxy");
        shiro_status status = [vpn setRegistrationProxy:url];
        if (status == SHIRO_E_STATE) return failure(@"Disconnect and wait for registration to finish before changing the proxy");
        if (status == SHIRO_E_ARG) return failure(@"Use socks5://host:port or http://host:port, with optional user:password@. Leave empty to disable.");
        if (status != SHIRO_OK) return failure(@"Could not save the registration proxy");
    }
    else if ([name isEqualToString:@"preference"]) {
        id key = [request objectForKey:@"key"], value = [request objectForKey:@"value"];
        if (![key isKindOfClass:[NSString class]] || ![value isKindOfClass:[NSNumber class]]) return failure(@"invalid preference");
        if ([value doubleValue] != (double)[value intValue]) return failure(@"invalid preference value");
        BOOL retryLimit = [key isEqualToString:@"reconnect_max_attempts"];
        if (retryLimit) {
            if ([value intValue] != 3 && [value intValue] != 5 && [value intValue] != 10) return failure(@"invalid reconnect limit");
        } else if (![key isEqualToString:@"auto_connect"] && ![key isEqualToString:@"auto_reconnect"] && ![key isEqualToString:@"failover"]) return failure(@"unknown preference");
        if (!retryLimit && [value intValue] != 0 && [value intValue] != 1) return failure(@"invalid switch value");
        NSString *preference = [@"shiro." stringByAppendingString:key];
        id old = [[defaults objectForKey:preference] retain];
        [defaults setObject:value forKey:preference];
        if (![defaults synchronize]) {
            if (old) [defaults setObject:old forKey:preference]; else [defaults removeObjectForKey:preference];
            [old release]; return failure(@"Could not save the setting");
        }
        [old release];
    }
    else if ([name isEqualToString:@"trace"]) {
        id trace = [request objectForKey:@"trace"];
        if (![trace isKindOfClass:[NSNumber class]]) return failure(@"invalid trace setting");
        [defaults setBool:[trace boolValue] forKey:@"shiro.trace"];
        if (![defaults synchronize]) return failure(@"Could not save the log setting");
    }
    else if ([name isEqualToString:@"settings"]) {
        if (vpn.enabled) return failure(@"Disconnect before changing settings");
        NSString *direct = [request objectForKey:@"direct"], *block = [request objectForKey:@"block"], *dns = [request objectForKey:@"dns"];
        NSNumber *trace = [request objectForKey:@"trace"];
        shiro_routing rules;
        uint32_t address;
        if (![direct isKindOfClass:[NSString class]] || ![block isKindOfClass:[NSString class]] || ![dns isKindOfClass:[NSString class]] ||
            ![trace isKindOfClass:[NSNumber class]] ||
            shiro_routing_parse(direct.UTF8String, block.UTF8String, &rules) != 0 ||
            shiro_warp_parse_ipv4(dns.UTF8String, strlen(dns.UTF8String), &address) != SHIRO_OK || !address)
            return failure(@"Invalid IPv4 networks or DNS. Use network/prefix (2-32), with no overlapping rules.");
        [defaults setObject:direct forKey:@"shiro.direct"];
        [defaults setObject:block forKey:@"shiro.block"];
        [defaults setObject:dns forKey:@"shiro.dns"];
        [defaults setBool:trace.boolValue forKey:@"shiro.trace"];
        if (![defaults synchronize]) return failure(@"Could not save settings");
    } else if ([name isEqualToString:@"logs"]) {
        NSString *install = tailFile(@"/var/root/Library/Shiro/install.log", 4000);
        NSString *previous = tailFile(@"/var/root/Library/Shiro/shiro.log.1", 12000);
        NSString *current = tailFile(@"/var/root/Library/Shiro/shiro.log", 28000);
        return [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"%@%@%@", install, previous, current] forKey:@"logs"];
    } else if ([name isEqualToString:@"clearLogs"]) {
        FILE *log = freopen("/var/root/Library/Shiro/shiro.log", "w", stderr);
        if (!log) return failure(@"Could not clear the log");
        if (chmod("/var/root/Library/Shiro/shiro.log", 0600) != 0 ||
            (unlink("/var/root/Library/Shiro/shiro.log.1") != 0 && errno != ENOENT)) return failure(@"Could not clear the log");
    } else if ([name isEqualToString:@"resetAccount"]) {
        if (vpn.enabled) return failure(@"Disconnect first");
        if (![vpn resetAccount]) return failure(@"Could not remove the account");
    } else if (![name isEqualToString:@"status"] && ![name isEqualToString:@"diagnostics"] && ![name isEqualToString:@"routes"]) return failure(@"unknown command");
    ShiroStats stats;
    memset(&stats, 0, sizeof(stats));
    [vpn stats:&stats];
    NSMutableDictionary *response = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInteger:vpn.state], @"state", [NSNumber numberWithInteger:vpn.failure], @"failure",
        [NSNumber numberWithBool:vpn.enabled], @"enabled", vpn.lastError, @"lastError",
        [NSNumber numberWithUnsignedLongLong:stats.bytesIn], @"bytesIn", [NSNumber numberWithUnsignedLongLong:stats.bytesOut], @"bytesOut",
        [NSNumber numberWithUnsignedLongLong:stats.uptimeMs], @"uptimeMs", [NSNumber numberWithUnsignedInt:stats.handshakes], @"handshakes",
        [defaults stringForKey:@"shiro.direct"] ?: @"", @"direct", [defaults stringForKey:@"shiro.block"] ?: @"", @"block",
        [defaults stringForKey:@"shiro.dns"] ?: @"1.1.1.1", @"dns", [NSNumber numberWithBool:[defaults boolForKey:@"shiro.trace"]], @"trace",
        [NSNumber numberWithInt:getpid()], @"pid", [NSNumber numberWithInt:shiro_ios_major()], @"ios",
        @"WARP / WireGuard / utun", @"backend", @"/var/root/Library/Shiro", @"directory", nil];
    for (NSString *key in [NSArray arrayWithObjects:@"auto_connect", @"auto_reconnect", @"failover", nil]) {
        id stored = [defaults objectForKey:[@"shiro." stringByAppendingString:key]];
        [response setObject:stored ?: [NSNumber numberWithBool:YES] forKey:key];
    }
    [response setObject:[defaults objectForKey:@"shiro.reconnect_max_attempts"] ?: [NSNumber numberWithInt:5] forKey:@"reconnect_max_attempts"];
    [response setObject:[vpn registrationProxySummary] forKey:@"registration_proxy"];
    [response addEntriesFromDictionary:[vpn accountInfo]];
    if ([name isEqualToString:@"routes"]) [response setObject:[vpn routeDescription] forKey:@"routes"];
    return response;
}

static void *serve(void *context) {
    int listener = *(int *)context;
    for (;;) {
        int fd = accept(listener, NULL, NULL);
        if (fd < 0) { if (errno == EINTR) continue; perror("shiro: accept"); return NULL; }
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        ShiroControlTimeout(fd);
        uid_t uid; gid_t gid;
        if (getpeereid(fd, &uid, &gid) == 0 && (uid == 0 || uid == 501)) {
            NSData *data = ShiroControlRead(fd);
            id decoded = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            if ([decoded isKindOfClass:[NSDictionary class]] && data.length <= 4096) {
                __block NSData *response = nil;
                dispatch_sync(dispatch_get_main_queue(), ^{
                    response = [[NSJSONSerialization dataWithJSONObject:command(decoded) options:0 error:NULL] retain];
                });
                if (!ShiroControlWrite(fd, response)) NSLog(@"shiro: control reply failed");
                [response release];
            }
        }
        close(fd);
        [pool drain];
    }
}

int main(int argc, char **argv) {
    /* lets the installer see whether the kernel kills the binary at exec, without starting the daemon */
    if (argc == 2 && strcmp(argv[1], "--probe") == 0) { puts("shirod"); return 0; }
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    if (geteuid() != 0) { fprintf(stderr, "shirod requires root\n"); return 1; }
    umask(0077);
    if ((mkdir("/var/root/Library/Shiro", 0700) != 0 && errno != EEXIST) ||
        (mkdir("/var/run/shiro", 0755) != 0 && errno != EEXIST)) { perror("shiro: state directory"); return 1; }
    chmod("/var/run/shiro", 0755);
    int lock = open("/var/root/Library/Shiro/daemon.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0600);
    if (lock < 0 || flock(lock, LOCK_EX | LOCK_NB) != 0) { fprintf(stderr, "shirod is already running or lock is unavailable\n"); return 1; }
    if (!freopen("/var/root/Library/Shiro/shiro.log", "a", stderr)) return 1;
    if (shiro_tunnel_recover() != 0) { NSLog(@"shiro: cannot recover previous routes"); return 1; }
    vpn = [[Shiro alloc] initWithDirectory:@"/var/root/Library/Shiro"];
    int listener = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    snprintf(address.sun_path, sizeof(address.sun_path), "%s", SHIRO_CONTROL_PATH);
    unlink(SHIRO_CONTROL_PATH);
    if (listener < 0 || bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0 ||
        chown(SHIRO_CONTROL_PATH, 0, 501) != 0 || chmod(SHIRO_CONTROL_PATH, 0660) != 0 || listen(listener, 4) != 0) {
        perror("shiro: control socket"); return 1;
    }
    pthread_t thread;
    if (pthread_create(&thread, NULL, serve, &listener) != 0) return 1;
    signal(SIGPIPE, SIG_IGN);
    signal(SIGTERM, SIG_IGN);
    signalSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(signalSource, ^{
        [vpn shutdown];
        unlink(SHIRO_CONTROL_PATH);
        exit(0);
    });
    dispatch_resume(signalSource);
    logTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(logTimer, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), 10 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(logTimer, ^{
        struct stat st;
        if (stat("/var/root/Library/Shiro/shiro.log", &st) == 0 && st.st_size > 262144) {
            if (rename("/var/root/Library/Shiro/shiro.log", "/var/root/Library/Shiro/shiro.log.1") != 0 ||
                !freopen("/var/root/Library/Shiro/shiro.log", "w", stderr)) {
                NSLog(@"shiro: log rotation failed (errno %d)", errno);
            }
        }
    });
    dispatch_resume(logTimer);
    [vpn resume];
    NSLog(@"shirod started, ios %d", shiro_ios_major());
    [pool drain];
    dispatch_main();
}
