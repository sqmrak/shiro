#include "shiro_random.h"

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

shiro_status shiro_random(void *buf, size_t n) {
    uint8_t *p = (uint8_t *)buf;
    int fd;
    if (n && !buf) return SHIRO_E_ARG;
    if (!n) return SHIRO_OK;
    fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) return SHIRO_E_IO;
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) < 0) { close(fd); return SHIRO_E_IO; }
    while (n) {
        ssize_t got = read(fd, p, n);
        if (got < 0) {
            if (errno == EINTR) continue;
            close(fd);
            return SHIRO_E_IO;
        }
        if (got == 0) {
            close(fd);
            return SHIRO_E_EOF;
        }
        p += got;
        n -= (size_t)got;
    }
    close(fd);
    return SHIRO_OK;
}

shiro_status shiro_random_u64(uint64_t *out) {
    uint8_t b[8];
    shiro_status s;
    uint64_t v = 0;
    int i;
    if (!out) return SHIRO_E_ARG;
    *out = 0;
    s = shiro_random(b, sizeof(b));
    if (s != SHIRO_OK) {
        return s;
    }
    for (i = 0; i < 8; ++i) v = (v << 8) | b[i];
    *out = v;
    return SHIRO_OK;
}
