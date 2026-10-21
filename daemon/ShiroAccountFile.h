#import <Foundation/Foundation.h>

#include "shiro_status.h"

/* account storage stays in the root-owned Shiro directory */
NSString *ShiroFilePath(NSString *directory, NSString *name);

/* the file is written aside and renamed, so a crash never leaves half of it behind; mode 0600 */
shiro_status ShiroWriteFile(NSString *path, const uint8_t *data, size_t len);
/* a missing file is SHIRO_E_NOTFOUND; buf holds cap bytes and the read stops there, so a caller that
   wants to catch a longer file passes one byte more than it expects */
shiro_status ShiroReadFile(NSString *path, uint8_t *buf, size_t cap, size_t *len);
