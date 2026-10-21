#ifndef SHIRO_LOG_H
#define SHIRO_LOG_H

#include <stddef.h>
#include "shiro_status.h"

/* one bounded current file and one rotated file, both private to their owner */
shiro_status shiro_log_append(const char *path, const void *line, size_t len, size_t limit);

#endif
