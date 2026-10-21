#include "shiro_socket.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <pthread.h>
#include <sys/time.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#include "shiro_clock.h"

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

void shiro_socket_init(shiro_socket *s) {
    s->fd = -1;
}

void shiro_socket_close(shiro_socket *s) {
    if (s->fd >= 0) close(s->fd);
    s->fd = -1;
}

static shiro_status set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) return SHIRO_E_IO;
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) < 0) return SHIRO_E_IO;
    return SHIRO_OK;
}

static int remaining_ms(uint64_t deadline) {
    uint64_t now = shiro_system_clock.monotonic_ms(NULL);
    if (now >= deadline) return 0;
    return deadline - now > INT_MAX ? INT_MAX : (int)(deadline - now);
}

/* poll restarts after a signal with the time that is left, so a signal storm cannot stretch a timeout */
static shiro_status wait_fd(int fd, short events, uint64_t deadline) {
    for (;;) {
        struct pollfd p;
        int rc;
        p.fd = fd;
        p.events = events;
        p.revents = 0;
        rc = poll(&p, 1, remaining_ms(deadline));
        if (rc < 0) {
            if (errno == EINTR) continue;
            return SHIRO_E_IO;
        }
        if (rc == 0) return SHIRO_E_TIMEOUT;
        if (p.revents & POLLNVAL) return SHIRO_E_IO;
        if (p.revents & (events | POLLERR | POLLHUP)) return SHIRO_OK;
    }
}

static shiro_status connect_one(const struct addrinfo *ai, uint64_t deadline, int *out_fd) {
    int fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
    shiro_status s;
    int err = 0;
    socklen_t len = sizeof(err);
    if (fd < 0) return SHIRO_E_IO;
#ifdef SO_NOSIGPIPE
    {
        /* ios has no MSG_NOSIGNAL, a write to a closed peer would kill the process */
        int one = 1;
        if (setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)) != 0) { close(fd); return SHIRO_E_IO; }
    }
#endif
    s = set_nonblocking(fd);
    if (s != SHIRO_OK) {
        close(fd);
        return s;
    }
    if (connect(fd, ai->ai_addr, ai->ai_addrlen) != 0) {
        if (errno != EINPROGRESS && errno != EINTR) {
            close(fd);
            return SHIRO_E_IO;
        }
        s = wait_fd(fd, POLLOUT, deadline);
        if (s != SHIRO_OK) {
            close(fd);
            return s;
        }
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) != 0 || err != 0) {
            close(fd);
            errno = err;
            return SHIRO_E_IO;
        }
    }
    {
        int one = 1;
        (void)setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    }
    *out_fd = fd;
    return SHIRO_OK;
}

/* ios 5 getaddrinfo can wait beyond the connect timeout when DNS is unreachable */
static pthread_mutex_t resolver_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t resolver_ready = PTHREAD_COND_INITIALIZER;
static struct {
    char host[254], service[8];
    struct addrinfo hints, *result;
    int busy, done, abandoned, error;
} resolver;

static void *resolve_host(void *unused) {
    struct addrinfo *result = NULL;
    int error;
    (void)unused;
    error = getaddrinfo(resolver.host, resolver.service, &resolver.hints, &result);
    pthread_mutex_lock(&resolver_lock);
    if (resolver.abandoned) {
        if (result) freeaddrinfo(result);
        resolver.busy = 0;
    } else {
        resolver.result = result;
        resolver.error = error;
        resolver.done = 1;
        pthread_cond_signal(&resolver_ready);
    }
    pthread_mutex_unlock(&resolver_lock);
    return NULL;
}

