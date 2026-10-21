#import "ShiroSession.h"

#include <pthread.h>
#include <errno.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <stdlib.h>

#include "shiro_bytes.h"
#include "shiro_clock.h"
#include "shiro_https.h"
#include "shiro_random.h"
#include "shiro_core.h"
#include "shiro_store.h"
#include "shiro_warp.h"

#import "ShiroAccountFile.h"
#include "shiro_tunnel.h"
#include <CoreFoundation/CoreFoundation.h>

NSString *const ShiroStateDidChangeNotification = @"ShiroStateDidChange";
static NSString *const ShiroEnabledKey = @"shiro.enabled";
static NSString *const ShiroAccountFile = @"shiro.account";
static NSString *const ShiroProxyFile = @"registration.proxy";

/* the registration call of the account. The path carries the version of the API and the header the build of the official client it was taken from,
   so they change together */
#define REGISTRATION_HOST "api.cloudflareclient.com"
#define REGISTRATION_PORT 443
#define REGISTRATION_PATH "/v0a4471/reg"
#define REGISTRATION_VERSION "CF-Client-Version: a-6.38-4471"
#define REGISTRATION_TIMEOUT_MS 15000
/* the first servers are the ones of the account, the rest are drawn; a silent network stops here instead of dialing for ever */
#define SERVER_ATTEMPTS 5u
#define INSTALL_ID_ALPHABET "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

typedef struct {
    Shiro *owner;
    uint32_t run;
    uint32_t serial;
    char physical[16];
} ShiroContext;

@interface Shiro () {
    NSString *_directory;
    shiro_tunnel _tunnel;
    NSString *_lastError;
    NSDictionary *_accountInfo;
    NSString *_routeText;
    NSString *_physicalInterface;
    /* account file, registration, and the start and stop of cores, one after another */
    dispatch_queue_t _queue;
    /* a stream is opened under the read side, so an core cannot be freed while a caller is inside it; main never takes the write side */
    pthread_rwlock_t _coreLock;
    shiro_core *_core;
    /* queue only */
    ShiroContext *_context;
    shiro_warp_identity _identity;
    /* main changes this only while the core queue is idle */
    shiro_proxy _registrationProxy;
    shiro_status _registrationProxyStatus;
    BOOL _identityLoaded;
    /* guards what other threads read: the route and the run that is still wanted */
    NSLock *_stateLock;
    uint32_t _liveRun;
    unsigned _queuePending;
    /* main thread only */
    ShiroState _state;
    ShiroFailure _failure;
    BOOL _enabled;
    uint32_t _run;
    /* every core start gets a number, so a late word from an core that was replaced is told apart */
    uint32_t _serial;
    unsigned _attempt;
    ShiroStats _lastStats;
}
@end

@implementation Shiro

- (NSString *)lastError { return _lastError ?: @""; }

@synthesize state = _state;
@synthesize failure = _failure;
@synthesize enabled = _enabled;

- (id)initWithDirectory:(NSString *)directory {
    self = [super init];
    if (!self) return nil;
    _directory = [directory copy];
    shiro_tunnel_init(&_tunnel);
    _queue = dispatch_queue_create("shiro.core", NULL);
    pthread_rwlock_init(&_coreLock, NULL);
    _stateLock = [[NSLock alloc] init];
    _enabled = [[NSUserDefaults standardUserDefaults] boolForKey:ShiroEnabledKey];
    uint8_t proxyURL[SHIRO_PROXY_URL_MAX + 1];
    size_t proxyLength = 0;
    _registrationProxyStatus = ShiroReadFile(ShiroFilePath(_directory, ShiroProxyFile), proxyURL, sizeof(proxyURL), &proxyLength);
    if (_registrationProxyStatus == SHIRO_E_NOTFOUND) _registrationProxyStatus = SHIRO_OK;
    else if (_registrationProxyStatus == SHIRO_OK)
        _registrationProxyStatus = shiro_proxy_parse((const char *)proxyURL, proxyLength, &_registrationProxy);
    shiro_wipe(proxyURL, sizeof(proxyURL));
    if (_registrationProxyStatus != SHIRO_OK) NSLog(@"shiro: registration proxy configuration failed: %s", shiro_status_name(_registrationProxyStatus));
    return self;
}

