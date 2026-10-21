#include "shiro_control_io.h"
#include "shiro_clock.h"
#include <sys/socket.h>
#include <poll.h>
#include <errno.h>
#include <limits.h>
#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

static shiro_status transfer(int fd, uint8_t *bytes, size_t length, int writing, uint64_t deadline) {
    size_t done = 0;
    while (done < length) {
        uint64_t now = shiro_system_clock.monotonic_ms(NULL);
        if (now >= deadline) return SHIRO_E_TIMEOUT;
        uint64_t left = deadline - now;
        struct pollfd p = {fd, writing ? POLLOUT : POLLIN, 0};
        int rc = poll(&p, 1, left > INT_MAX ? INT_MAX : (int)left);
        if (rc < 0) { if (errno == EINTR) continue; return SHIRO_E_IO; }
        if (!rc) continue;
        if (p.revents & POLLNVAL) return SHIRO_E_IO;
        ssize_t n = writing ? send(fd, bytes + done, length - done, MSG_DONTWAIT | MSG_NOSIGNAL)
                            : recv(fd, bytes + done, length - done, MSG_DONTWAIT);
        if (n < 0) {
            if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) continue;
            return SHIRO_E_IO;
        }
        if (!n) return writing ? SHIRO_E_IO : SHIRO_E_EOF;
        done += (size_t)n;
    }
    return SHIRO_OK;
}

shiro_status shiro_control_read(int fd, uint8_t *buffer, size_t cap, size_t *length, int timeout_ms) {
    uint8_t header[4];
    if (length) *length = 0;
    if (fd < 0 || !buffer || !length || !cap || timeout_ms <= 0) return SHIRO_E_ARG;
    uint64_t deadline = shiro_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    shiro_status status = transfer(fd, header, sizeof(header), 0, deadline);
    if (status != SHIRO_OK) return status;
    uint32_t count = ((uint32_t)header[0] << 24) | ((uint32_t)header[1] << 16) | ((uint32_t)header[2] << 8) | header[3];
    if (!count) return SHIRO_E_MALFORMED;
    if (count > cap || count > SHIRO_CONTROL_MAX) return SHIRO_E_LIMIT;
    status = transfer(fd, buffer, count, 0, deadline);
    if (status == SHIRO_OK) *length = count;
    return status;
}

shiro_status shiro_control_write(int fd, const uint8_t *buffer, size_t length, int timeout_ms) {
    if (fd < 0 || !buffer || !length || timeout_ms <= 0) return SHIRO_E_ARG;
    if (length > SHIRO_CONTROL_MAX) return SHIRO_E_LIMIT;
    uint64_t deadline = shiro_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    uint8_t header[4] = {(uint8_t)(length >> 24), (uint8_t)(length >> 16), (uint8_t)(length >> 8), (uint8_t)length};
    shiro_status status = transfer(fd, header, sizeof(header), 1, deadline);
    return status == SHIRO_OK ? transfer(fd, (uint8_t *)buffer, length, 1, deadline) : status;
}
