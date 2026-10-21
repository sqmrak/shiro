#ifndef SHIRO_SOCKET_H
#define SHIRO_SOCKET_H

#include <stddef.h>
#include <stdint.h>

#include "shiro_status.h"

typedef struct shiro_socket {
    int fd;
} shiro_socket;

void shiro_socket_init(shiro_socket *s);
shiro_status shiro_socket_connect(shiro_socket *s, const char *host, uint16_t port, int timeout_ms);
/* takes over a connected non blocking stream socket that another part of the program opened, such as a stream of the tunnel. SHIRO_E_STATE when the
   socket already holds a descriptor, and then fd stays with the caller */
shiro_status shiro_socket_adopt(shiro_socket *s, int fd);
shiro_status shiro_socket_write_all(shiro_socket *s, const uint8_t *data, size_t len, int timeout_ms);
shiro_status shiro_socket_read(shiro_socket *s, uint8_t *buf, size_t cap, size_t *got, int timeout_ms);
void shiro_socket_close(shiro_socket *s);

#endif
