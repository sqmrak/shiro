#ifndef SHIRO_HTTP_H
#define SHIRO_HTTP_H

#include <stddef.h>
#include <stdint.h>

#include "shiro_status.h"

/* the one HTTP/1.x response a registration call gets back, read strictly: the reply comes from the network, and a captive portal or a proxy answers with
   something that looks like HTTP and is not what the API said */

#define SHIRO_HTTP_MAX_HEADERS 16384u

typedef struct shiro_http_response {
    int status;             /* 100 to 599 */
    size_t body_len;
} shiro_http_response;

/* data is everything received so far; eof says the connection is closed. On SHIRO_OK the body (decoded from chunks when the reply was chunked) is in body and
   body_len is set. SHIRO_E_TRUNCATED means more bytes are needed (and with eof set, that the reply was cut short), SHIRO_E_MALFORMED for anything that
   is not a well formed answer (a bad status line, a header without a colon, two different lengths, a chunk size that is not hex, a length together with
   chunking, an interim 1xx answer), SHIRO_E_LIMIT when the body would not fit in cap or the headers pass SHIRO_HTTP_MAX_HEADERS */
shiro_status shiro_http_parse_response(const uint8_t *data, size_t len, int eof, shiro_http_response *out, uint8_t *body, size_t cap);

#endif
