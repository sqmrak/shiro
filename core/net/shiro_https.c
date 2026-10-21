#include "shiro_https.h"

#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <openssl/x509_vfy.h>
#include <openssl/x509v3.h>

#include "shiro_bytes.h"
#include "shiro_clock.h"
#include "shiro_http.h"
#include "shiro_socket.h"

#define SPLIT_PIECE 6u
#define SPLIT_PIECES 23u
#define SPLIT_GAP_MS 12
#define REQUEST_MAX 16384u
#define READ_STEP 4096u

typedef struct io {
    shiro_socket socket;
    SSL *ssl;
    BIO *rbio, *wbio;
    uint64_t deadline;
    int eof;
    int split;
} io;

static int time_left(const io *c) {
    uint64_t now = shiro_system_clock.monotonic_ms(NULL);
    return now >= c->deadline ? 0 : (int)(c->deadline - now > 0x7FFFFFFFu ? 0x7FFFFFFFu : c->deadline - now);
}

static void pause_ms(int ms) {
    (void)poll(NULL, 0, ms);
}

/* every byte OpenSSL has queued for the peer goes out; the very first batch (the hello) may be cut up when asked */
static shiro_status flush(io *c) {
    uint8_t buf[16384];
    for (;;) {
        size_t pending = BIO_ctrl_pending(c->wbio), n, sent = 0;
        int got;
        if (pending == 0) return SHIRO_OK;
        n = pending < sizeof(buf) ? pending : sizeof(buf);
        got = BIO_read(c->wbio, buf, (int)n);
        if (got <= 0) return SHIRO_E_IO;
        n = (size_t)got;
        if (c->split && n > SPLIT_PIECE) {
            size_t piece, pieces = 0;
            c->split = 0;
            while (sent < n) {
                piece = sent + SPLIT_PIECE < n && pieces < SPLIT_PIECES ? SPLIT_PIECE : n - sent;
                if (time_left(c) == 0) return SHIRO_E_TIMEOUT;
                if (shiro_socket_write_all(&c->socket, buf + sent, piece, time_left(c)) != SHIRO_OK) return SHIRO_E_IO;
                sent += piece;
                ++pieces;
                if (sent < n) pause_ms(SPLIT_GAP_MS);
            }
        } else {
            shiro_status s;
            c->split = 0;
            if (time_left(c) == 0) return SHIRO_E_TIMEOUT;
            s = shiro_socket_write_all(&c->socket, buf, n, time_left(c));
            if (s != SHIRO_OK) return s == SHIRO_E_TIMEOUT ? s : SHIRO_E_IO;
        }
    }
}

/* one read from the socket into OpenSSL's input */
static shiro_status fill(io *c) {
    uint8_t buf[READ_STEP];
    size_t got = 0;
    int left = time_left(c);
    shiro_status s;
    if (c->eof) return SHIRO_E_EOF;
    if (left == 0) return SHIRO_E_TIMEOUT;
    s = shiro_socket_read(&c->socket, buf, sizeof(buf), &got, left);
    if (s == SHIRO_E_EOF) {
        c->eof = 1;
        return SHIRO_E_EOF;
    }
    if (s != SHIRO_OK) return s == SHIRO_E_TIMEOUT ? s : SHIRO_E_IO;
    if (BIO_write(c->rbio, buf, (int)got) != (int)got) return SHIRO_E_IO;
    return SHIRO_OK;
}

static int load_roots(SSL_CTX *ctx, const char *pem, size_t len) {
    BIO *bio;
    X509_STORE *store = SSL_CTX_get_cert_store(ctx);
    int added = 0;
    if (!pem || len == 0 || len > 0x7FFFFFFF) return 0;
    bio = BIO_new_mem_buf(pem, (int)len);
    if (!bio) return 0;
    for (;;) {
        X509 *cert = PEM_read_bio_X509(bio, NULL, NULL, NULL);
        if (!cert) break;
        if (X509_STORE_add_cert(store, cert) == 1) ++added;
        X509_free(cert);
    }
    ERR_clear_error();
    BIO_free(bio);
    return added;
}

static int has_line_break(const char *s) {
    return s && (strchr(s, '\r') || strchr(s, '\n'));
}

static shiro_status build_request(const shiro_https_request *r, char *out, size_t cap, size_t *len) {
    size_t n = 0, i;
    int w;
    w = snprintf(out, cap, "POST %s HTTP/1.1\r\nHost: %s\r\n", r->path, r->host);
    if (w < 0 || (size_t)w >= cap) return SHIRO_E_ARG;
    n = (size_t)w;
    for (i = 0; r->headers && r->headers[i]; ++i) {
        if (has_line_break(r->headers[i]) || !strchr(r->headers[i], ':')) return SHIRO_E_ARG;
        w = snprintf(out + n, cap - n, "%s\r\n", r->headers[i]);
        if (w < 0 || (size_t)w >= cap - n) return SHIRO_E_ARG;
        n += (size_t)w;
    }
    w = snprintf(out + n, cap - n, "Content-Length: %zu\r\nConnection: close\r\n\r\n", r->body_len);
    if (w < 0 || (size_t)w >= cap - n) return SHIRO_E_ARG;
    n += (size_t)w;
    *len = n;
    return SHIRO_OK;
}

