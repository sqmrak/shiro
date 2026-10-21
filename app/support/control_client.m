#import "control_client.h"
#import "ShiroControl.h"
#import "app_log.h"
@implementation ShiroControl
- (id)initWithSocketPath:(NSString *)path {
    self = [super init];
    if (self && ![path isEqualToString:@SHIRO_CONTROL_PATH]) { [self release]; return nil; }
    return self;
}
- (void)request:(NSDictionary *)request reply:(void (^)(NSDictionary *, NSString *))done {
    NSString *verb = [request objectForKey:@"command"];
    BOOL record = ![verb isEqualToString:@"status"] && ![verb isEqualToString:@"logs"];
    if (record) ShiroAppLog(@"control command=%@ started", verb);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSError *error = nil;
        NSDictionary *response = ShiroControlRequest(request, &error);
        NSString *message = [response objectForKey:@"error"] ?: (response ? nil : error.localizedDescription);
        if (record) ShiroAppLog(@"control command=%@ %@", verb, message.length ? [@"failed: " stringByAppendingString:message] : @"completed");
        dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(response, message); });
        [pool drain];
    });
}
- (void)sendCommand:(NSString *)line timeoutMs:(int)timeout reply:(void (^)(NSString *))done {
    NSString *verb = [[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    NSDictionary *verbs = [NSDictionary dictionaryWithObjectsAndKeys:@"status", @"STATUS", @"diagnostics", @"DIAG", @"routes", @"UTUN_ROUTES", @"connect", @"CONNECT", @"disconnect", @"DISCONNECT", @"reconnect", @"RECONNECT", @"logs", @"LOGS", nil];
    NSString *command = [verbs objectForKey:verb];
    if (!command) { if (done) done(@"ERR unknown command. Use STATUS, DIAG, UTUN_ROUTES, CONNECT, DISCONNECT, RECONNECT or LOGS"); return; }
    [self request:[NSDictionary dictionaryWithObject:command forKey:@"command"] reply:^(NSDictionary *response, NSString *error) {
        if (done) done(error ? [@"ERR " stringByAppendingString:error] : [response description]);
    }];
}
- (void)daemonLogTail:(void (^)(NSString *))done {
    [self request:[NSDictionary dictionaryWithObject:@"logs" forKey:@"command"] reply:^(NSDictionary *response, NSString *error) {
        if (done) done(error ?: [response objectForKey:@"logs"] ?: @"");
    }];
}
@end
