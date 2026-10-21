#include "shiro_status.h"

const char *shiro_status_name(shiro_status status) {
    switch (status) {
    case SHIRO_OK: return "ok";
    case SHIRO_E_ARG: return "bad argument";
    case SHIRO_E_MALFORMED: return "malformed input";
    case SHIRO_E_TRUNCATED: return "truncated input";
    case SHIRO_E_UNSUPPORTED: return "unsupported input";
    case SHIRO_E_LIMIT: return "limit exceeded";
    case SHIRO_E_NOMEM: return "out of memory";
    case SHIRO_E_CRYPTO: return "crypto failure";
    case SHIRO_E_SECURITY: return "validation failed";
    case SHIRO_E_STATE: return "wrong state";
    case SHIRO_E_TIMEOUT: return "timeout";
    case SHIRO_E_IO: return "io error";
    case SHIRO_E_EOF: return "end of stream";
    case SHIRO_E_RETRY: return "retry";
    case SHIRO_E_NOTFOUND: return "not found";
    case SHIRO_E_RPC: return "rpc error";
    case SHIRO_E_STORAGE: return "storage error";
    case SHIRO_E_PROXY_AUTH: return "proxy authentication failed";
    case SHIRO_E_PROXY: return "proxy refused connection";
    }
    return "unknown status";
}
