#import "ShiroControl.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/time.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

void ShiroControlTimeout(int fd) {
    struct timeval timeout = {3, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
#ifdef SO_NOSIGPIPE
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
}

NSData *ShiroControlRead(int fd) {
    NSMutableData *data = [NSMutableData dataWithLength:SHIRO_CONTROL_MAX];
    size_t length = 0;
    if (shiro_control_read(fd, data.mutableBytes, data.length, &length, 3000) != SHIRO_OK) return nil;
    [data setLength:length];
    return data;
}

BOOL ShiroControlWrite(int fd, NSData *data) {
    return shiro_control_write(fd, data.bytes, data.length, 3000) == SHIRO_OK;
}

NSDictionary *ShiroControlRequest(NSDictionary *request, NSError **error) {
    NSData *body = [NSJSONSerialization dataWithJSONObject:request options:0 error:error];
    if (!body) return nil;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) goto fail;
    ShiroControlTimeout(fd);
    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    snprintf(address.sun_path, sizeof(address.sun_path), "%s", SHIRO_CONTROL_PATH);
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) { close(fd); goto fail; }
    uid_t uid; gid_t gid;
    if (getpeereid(fd, &uid, &gid) != 0 || uid != 0) { close(fd); goto fail; }
    if (!ShiroControlWrite(fd, body)) { close(fd); goto fail; }
    NSData *reply = ShiroControlRead(fd);
    close(fd);
    if (!reply) goto fail;
    id decoded = [NSJSONSerialization JSONObjectWithData:reply options:0 error:error];
    if (![decoded isKindOfClass:[NSDictionary class]]) goto fail;
    return decoded;
fail:
    if (error) *error = [NSError errorWithDomain:@"Shiro" code:1 userInfo:[NSDictionary dictionaryWithObject:@"Could not reach shirod. Check the daemon launch log." forKey:NSLocalizedDescriptionKey]];
    return nil;
}
