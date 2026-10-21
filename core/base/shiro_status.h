#ifndef SHIRO_STATUS_H
#define SHIRO_STATUS_H

typedef enum shiro_status {
    SHIRO_OK = 0,
    SHIRO_E_ARG = -1,
    SHIRO_E_MALFORMED = -2,
    SHIRO_E_TRUNCATED = -3,   /* incomplete frames can resume, malformed frames cannot */
    SHIRO_E_UNSUPPORTED = -4,
    SHIRO_E_LIMIT = -5,
    SHIRO_E_NOMEM = -6,
    SHIRO_E_CRYPTO = -7,
    SHIRO_E_SECURITY = -8,
    SHIRO_E_STATE = -9,
    SHIRO_E_TIMEOUT = -10,
    SHIRO_E_IO = -11,
    SHIRO_E_EOF = -12,
    SHIRO_E_RETRY = -13,
    SHIRO_E_NOTFOUND = -14,
    SHIRO_E_RPC = -15,
    SHIRO_E_STORAGE = -16,
    SHIRO_E_PROXY_AUTH = -17,
    SHIRO_E_PROXY = -18
} shiro_status;

const char *shiro_status_name(shiro_status status);

#endif
