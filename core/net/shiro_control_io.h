#ifndef SHIRO_CONTROL_IO_H
#define SHIRO_CONTROL_IO_H
#include <stddef.h>
#include <stdint.h>
#include "shiro_status.h"
#define SHIRO_CONTROL_MAX 65536u
shiro_status shiro_control_read(int fd, uint8_t *buffer, size_t cap, size_t *length, int timeout_ms);
shiro_status shiro_control_write(int fd, const uint8_t *buffer, size_t length, int timeout_ms);
#endif
