#import "ShiroAccountFile.h"

#import <errno.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>

NSString *ShiroFilePath(NSString *directory, NSString *name) {
    return [directory stringByAppendingPathComponent:name];
}

/* the file is written aside and renamed, so a crash never leaves half a key behind */
shiro_status ShiroWriteFile(NSString *path, const uint8_t *data, size_t len) {
    NSString *temporary = [path stringByAppendingString:@".tmp"];
    int fd = open(temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0600);
    if (fd < 0) return SHIRO_E_STORAGE;
    if (fchmod(fd, 0600) != 0) { close(fd); unlink(temporary.fileSystemRepresentation); return SHIRO_E_STORAGE; }
    size_t done = 0;
    while (done < len) {
        ssize_t n = write(fd, data + done, len - done);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) {
            close(fd);
            unlink(temporary.fileSystemRepresentation);
            return SHIRO_E_STORAGE;
        }
        done += (size_t)n;
    }
    BOOL synced = fsync(fd) == 0;
    BOOL closed = close(fd) == 0;
    if (!synced || !closed || rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) != 0) {
        unlink(temporary.fileSystemRepresentation);
        return SHIRO_E_STORAGE;
    }
    return SHIRO_OK;
}

/* a missing file is SHIRO_E_NOTFOUND; buf holds cap bytes and one more is read to catch a longer file */
shiro_status ShiroReadFile(NSString *path, uint8_t *buf, size_t cap, size_t *len) {
    if (len) *len = 0;
    if (!path || !buf || !len || !cap) return SHIRO_E_ARG;
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return errno == ENOENT ? SHIRO_E_NOTFOUND : SHIRO_E_STORAGE;
    size_t total = 0;
    for (;;) {
        ssize_t n = read(fd, buf + total, cap - total);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) {
            close(fd);
            return SHIRO_E_STORAGE;
        }
        if (n == 0) break;
        total += (size_t)n;
        if (total == cap) break;
    }
    close(fd);
    *len = total;
    return SHIRO_OK;
}