- (void)dealloc {
    dispatch_sync(_queue, ^{ [self stopCore]; });
    dispatch_release(_queue);
    pthread_rwlock_destroy(&_coreLock);
    shiro_wipe(&_identity, sizeof(_identity));
    shiro_wipe(&_registrationProxy, sizeof(_registrationProxy));
    [_stateLock release];
    [_directory release];
    [_lastError release];
    [_accountInfo release]; [_routeText release]; [_physicalInterface release];
    [super dealloc];
}

- (void)shutdown {
    [self newRun];
    dispatch_sync(_queue, ^{ [self stopCore]; });
    [self setState:ShiroStateOff failure:ShiroFailureNone];
}

- (BOOL)resetAccount {
    [_stateLock lock]; BOOL busy = _queuePending != 0; [_stateLock unlock];
    if (_enabled || busy) return NO;
    __block BOOL success = NO;
    dispatch_sync(_queue, ^{
        [self stopCore];
        success = unlink([self accountPath].fileSystemRepresentation) == 0 || errno == ENOENT;
        if (success) {
            shiro_wipe(&_identity, sizeof(_identity));
            _identityLoaded = NO;
        }
    });
    if (success) { [_accountInfo release]; _accountInfo = nil; }
    return success;
}

- (void)enqueue:(void (^)(void))work {
    [_stateLock lock]; ++_queuePending; [_stateLock unlock];
    dispatch_async(_queue, ^{
        @autoreleasepool { work(); }
        [_stateLock lock]; --_queuePending; [_stateLock unlock];
    });
}

- (NSDictionary *)accountInfo { return _accountInfo ?: [NSDictionary dictionary]; }

- (NSString *)registrationProxySummary {
    if (_registrationProxyStatus != SHIRO_OK) return @"Invalid registration proxy";
    if (_registrationProxy.type == SHIRO_PROXY_NONE) return @"Off";
    NSString *host = [NSString stringWithUTF8String:_registrationProxy.host];
    if (strchr(_registrationProxy.host, ':')) host = [NSString stringWithFormat:@"[%@]", host];
    return [NSString stringWithFormat:@"%@ %@:%u", _registrationProxy.type == SHIRO_PROXY_SOCKS5 ? @"SOCKS5" : @"HTTP", host, (unsigned)_registrationProxy.port];
}

- (shiro_status)setRegistrationProxy:(NSString *)url {
    [_stateLock lock]; BOOL busy = _queuePending != 0; [_stateLock unlock];
    if (_enabled || busy) return SHIRO_E_STATE;
    NSData *data = [url dataUsingEncoding:NSUTF8StringEncoding];
    shiro_proxy proxy;
    shiro_status status = data ? shiro_proxy_parse(data.length ? data.bytes : "", data.length, &proxy) : SHIRO_E_ARG;
    if (status != SHIRO_OK) return status;
    __block shiro_status saved = SHIRO_E_STORAGE;
    dispatch_sync(_queue, ^{ saved = ShiroWriteFile(ShiroFilePath(_directory, ShiroProxyFile), data.bytes, data.length); });
    if (saved == SHIRO_OK) {
        shiro_wipe(&_registrationProxy, sizeof(_registrationProxy));
        _registrationProxy = proxy;
        _registrationProxyStatus = SHIRO_OK;
    }
    shiro_wipe(&proxy, sizeof(proxy));
    return saved;
}

- (NSString *)routeDescription {
    [_stateLock lock];
    NSString *text = [_routeText retain];
    [_stateLock unlock];
    return [text autorelease] ?: @"";
}

#pragma mark state

- (BOOL)runIsLive:(uint32_t)run {
    [_stateLock lock];
    BOOL live = _liveRun == run;
    [_stateLock unlock];
    return live;
}

/* main thread */
- (uint32_t)newRun {
    ++_run;
    [_stateLock lock];
    _liveRun = _run;
    [_stateLock unlock];
    return _run;
}

/* umask 0077 protects account keys, but springboard needs a readable status file */
static BOOL ShiroPublishBadge(NSString *badge) {
    char path[] = "/var/root/Library/Shiro/status.XXXXXX";
    int fd = mkstemp(path);
    if (fd < 0) return NO;
    const char *bytes = badge.UTF8String;
    size_t length = strlen(bytes), used = 0;
    BOOL ok = YES;
    while (used < length) {
        ssize_t count = write(fd, bytes + used, length - used);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) { ok = NO; break; }
        used += (size_t)count;
    }
    if (ok && fchmod(fd, 0644) != 0) ok = NO;
    if (close(fd) != 0) ok = NO;
    if (ok && rename(path, "/var/mobile/Library/Preferences/com.shiro.status.state") != 0) ok = NO;
    if (!ok && unlink(path) != 0) NSLog(@"shiro: cannot remove status staging file (errno %d)", errno);
    return ok;
}

