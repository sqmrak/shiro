#import <Foundation/Foundation.h>

#include "shiro_status.h"

typedef enum {
    ShiroStateOff = 0,
    /* the first start has no account yet and asks the registration API for one */
    ShiroStateRegistering,
    /* the servers of the account are tried one after another */
    ShiroStateConnecting,
    ShiroStateUp,
    ShiroStateFailed
} ShiroState;

typedef enum {
    ShiroFailureNone = 0,
    /* the WARP account could not be made or read: no answer, a refused call, a reply that is not what the API returns */
    ShiroFailureAccount,
    /* every server that was tried stayed silent */
    ShiroFailureServer,
    /* a server answered with something that does not authenticate against the account's key */
    ShiroFailureKey
} ShiroFailure;

typedef struct {
    unsigned long long bytesIn, bytesOut;
    unsigned long long ageMs;
    unsigned handshakes;
} ShiroStats;

/* main thread: posted after every change of the state or the failure */
extern NSString *const ShiroStateDidChangeNotification;

/* the daemon owns the account, core and system tunnel */
@interface Shiro : NSObject

/* main thread only */
@property (nonatomic, readonly) ShiroState state;
@property (nonatomic, readonly) NSString *lastError;
@property (nonatomic, readonly) ShiroFailure failure;
/* whether the person wants the tunnel; kept across launches */
@property (nonatomic, readonly) BOOL enabled;


- (id)initWithDirectory:(NSString *)directory;

/* restore the saved connection intent when connect-at-startup is enabled */
- (void)resume;
- (void)shutdown;
- (BOOL)resetAccount;
- (NSString *)routeDescription;
- (NSDictionary *)accountInfo;
- (NSString *)registrationProxySummary;
/* an empty URL disables the proxy; changes require an idle, disconnected daemon */
- (shiro_status)setRegistrationProxy:(NSString *)url;
- (void)setEnabled:(BOOL)enabled;
/* after a failure: tries the account and the servers again from the start */
- (void)retry;
- (void)reconnect;
/* NO when the tunnel is not up or the core is busy; the figures are the ones of the last YES */
- (BOOL)stats:(ShiroStats *)stats;

@end
