#include "shiro_log.h"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

static pthread_mutex_t log_lock = PTHREAD_MUTEX_INITIALIZER;

shiro_status shiro_log_append(const char *path, const void *line, size_t len, size_t limit) {
    char previous[1024];
    int fd, n;
    size_t used = 0;
    struct stat info;
    shiro_status status = SHIRO_E_STORAGE;
    if (!path || !line || !limit || len > limit) return SHIRO_E_ARG;
    n = snprintf(previous, sizeof(previous), "%s.1", path);
    if (n < 0 || (size_t)n >= sizeof(previous)) return SHIRO_E_LIMIT;
    if (!len) return SHIRO_OK;
    pthread_mutex_lock(&log_lock);
    fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_NONBLOCK, 0600);
    if (fd < 0) goto done;
    if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || fchmod(fd, 0600) != 0) goto close_file;
    if (info.st_size < 0 || (uintmax_t)info.st_size > limit - len) {
        if (close(fd) != 0) goto done;
        if (rename(path, previous) != 0) goto done;
        fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
        if (fd < 0) goto done;
    }
    while (used < len) {
        ssize_t count = write(fd, (const char *)line + used, len - used);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) goto close_file;
        used += (size_t)count;
    }
    status = SHIRO_OK;
close_file:
    if (close(fd) != 0) status = SHIRO_E_STORAGE;
done:
    pthread_mutex_unlock(&log_lock);
    return status;
}