- (void)setState:(ShiroState)state failure:(ShiroFailure)failure {
    NSLog(@"shiro: state %ld -> %ld failure=%ld run=%u physical=%@", (long)_state, (long)state, (long)failure, _run, _physicalInterface ?: @"none");
    _state = state;
    _failure = failure;
    NSString *badge = state == ShiroStateUp ? [NSString stringWithFormat:@"1 %@\n", _physicalInterface ?: @""] : @"0\n";
    if (!ShiroPublishBadge(badge))
        NSLog(@"shiro: cannot publish status badge");
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.shiro.status.changed"), NULL, NULL, true);
    [[NSNotificationCenter defaultCenter] postNotificationName:ShiroStateDidChangeNotification object:self];
}

- (void)resume {
    id autoConnect = [[NSUserDefaults standardUserDefaults] objectForKey:@"shiro.auto_connect"];
    [self setState:ShiroStateOff failure:ShiroFailureNone];
    if (_enabled && (!autoConnect || [autoConnect boolValue])) [self begin];
    else _enabled = NO;
}

- (void)setEnabled:(BOOL)enabled {
    if (enabled == _enabled) return;
    _enabled = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:ShiroEnabledKey];
    if (![[NSUserDefaults standardUserDefaults] synchronize]) NSLog(@"shiro: the VPN switch was not saved");
    if (enabled) {
        [self begin];
        return;
    }
    [self newRun];
    [self setState:ShiroStateOff failure:ShiroFailureNone];
    [self enqueue:^{ [self stopCore]; }];
}

- (void)retry {
    if (_enabled && _state == ShiroStateFailed) [self begin];
}

- (void)reconnect {
    if (_enabled) [self begin];
}

- (void)begin {
    memset(&_lastStats, 0, sizeof(_lastStats));
    [_lastError release];
    _lastError = nil;
    uint32_t run = [self newRun];
    uint32_t serial = ++_serial;
    _attempt = 0;
    [self setState:ShiroStateConnecting failure:ShiroFailureNone];
    [self enqueue:^{ [self prepareRun:run serial:serial]; }];
}

- (void)failRun:(uint32_t)run with:(ShiroFailure)failure {
    if (run != _run || !_enabled) return;
    [self newRun];
    [self setState:ShiroStateFailed failure:failure];
    [self enqueue:^{ [self stopCore]; }];
}

- (void)registeringRun:(uint32_t)run {
    if (run != _run || !_enabled) return;
    [self setState:ShiroStateRegistering failure:ShiroFailureNone];
}

- (void)connectingRun:(uint32_t)run {
    if (run != _run || !_enabled) return;
    [self setState:ShiroStateConnecting failure:ShiroFailureNone];
}

/* main thread, from the core's callback */
- (void)coreState:(shiro_state)state reason:(shiro_status)reason run:(uint32_t)run serial:(uint32_t)serial {
    if (run != _run || serial != _serial || !_enabled) return;
    if (state == SHIRO_UP) {
        _attempt = 0;
        [self setState:ShiroStateUp failure:ShiroFailureNone];
        return;
    }
    if (state != SHIRO_DOWN) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id reconnect = [defaults objectForKey:@"shiro.auto_reconnect"];
    if (reconnect && ![reconnect boolValue]) {
        [self failRun:run with:ShiroFailureServer]; return;
    }
    BOOL wasUp = _state == ShiroStateUp;
    /* a tunnel that was working starts again from the account's own server; one that never answered goes on to the next server */
    _attempt = wasUp ? 0 : _attempt + 1;
    id failover = [defaults objectForKey:@"shiro.failover"];
    unsigned limit = [defaults objectForKey:@"shiro.reconnect_max_attempts"] ? (unsigned)[defaults integerForKey:@"shiro.reconnect_max_attempts"] : SERVER_ATTEMPTS;
    if (failover && ![failover boolValue]) limit = 1;
    if (_attempt >= limit) {
        [self failRun:run with:reason == SHIRO_E_SECURITY ? ShiroFailureKey : ShiroFailureServer];
        return;
    }
    NSLog(@"shiro: the tunnel went down (%s), next server is %u", shiro_status_name(reason), _attempt);
    uint32_t next = ++_serial;
    unsigned attempt = _attempt;
    [self setState:ShiroStateConnecting failure:ShiroFailureNone];
    [self enqueue:^{ [self startCoreForRun:run serial:next attempt:attempt]; }];
}

