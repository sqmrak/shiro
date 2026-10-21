#import <Foundation/Foundation.h>
#define SHIRO_CONTROL_PATH "/var/run/shiro/control.sock"
#include "shiro_control_io.h"
NSDictionary *ShiroControlRequest(NSDictionary *request, NSError **error);
NSData *ShiroControlRead(int fd);
BOOL ShiroControlWrite(int fd, NSData *data);
void ShiroControlTimeout(int fd);