/* the reply so far, as a response when it is complete; on success the body buffer passes to the response */
static shiro_status take_response(const uint8_t *in, size_t in_len, int eof, uint8_t **body, shiro_https_response *response) {
    shiro_http_response parsed;
    shiro_status status = shiro_http_parse_response(in, in_len, eof, &parsed, *body, SHIRO_HTTPS_MAX_RESPONSE);
    uint8_t *shrunk;
    if (status != SHIRO_OK) return status;
    shrunk = (uint8_t *)realloc(*body, parsed.body_len ? parsed.body_len : 1);
    response->body = shrunk ? shrunk : *body;
    *body = NULL;
    response->status = parsed.status;
    response->body_len = parsed.body_len;
    return SHIRO_OK;
}

static void close_io(io *c) {
    if (c->ssl) SSL_free(c->ssl);   /* frees both BIOs */
    shiro_socket_close(&c->socket);
    c->ssl = NULL;
}

shiro_status shiro_https_post(const shiro_https_request *request, shiro_https_response *response) {
    io c;
    SSL_CTX *ctx = NULL;
    char head[REQUEST_MAX];
    size_t head_len = 0, in_len = 0;
    uint8_t *in = NULL, *body = NULL;
    shiro_status status;
    int rc;
    if (response) memset(response, 0, sizeof(*response));
    if (response) response->stage = "request validation";
    if (!request || !response || !request->host || !request->host[0] || !request->path || request->path[0] != '/' || request->port == 0 ||
        request->timeout_ms <= 0 || (request->body_len && !request->body) || request->body_len > REQUEST_MAX || has_line_break(request->host) ||
        has_line_break(request->path) || strchr(request->host, ' ') || strchr(request->path, ' ')) {
        return SHIRO_E_ARG;
    }
    status = build_request(request, head, sizeof(head), &head_len);
    if (status != SHIRO_OK) return status;
    memset(&c, 0, sizeof(c));
    shiro_socket_init(&c.socket);
    c.deadline = shiro_system_clock.monotonic_ms(NULL) + (uint64_t)request->timeout_ms;
    c.split = request->split_hello;

    ctx = SSL_CTX_new(TLS_client_method());
    if (!ctx) return SHIRO_E_CRYPTO;
    if (SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION) != 1) {
        SSL_CTX_free(ctx);
        return SHIRO_E_CRYPTO;
    }
    SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
    if (load_roots(ctx, request->roots_pem, request->roots_len) == 0) {
        SSL_CTX_free(ctx);
        return SHIRO_E_ARG;
    }
    c.ssl = SSL_new(ctx);
    SSL_CTX_free(ctx);
    if (!c.ssl) return SHIRO_E_CRYPTO;
    c.rbio = BIO_new(BIO_s_mem());
    c.wbio = BIO_new(BIO_s_mem());
    if (!c.rbio || !c.wbio) {
        BIO_free(c.rbio);
        BIO_free(c.wbio);
        SSL_free(c.ssl);
        return SHIRO_E_NOMEM;
    }
    /* the SSL object owns the BIOs from here on */
    SSL_set_bio(c.ssl, c.rbio, c.wbio);
    SSL_set_connect_state(c.ssl);
    SSL_set_hostflags(c.ssl, X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS);
    if (SSL_set1_host(c.ssl, request->host) != 1 || SSL_set_tlsext_host_name(c.ssl, request->host) != 1) {
        close_io(&c);
        return SHIRO_E_CRYPTO;
    }

    response->stage = request->proxy ? "proxy connection" : "direct connection";
    if (request->proxy)
        status = shiro_proxy_connect(&c.socket, request->proxy, request->host, request->port, time_left(&c) ? time_left(&c) : 1);
    else
        status = shiro_socket_connect(&c.socket, request->connect_ip ? request->connect_ip : request->host, request->port, time_left(&c) ? time_left(&c) : 1);
    if (status != SHIRO_OK) {
        close_io(&c);
        return status;
    }

    response->stage = "TLS handshake";
    for (;;) {
        int err;
        ERR_clear_error();
        rc = SSL_do_handshake(c.ssl);
        status = flush(&c);
        if (status != SHIRO_OK) goto fail;
        if (rc == 1) break;
        err = SSL_get_error(c.ssl, rc);
        if (err == SSL_ERROR_WANT_READ) {
            status = fill(&c);
            if (status == SHIRO_E_EOF) status = SHIRO_E_IO;
            if (status != SHIRO_OK) goto fail;
        } else if (err != SSL_ERROR_WANT_WRITE) {
            /* a certificate or a name that does not check out is a security failure and is told apart from a network one */
            long verify = SSL_get_verify_result(c.ssl);
            unsigned long e = ERR_peek_last_error();
            status = (verify != X509_V_OK || ERR_GET_LIB(e) == ERR_LIB_X509 || ERR_GET_REASON(e) == SSL_R_UNSUPPORTED_PROTOCOL ||
                      ERR_GET_REASON(e) == SSL_R_TLSV1_ALERT_PROTOCOL_VERSION || ERR_GET_REASON(e) == SSL_R_WRONG_SSL_VERSION)
                         ? SHIRO_E_SECURITY
                         : SHIRO_E_IO;
            goto fail;
        }
    }
    if (SSL_get_verify_result(c.ssl) != X509_V_OK) {
        status = SHIRO_E_SECURITY;
        goto fail;
    }

    response->stage = "HTTPS request";
    /* the request, header and body in one write */
    {
        size_t total = head_len + request->body_len, sent = 0;
        uint8_t *all = (uint8_t *)malloc(total);
        if (!all) {
            status = SHIRO_E_NOMEM;
            goto fail;
        }
        memcpy(all, head, head_len);
        if (request->body_len) memcpy(all + head_len, request->body, request->body_len);
        while (sent < total) {
            int w;
            ERR_clear_error();
            w = SSL_write(c.ssl, all + sent, (int)(total - sent));
            if (w > 0) {
                sent += (size_t)w;
                status = flush(&c);
                if (status != SHIRO_OK) {
                    shiro_wipe(all, total);
                    free(all);
                    goto fail;
                }
                continue;
            }
            if (SSL_get_error(c.ssl, w) != SSL_ERROR_WANT_WRITE && SSL_get_error(c.ssl, w) != SSL_ERROR_WANT_READ) {
                shiro_wipe(all, total);
                free(all);
                status = SHIRO_E_IO;
                goto fail;
            }
            status = flush(&c);
            if (status != SHIRO_OK) {
                shiro_wipe(all, total);
                free(all);
                goto fail;
            }
            if (SSL_get_error(c.ssl, w) == SSL_ERROR_WANT_READ && (status = fill(&c)) != SHIRO_OK) {
                shiro_wipe(all, total);
                free(all);
                goto fail;
            }
        }
        shiro_wipe(all, total);
        free(all);
    }

    response->stage = "HTTPS response";
    in = (uint8_t *)malloc(SHIRO_HTTPS_MAX_RESPONSE);
    body = (uint8_t *)malloc(SHIRO_HTTPS_MAX_RESPONSE);
    if (!in || !body) {
        status = SHIRO_E_NOMEM;
        goto fail;
    }
    for (;;) {
        int got, err;
        ERR_clear_error();
        got = SSL_read(c.ssl, in + in_len, (int)(SHIRO_HTTPS_MAX_RESPONSE - in_len));
        if (got > 0) {
            in_len += (size_t)got;
            status = take_response(in, in_len, 0, &body, response);
            if (status == SHIRO_OK) goto done;
            if (status != SHIRO_E_TRUNCATED) goto fail;
            if (in_len >= SHIRO_HTTPS_MAX_RESPONSE) {
                status = SHIRO_E_LIMIT;
                goto fail;
            }
            continue;
        }
        err = SSL_get_error(c.ssl, got);
        if (err == SSL_ERROR_WANT_READ) {
            status = fill(&c);
            if (status == SHIRO_OK) continue;
            if (status != SHIRO_E_EOF) goto fail;
        } else if (err != SSL_ERROR_ZERO_RETURN) {
            status = SHIRO_E_IO;
            goto fail;
        }
        /* the server closed, which ends a reply that has no length of its own; one that had a length and was cut short stays incomplete */
        status = take_response(in, in_len, 1, &body, response);
        if (status == SHIRO_E_TRUNCATED) status = SHIRO_E_IO;
        if (status == SHIRO_OK) goto done;
        goto fail;
    }
fail:
    if (response->body) {
        free(response->body);
        response->body = NULL;
    }
done:
    if (status == SHIRO_OK) response->stage = "complete";
    if (in) {
        shiro_wipe(in, in_len);
        free(in);
    }
    free(body);
    close_io(&c);
    return status;
}

void shiro_https_response_free(shiro_https_response *response) {
    if (!response) return;
    if (response->body) {
        shiro_wipe(response->body, response->body_len);
        free(response->body);
    }
    memset(response, 0, sizeof(*response));
}