static void ShiroCoreState(void *context, shiro_state state, shiro_status reason) {
    @autoreleasepool {
    ShiroContext *c = context;
    Shiro *owner = c->owner;
    uint32_t run = c->run, serial = c->serial;
    NSString *physical = [NSString stringWithUTF8String:c->physical];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (run == owner->_run && serial == owner->_serial) {
            [owner->_physicalInterface release]; owner->_physicalInterface = [physical copy];
        }
        [owner coreState:state reason:reason run:run serial:serial];
    });
    }
}

static void ShiroCoreTrace(void *context, const char *line) {
    @autoreleasepool {
    (void)context;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"shiro.trace"]) NSLog(@"shiro: %s", line);
    }
}

#pragma mark queue

- (NSString *)accountPath {
    return ShiroFilePath(_directory, ShiroAccountFile);
}

/* SHIRO_E_NOTFOUND when there is no usable account; an unreadable one is deleted, since only a new registration repairs it */
- (shiro_status)loadIdentity {
    uint8_t buf[SHIRO_STORE_LEN + 1];
    size_t len = 0;
    shiro_status status = ShiroReadFile([self accountPath], buf, sizeof(buf), &len);
    if (status != SHIRO_OK) { shiro_wipe(buf, sizeof(buf)); return status; }
    status = shiro_store_unpack(buf, len, &_identity);
    shiro_wipe(buf, sizeof(buf));
    if (status != SHIRO_OK) {
        NSLog(@"shiro: the stored account is unusable, registering a new one");
        if (unlink([self accountPath].fileSystemRepresentation) != 0 && errno != ENOENT) return SHIRO_E_STORAGE;
        return SHIRO_E_NOTFOUND;
    }
    return SHIRO_OK;
}

- (shiro_status)storeIdentity {
    uint8_t buf[SHIRO_STORE_LEN];
    size_t len = 0;
    shiro_status status = shiro_store_pack(&_identity, buf, sizeof(buf), &len);
    if (status == SHIRO_OK) status = ShiroWriteFile([self accountPath], buf, len);
    shiro_wipe(buf, sizeof(buf));
    return status;
}

static shiro_status ShiroInstallId(char id[SHIRO_WARP_INSTALL_ID_LEN + 1]) {
    size_t filled = 0;
    for (int round = 0; round < 8 && filled < SHIRO_WARP_INSTALL_ID_LEN; ++round) {
        uint8_t raw[32];
        if (shiro_random(raw, sizeof(raw)) != SHIRO_OK) return SHIRO_E_CRYPTO;
        for (size_t i = 0; i < sizeof(raw) && filled < SHIRO_WARP_INSTALL_ID_LEN; ++i) {
            /* 248 is the largest multiple of 62 in a byte, so the letters come out evenly */
            if (raw[i] < 248) id[filled++] = INSTALL_ID_ALPHABET[raw[i] % 62];
        }
    }
    id[filled] = '\0';
    return filled == SHIRO_WARP_INSTALL_ID_LEN ? SHIRO_OK : SHIRO_E_CRYPTO;
}

static void ShiroTimestamp(char out[32]) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    time_t seconds = (time_t)now;
    struct tm parts;
    gmtime_r(&seconds, &parts);
    int millis = (int)((now - (NSTimeInterval)seconds) * 1000.0);
    if (millis < 0 || millis > 999) millis = 0;
    snprintf(out, 32, "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", parts.tm_year + 1900, parts.tm_mon + 1, parts.tm_mday, parts.tm_hour, parts.tm_min, parts.tm_sec,
             millis);
}

