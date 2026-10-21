#import <Foundation/Foundation.h>
#include <stdint.h>
@interface ShiroControl : NSObject
- (id)initWithSocketPath:(NSString *)path;
- (void)request:(NSDictionary *)request reply:(void (^)(NSDictionary *response, NSString *error))done;
- (void)sendCommand:(NSString *)command timeoutMs:(int)timeout reply:(void (^)(NSString *reply))done;
- (void)daemonLogTail:(void (^)(NSString *text))done;
@end
