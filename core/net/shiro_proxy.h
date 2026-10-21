#ifndef SHIRO_PROXY_H
#define SHIRO_PROXY_H

#include "shiro_socket.h"

#define SHIRO_PROXY_URL_MAX 2048u

typedef enum shiro_proxy_type {
    SHIRO_PROXY_NONE = 0,
    SHIRO_PROXY_SOCKS5,
    SHIRO_PROXY_HTTP
} shiro_proxy_type;

typedef struct shiro_proxy {
    shiro_proxy_type type;
    char host[254];
    uint16_t port;
    char username[256];
    char password[256];
} shiro_proxy;

/* an empty URL disables the proxy; credentials accept percent escapes */
shiro_status shiro_proxy_parse(const char *url, size_t len, shiro_proxy *out);
/* the proxy resolves host; the socket stays open only on success */
shiro_status shiro_proxy_connect(shiro_socket *socket, const shiro_proxy *proxy, const char *host, uint16_t port, int timeout_ms);

#endif