/* makes the account on the first start. The trust is the bundled roots alone: the system store of an old iOS lacks today's, and the call carries the key */
- (shiro_status)registerIdentity {
    if (_registrationProxyStatus != SHIRO_OK) return _registrationProxyStatus;
    NSString *rootsPath = @"/var/jb/Applications/Shiro.app/roots.pem";
    NSData *roots = rootsPath ? [NSData dataWithContentsOfFile:rootsPath] : nil;
    if (![roots length]) {
        NSLog(@"shiro: registration trust roots unavailable at %@", rootsPath);
        return SHIRO_E_NOTFOUND;
    }

    uint8_t privateKey[SHIRO_WG_KEY_LEN], publicKey[SHIRO_WG_KEY_LEN];
    char installId[SHIRO_WARP_INSTALL_ID_LEN + 1], tos[32], body[1024];
    size_t bodyLen = 0;
    shiro_status status = shiro_warp_generate_key(privateKey, publicKey);
    if (status == SHIRO_OK) status = ShiroInstallId(installId);
    if (status != SHIRO_OK) goto done;
    ShiroTimestamp(tos);
    status = shiro_warp_registration_body(publicKey, installId, tos, body, sizeof(body), &bodyLen);
    if (status != SHIRO_OK) goto done;

    static const char *const headers[] = {"Content-Type: application/json; charset=UTF-8", "User-Agent: okhttp/3.12.1", REGISTRATION_VERSION, NULL};
    shiro_https_request request;
    shiro_https_response response;
    memset(&request, 0, sizeof(request));
    request.host = REGISTRATION_HOST;
    request.port = REGISTRATION_PORT;
    request.path = REGISTRATION_PATH;
    request.headers = headers;
    request.body = (const uint8_t *)body;
    request.body_len = bodyLen;
    request.roots_pem = roots.bytes;
    request.roots_len = roots.length;
    request.timeout_ms = REGISTRATION_TIMEOUT_MS;
    request.proxy = _registrationProxy.type == SHIRO_PROXY_NONE ? NULL : &_registrationProxy;
    /* a network that reads the SNI of one segment drops the plain hello; the second try writes it in pieces. Only a dead path is worth a second try:
       a refused certificate or a reply that is not HTTP would come back the same */
    for (int split = 0; split < (request.proxy ? 1 : 2); ++split) {
        NSLog(@"shiro: WARP registration attempt %d (%@)", split + 1, request.proxy ? @"proxy TLS" : split ? @"split TLS hello" : @"TLS");
        request.split_hello = split;
        uint64_t started = shiro_system_clock.monotonic_ms(NULL);
        status = shiro_https_post(&request, &response);
        NSLog(@"shiro: registration stage=%s result=%s elapsed=%llu ms HTTP=%d", response.stage ?: "unknown", shiro_status_name(status),
              (unsigned long long)(shiro_system_clock.monotonic_ms(NULL) - started), response.status);
        if (status == SHIRO_OK || (status != SHIRO_E_IO && status != SHIRO_E_TIMEOUT)) break;
    }
    if (status != SHIRO_OK) goto done;
    if (response.status < 200 || response.status > 299) {
        NSLog(@"shiro: the registration call answered %d", response.status);
        status = SHIRO_E_RPC;
    } else {
        status = shiro_warp_parse_registration((const char *)response.body, response.body_len, privateKey, &_identity);
    }
    shiro_https_response_free(&response);
    if (status == SHIRO_OK) {
        status = [self storeIdentity];
        NSLog(@"shiro: registration account storage: %s", shiro_status_name(status));
        if (status != SHIRO_OK) shiro_wipe(&_identity, sizeof(_identity));
    }
done:
    shiro_wipe(privateKey, sizeof(privateKey));
    return status;
}

- (void)prepareRun:(uint32_t)run serial:(uint32_t)serial {
    NSLog(@"shiro: preparing WARP account");
    if (![self runIsLive:run]) return;
    if (!_identityLoaded) {
        shiro_status status = [self loadIdentity];
        if (status == SHIRO_E_NOTFOUND) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self registeringRun:run]; });
            status = [self registerIdentity];
            if (status != SHIRO_OK) {
                NSString *message = [NSString stringWithFormat:@"WARP registration failed: %s", shiro_status_name(status)];
                NSLog(@"shiro: %@", message);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (run != _run) return;
                    [_lastError release]; _lastError = [message copy];
                });
            }
            dispatch_async(dispatch_get_main_queue(), ^{ [self connectingRun:run]; });
        }
        if (status != SHIRO_OK) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self failRun:run with:ShiroFailureAccount]; });
            return;
        }
        _identityLoaded = YES;
    }
    uint32_t address = htonl(_identity.address), endpoint = htonl(_identity.endpoint_ip);
    char addressText[INET_ADDRSTRLEN], endpointText[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &address, addressText, sizeof(addressText));
    inet_ntop(AF_INET, &endpoint, endpointText, sizeof(endpointText));
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithUTF8String:addressText], @"tunnel_address", [NSString stringWithUTF8String:endpointText], @"endpoint", nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (run == _run) { [_accountInfo release]; _accountInfo = [info copy]; }
    });
    [self startCoreForRun:run serial:serial attempt:0];
}