static shiro_status resolve_until(const char *host, const char *service,
                                  const struct addrinfo *hints, uint64_t deadline,
                                  struct addrinfo **result) {
    pthread_t worker;
    pthread_attr_t attributes;
    shiro_status status = SHIRO_E_IO;
    unsigned char numeric[16];
    *result = NULL;
    if (inet_pton(AF_INET, host, numeric) == 1 || inet_pton(AF_INET6, host, numeric) == 1) {
        struct addrinfo numeric_hints = *hints;
        numeric_hints.ai_flags |= AI_NUMERICHOST;
        return getaddrinfo(host, service, &numeric_hints, result) == 0 ? SHIRO_OK : SHIRO_E_IO;
    }
    if (strlen(host) >= sizeof(resolver.host)) return SHIRO_E_ARG;
    pthread_mutex_lock(&resolver_lock);
    /* one blocked system resolver consumes at most one worker */
    if (resolver.busy) { pthread_mutex_unlock(&resolver_lock); return SHIRO_E_STATE; }
    memset(&resolver, 0, sizeof(resolver));
    resolver.busy = 1;
    snprintf(resolver.host, sizeof(resolver.host), "%s", host);
    snprintf(resolver.service, sizeof(resolver.service), "%s", service);
    resolver.hints = *hints;
    int rc = pthread_attr_init(&attributes);
    if (rc == 0) {
        rc = pthread_attr_setdetachstate(&attributes, PTHREAD_CREATE_DETACHED);
        if (rc == 0) rc = pthread_create(&worker, &attributes, resolve_host, NULL);
        pthread_attr_destroy(&attributes);
    }
    if (rc != 0) { resolver.busy = 0; pthread_mutex_unlock(&resolver_lock); return SHIRO_E_IO; }
    while (!resolver.done) {
        int left = remaining_ms(deadline);
        struct timeval now;
        struct timespec until;
        if (!left) { status = SHIRO_E_TIMEOUT; break; }
        gettimeofday(&now, NULL);
        until.tv_sec = now.tv_sec + left / 1000;
        until.tv_nsec = (now.tv_usec + (left % 1000) * 1000L) * 1000L;
        if (until.tv_nsec >= 1000000000L) { ++until.tv_sec; until.tv_nsec -= 1000000000L; }
        rc = pthread_cond_timedwait(&resolver_ready, &resolver_lock, &until);
        if (rc != 0 && rc != ETIMEDOUT) break;
    }
    if (resolver.done) {
        *result = resolver.result;
        status = resolver.error == 0 && *result ? SHIRO_OK : SHIRO_E_IO;
        if (status != SHIRO_OK && *result) { freeaddrinfo(*result); *result = NULL; }
        resolver.busy = 0;
    } else resolver.abandoned = 1;
    pthread_mutex_unlock(&resolver_lock);
    return status;
}

shiro_status shiro_socket_connect(shiro_socket *s, const char *host, uint16_t port, int timeout_ms) {
    struct addrinfo hints, *list = NULL, *ai;
    char service[8];
    uint64_t deadline;
    shiro_status last = SHIRO_E_IO;
    if (!s || !host || !*host || !port || timeout_ms <= 0) return SHIRO_E_ARG;
    if (s->fd >= 0) return SHIRO_E_STATE;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    snprintf(service, sizeof(service), "%u", (unsigned)port);
    deadline = shiro_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    last = resolve_until(host, service, &hints, deadline, &list);
    if (last != SHIRO_OK) return last;
    for (ai = list; ai; ai = ai->ai_next) {
        int fd = -1;
        last = connect_one(ai, deadline, &fd);
        if (last == SHIRO_OK) {
            s->fd = fd;
            break;
        }
        if (remaining_ms(deadline) == 0) {
            last = SHIRO_E_TIMEOUT;
            break;
        }
    }
    freeaddrinfo(list);
    return last;
}

shiro_status shiro_socket_adopt(shiro_socket *s, int fd) {
    if (!s || fd < 0) return SHIRO_E_ARG;
    if (s->fd >= 0) return SHIRO_E_STATE;
    s->fd = fd;
    return SHIRO_OK;
}

shiro_status shiro_socket_write_all(shiro_socket *s, const uint8_t *data, size_t len, int timeout_ms) {
    uint64_t deadline;
    if (!s || s->fd < 0 || (len && !data) || timeout_ms <= 0) return SHIRO_E_ARG;
    deadline = shiro_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    while (len) {
        ssize_t n = send(s->fd, data, len, MSG_NOSIGNAL);
        if (n < 0) {
            shiro_status w;
            if (errno == EINTR) continue;
            if (errno != EAGAIN && errno != EWOULDBLOCK) return SHIRO_E_IO;
            w = wait_fd(s->fd, POLLOUT, deadline);
            if (w != SHIRO_OK) return w;
            continue;
        }
        if (n == 0) return SHIRO_E_EOF;
        data += n;
        len -= (size_t)n;
    }
    return SHIRO_OK;
}

shiro_status shiro_socket_read(shiro_socket *s, uint8_t *buf, size_t cap, size_t *got, int timeout_ms) {
    uint64_t deadline;
    if (got) *got = 0;
    if (!s || s->fd < 0 || !buf || cap == 0 || !got || timeout_ms < 0) return SHIRO_E_ARG;
    deadline = shiro_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    for (;;) {
        ssize_t n = recv(s->fd, buf, cap, 0);
        if (n > 0) {
            *got = (size_t)n;
            return SHIRO_OK;
        }
        if (n == 0) return SHIRO_E_EOF;
        if (errno == EINTR) continue;
        if (errno != EAGAIN && errno != EWOULDBLOCK) return SHIRO_E_IO;
        {
            shiro_status w = wait_fd(s->fd, POLLIN, deadline);
            if (w != SHIRO_OK) return w;
        }
    }
}
