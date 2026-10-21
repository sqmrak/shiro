#ifndef SHIRO_HTTPS_H
#define SHIRO_HTTPS_H

#include <stddef.h>
#include <stdint.h>

#include "shiro_status.h"
#include "shiro_proxy.h"

/* one HTTPS POST for the account call of WARP, over TLS 1.2 or newer with the chain and the host name checked. The trust is exactly the roots that the
   request carries: the system stores of old iOS releases lack today's roots, and a client that falls back to accepting any certificate would be a way in for
   whoever sits on the path. There is no switch that turns the check off */

#define SHIRO_HTTPS_MAX_RESPONSE (256u * 1024u)

typedef struct shiro_https_request {
    const char *host;                   /* the name asked for in the SNI and required in the certificate */
    const char *connect_ip;             /* a dotted IPv4 address to dial instead of resolving host, or NULL */
    uint16_t port;
    const char *path;                   /* starts with / */
    const char *const *headers;         /* "Name: value" lines ending with NULL, or NULL; Host, Content-Length and Connection are added by the call */
    const uint8_t *body;
    size_t body_len;
    const char *roots_pem;              /* the trusted roots, PEM, at least one */
    size_t roots_len;
    int split_hello;                    /* write the first bytes of the TLS hello in small pieces with a short pause, for a network that reads the SNI of one segment */
    int timeout_ms;                     /* the whole call */
    const shiro_proxy *proxy;           /* NULL for direct access; TLS still authenticates host */
} shiro_https_request;

typedef struct shiro_https_response {
    int status;
    uint8_t *body;                      /* owned, free with shiro_https_response_free */
    size_t body_len;
    const char *stage;      /* static name of the current or failed transport stage */
} shiro_https_response;

/* SHIRO_E_ARG for a request that is not well formed (a header with a line break, no roots, no host), SHIRO_E_SECURITY when the certificate chain, the name
   or the protocol version is not acceptable, SHIRO_E_TIMEOUT, SHIRO_E_IO for connect and transport failures, SHIRO_E_MALFORMED for an answer that is not
   HTTP, SHIRO_E_LIMIT for one that is too large. Any status of the server (also 4xx and 5xx) is SHIRO_OK with the status filled in */
shiro_status shiro_https_post(const shiro_https_request *request, shiro_https_response *response);
void shiro_https_response_free(shiro_https_response *response);

#endif