- (void)startCoreForRun:(uint32_t)run serial:(uint32_t)serial attempt:(unsigned)attempt {
    [self stopCore];
    /* a run that ended while this block waited its turn must not bring a tunnel up */
    if (![self runIsLive:run]) return;
    uint32_t ip = 0;
    uint16_t port = 0;
    shiro_status status = shiro_warp_endpoint(&_identity, attempt, &ip, &port);
    uint32_t networkIP = htonl(ip);
    char endpointText[INET_ADDRSTRLEN] = "";
    inet_ntop(AF_INET, &networkIP, endpointText, sizeof(endpointText));
    NSLog(@"shiro: server attempt=%u endpoint=%s:%u", attempt + 1, endpointText, (unsigned)port);
    ShiroContext *context = status == SHIRO_OK ? calloc(1, sizeof(*context)) : NULL;
    shiro_core *core = NULL;
    if (context) {
        context->owner = self;
        context->run = run;
        context->serial = serial;
        shiro_events events = {context, ShiroCoreState, ShiroCoreTrace};
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        shiro_routing routing;
        NSString *direct = [defaults stringForKey:@"shiro.direct"] ?: @"";
        NSString *block = [defaults stringForKey:@"shiro.block"] ?: @"";
        NSString *dns = [defaults stringForKey:@"shiro.dns"] ?: @"1.1.1.1";
        char error[512] = "";
        if (shiro_routing_parse(direct.UTF8String, block.UTF8String, &routing) != 0) {
            snprintf(error, sizeof(error), "invalid routing rules");
            status = SHIRO_E_ARG;
        } else if (shiro_tunnel_open(&_tunnel, _identity.address, ip, &routing, dns.UTF8String, error, sizeof(error)) != 0) {
            status = SHIRO_E_IO;
        } else {
            snprintf(context->physical, sizeof(context->physical), "%s", _tunnel.plan.physical_ifname);
            char routes[16384];
            int n = tun_plan_render(&_tunnel.plan, routes, sizeof(routes));
            [_stateLock lock];
            [_routeText release];
            _routeText = n >= 0 && (size_t)n < sizeof(routes) ? [[NSString alloc] initWithUTF8String:routes] : [@"route list exceeds the buffer" copy];
            [_stateLock unlock];
            status = shiro_core_start_packets(&core, &_identity, ip, port, &events, _tunnel.device.fd, &routing);
        }
        if (error[0]) {
            NSString *message = [NSString stringWithUTF8String:error];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (run != _run || serial != _serial) return;
                [_lastError release]; _lastError = [message copy];
            });
            NSLog(@"shiro: %s", error);
        }
    } else if (status == SHIRO_OK) {
        status = SHIRO_E_NOMEM;
    }
    if (status != SHIRO_OK) {
        NSLog(@"shiro: the core did not start: %s", shiro_status_name(status));
        shiro_tunnel_close(&_tunnel);
        free(context);
        dispatch_async(dispatch_get_main_queue(), ^{ [self failRun:run with:ShiroFailureServer]; });
        return;
    }
    pthread_rwlock_wrlock(&_coreLock);
    _core = core;
    pthread_rwlock_unlock(&_coreLock);
    _context = context;
}

/* queue only. The write side waits for the streams that are being opened, then the core ends them and joins its thread, so no callback comes after it */
- (void)stopCore {
    pthread_rwlock_wrlock(&_coreLock);
    shiro_core *core = _core;
    _core = NULL;
    if (core) shiro_core_stop(core);
    pthread_rwlock_unlock(&_coreLock);
    free(_context);
    _context = NULL;
    shiro_tunnel_close(&_tunnel);
    [_stateLock lock]; [_routeText release]; _routeText = nil; [_stateLock unlock];
}

#pragma mark use

- (BOOL)stats:(ShiroStats *)stats {
    if (_state != ShiroStateUp || pthread_rwlock_tryrdlock(&_coreLock) != 0) {
        if (stats) *stats = _lastStats;
        return NO;
    }
    BOOL got = NO;
    if (_core) {
        shiro_stats raw;
        memset(&raw, 0, sizeof(raw));
        shiro_core_stats(_core, &raw);
        _lastStats.bytesIn = raw.bytes_in;
        _lastStats.bytesOut = raw.bytes_out;
        _lastStats.ageMs = raw.session_age_ms;
        _lastStats.handshakes = raw.handshakes;
        got = YES;
    }
    pthread_rwlock_unlock(&_coreLock);
    if (stats) *stats = _lastStats;
    return got;
}

@end
