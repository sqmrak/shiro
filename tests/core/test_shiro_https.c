#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>

#include "shiro_https.h"
#include "test_util.h"

/* a TLS server on the loopback with certificates made here, so that every way a certificate can be wrong is a real handshake against the real client */

typedef enum behavior {
    BEHAVE_ANSWER,        /* reads the request and sends reply */
    BEHAVE_CLOSE,         /* closes the socket straight after accept */
    BEHAVE_GARBAGE,       /* completes the handshake and sends something that is not HTTP */
    BEHAVE_SILENT         /* completes the handshake and says nothing */
} behavior;

typedef struct server {
    int listen_fd;
    uint16_t port;
    pthread_t thread;
    X509 *cert;
    EVP_PKEY *key;
    int max_version;
    behavior behave;
    const uint8_t *reply;
    size_t reply_len;
    char request[4096];
    size_t request_len;
    size_t first_peek;
    int handshake_ok;
    shiro_proxy_type proxy_type;
    int proxy_matched;
    char sni[254];
} server;

static int proxy_read(int fd, uint8_t *buf, size_t len) {
    while (len) {
        ssize_t n = recv(fd, buf, len, 0);
        if (n <= 0) return 0;
        buf += n;
        len -= (size_t)n;
    }
    return 1;
}

static int proxy_negotiate(server *s, int fd) {
    uint8_t buf[1024];
    if (s->proxy_type == SHIRO_PROXY_HTTP) {
        static const char request[] = "CONNECT api.test.invalid:443 HTTP/1.1\r\nHost: api.test.invalid:443\r\nProxy-Authorization: Basic dXNlcjpwYXNz\r\n\r\n";
        static const char response[] = "HTTP/1.1 200 Connected\r\n\r\n";
        if (!proxy_read(fd, buf, sizeof(request) - 1) || memcmp(buf, request, sizeof(request) - 1) != 0) return 0;
        if (send(fd, response, sizeof(response) - 1, MSG_NOSIGNAL) != (ssize_t)(sizeof(response) - 1)) return 0;
    } else {
        static const uint8_t hello[] = {5,1,2}, method[] = {5,2}, auth_ok[] = {1,0};
        static const uint8_t auth[] = {1,4,'u','s','e','r',4,'p','a','s','s'};
        static const uint8_t connect[] = {5,1,0,3,16,'a','p','i','.','t','e','s','t','.','i','n','v','a','l','i','d',1,187};
        static const uint8_t response[] = {5,0,0,1,127,0,0,1,0,80};
        if (!proxy_read(fd, buf, sizeof(hello)) || memcmp(buf, hello, sizeof(hello)) != 0) return 0;
        if (send(fd, method, sizeof(method), MSG_NOSIGNAL) != (ssize_t)sizeof(method)) return 0;
        if (!proxy_read(fd, buf, sizeof(auth)) || memcmp(buf, auth, sizeof(auth)) != 0) return 0;
        if (send(fd, auth_ok, sizeof(auth_ok), MSG_NOSIGNAL) != (ssize_t)sizeof(auth_ok)) return 0;
        if (!proxy_read(fd, buf, sizeof(connect)) || memcmp(buf, connect, sizeof(connect)) != 0) return 0;
        if (send(fd, response, sizeof(response), MSG_NOSIGNAL) != (ssize_t)sizeof(response)) return 0;
    }
    return 1;
}

static EVP_PKEY *make_key(void) {
    return EVP_EC_gen("P-256");
}

static X509 *make_cert(EVP_PKEY *subject_key, const char *cn, const char *san, X509 *issuer, EVP_PKEY *issuer_key, int is_ca, long from_sec, long to_sec,
                       long serial) {
    X509 *cert = X509_new();
    X509_NAME *name = X509_NAME_new();
    X509V3_CTX ctx;
    X509_EXTENSION *ext;
    X509_set_version(cert, 2);
    ASN1_INTEGER_set(X509_get_serialNumber(cert), serial);
    X509_gmtime_adj(X509_getm_notBefore(cert), from_sec);
    X509_gmtime_adj(X509_getm_notAfter(cert), to_sec);
    X509_set_pubkey(cert, subject_key);
    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, (const unsigned char *)cn, -1, -1, 0);
    X509_set_subject_name(cert, name);
    X509_set_issuer_name(cert, issuer ? X509_get_subject_name(issuer) : name);
    X509_NAME_free(name);
    X509V3_set_ctx_nodb(&ctx);
    X509V3_set_ctx(&ctx, issuer ? issuer : cert, cert, NULL, NULL, 0);
    ext = X509V3_EXT_conf_nid(NULL, &ctx, NID_basic_constraints, is_ca ? "critical,CA:TRUE" : "critical,CA:FALSE");
    X509_add_ext(cert, ext, -1);
    X509_EXTENSION_free(ext);
    if (is_ca) {
        ext = X509V3_EXT_conf_nid(NULL, &ctx, NID_key_usage, "critical,keyCertSign,cRLSign");
        X509_add_ext(cert, ext, -1);
        X509_EXTENSION_free(ext);
    }
    if (san) {
        ext = X509V3_EXT_conf_nid(NULL, &ctx, NID_subject_alt_name, san);
        X509_add_ext(cert, ext, -1);
        X509_EXTENSION_free(ext);
    }
    X509_sign(cert, issuer_key ? issuer_key : subject_key, EVP_sha256());
    return cert;
}

static char *pem_of(X509 *cert, size_t *len) {
    BIO *bio = BIO_new(BIO_s_mem());
    char *data, *copy;
    long n;
    PEM_write_bio_X509(bio, cert);
    n = BIO_get_mem_data(bio, &data);
    copy = (char *)malloc((size_t)n + 1);
    memcpy(copy, data, (size_t)n);
    copy[n] = 0;
    *len = (size_t)n;
    BIO_free(bio);
    return copy;
}

static void *serve(void *arg) {
    server *s = (server *)arg;
    struct sockaddr_in peer;
    socklen_t plen = sizeof(peer);
    int fd = accept(s->listen_fd, (struct sockaddr *)&peer, &plen);
    SSL_CTX *ctx;
    SSL *ssl;
    if (fd < 0) return NULL;
    if (s->behave == BEHAVE_CLOSE) {
        close(fd);
        return NULL;
    }
    if (s->proxy_type != SHIRO_PROXY_NONE) {
        struct timeval timeout = {3, 0};
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        s->proxy_matched = proxy_negotiate(s, fd);
        if (!s->proxy_matched) { close(fd); return NULL; }
    }
    {
        struct pollfd p = {fd, POLLIN, 0};
        uint8_t peek[4096];
        ssize_t n;
        if (poll(&p, 1, 5000) > 0) {
            n = recv(fd, peek, sizeof(peek), MSG_PEEK);
            s->first_peek = n > 0 ? (size_t)n : 0;
        }
    }
    ctx = SSL_CTX_new(TLS_server_method());
    SSL_CTX_set_security_level(ctx, 0);
    SSL_CTX_set_min_proto_version(ctx, TLS1_VERSION);
    SSL_CTX_set_max_proto_version(ctx, s->max_version);
    SSL_CTX_use_certificate(ctx, s->cert);
    SSL_CTX_use_PrivateKey(ctx, s->key);
    ssl = SSL_new(ctx);
    SSL_set_fd(ssl, fd);
    if (SSL_accept(ssl) == 1) {
        const char *name = SSL_get_servername(ssl, TLSEXT_NAMETYPE_host_name);
        if (name) snprintf(s->sni, sizeof(s->sni), "%s", name);
        /* whatever the server does next, the request is read first: a socket closed on unread data answers with a reset that eats the reply */
        size_t n = 0, header_end = 0, want = 0;
        s->handshake_ok = 1;
        for (;;) {
            int got = SSL_read(ssl, s->request + n, (int)(sizeof(s->request) - 1 - n));
            char *e, *cl;
            if (got <= 0) break;
            n += (size_t)got;
            s->request[n] = 0;
            e = strstr(s->request, "\r\n\r\n");
            if (e && !header_end) {
                header_end = (size_t)(e - s->request) + 4;
                cl = strstr(s->request, "Content-Length: ");
                want = header_end + (cl ? (size_t)atoi(cl + 16) : 0);
            }
            if (header_end && n >= want) break;
        }
        s->request_len = n;
        if (s->behave == BEHAVE_ANSWER) {
            size_t sent = 0;
            while (sent < s->reply_len) {
                size_t part = s->reply_len - sent < 16000 ? s->reply_len - sent : 16000;
                int w = SSL_write(ssl, s->reply + sent, (int)part);
                if (w <= 0) break;
                sent += (size_t)w;
            }
            SSL_shutdown(ssl);
        } else if (s->behave == BEHAVE_GARBAGE) {
            SSL_write(ssl, "SSH-2.0-not-http\r\n", 18);
            SSL_shutdown(ssl);
        } else {
            struct pollfd p = {fd, POLLIN, 0};
            (void)poll(&p, 1, 1500);
        }
    }
    SSL_free(ssl);
    SSL_CTX_free(ctx);
    close(fd);
    return NULL;
}

static void server_start(server *s, X509 *cert, EVP_PKEY *key, behavior behave, const uint8_t *reply, size_t reply_len) {
    struct sockaddr_in a;
    socklen_t len = sizeof(a);
    int one = 1;
    memset(s, 0, sizeof(*s));
    s->cert = cert;
    s->key = key;
    s->behave = behave;
    s->reply = reply;
    s->reply_len = reply_len;
    s->max_version = TLS1_3_VERSION;
    s->listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(s->listen_fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(s->listen_fd, (struct sockaddr *)&a, sizeof(a));
    listen(s->listen_fd, 4);
    getsockname(s->listen_fd, (struct sockaddr *)&a, &len);
    s->port = ntohs(a.sin_port);
}

static void server_run(server *s) {
    pthread_create(&s->thread, NULL, serve, s);
}

static void server_stop(server *s) {
    pthread_join(s->thread, NULL);
    close(s->listen_fd);
}

typedef struct pki {
    EVP_PKEY *ca_key, *leaf_key, *other_ca_key;
    X509 *ca, *leaf, *wrong_name, *expired, *foreign, *self_signed, *other_ca;
    char *roots;
    size_t roots_len;
    char *other_roots;
    size_t other_roots_len;
} pki;

static void pki_make(pki *p) {
    X509 *other_leaf;
    memset(p, 0, sizeof(*p));
    p->ca_key = make_key();
    p->leaf_key = make_key();
    p->other_ca_key = make_key();
    p->ca = make_cert(p->ca_key, "Test Root", NULL, NULL, p->ca_key, 1, -3600, 86400L * 365, 1);
    p->other_ca = make_cert(p->other_ca_key, "Other Root", NULL, NULL, p->other_ca_key, 1, -3600, 86400L * 365, 2);
    p->leaf = make_cert(p->leaf_key, "api.test.invalid", "DNS:api.test.invalid", p->ca, p->ca_key, 0, -3600, 86400L * 30, 10);
    p->wrong_name = make_cert(p->leaf_key, "other.test.invalid", "DNS:other.test.invalid", p->ca, p->ca_key, 0, -3600, 86400L * 30, 11);
    p->expired = make_cert(p->leaf_key, "api.test.invalid", "DNS:api.test.invalid", p->ca, p->ca_key, 0, -86400L * 30, -86400L, 12);
    p->foreign = make_cert(p->leaf_key, "api.test.invalid", "DNS:api.test.invalid", p->other_ca, p->other_ca_key, 0, -3600, 86400L * 30, 13);
    p->self_signed = make_cert(p->leaf_key, "api.test.invalid", "DNS:api.test.invalid", NULL, p->leaf_key, 0, -3600, 86400L * 30, 14);
    (void)other_leaf;
    p->roots = pem_of(p->ca, &p->roots_len);
    p->other_roots = pem_of(p->other_ca, &p->other_roots_len);
}

static void pki_free(pki *p) {
    X509_free(p->ca);
    X509_free(p->leaf);
    X509_free(p->wrong_name);
    X509_free(p->expired);
    X509_free(p->foreign);
    X509_free(p->self_signed);
    X509_free(p->other_ca);
    EVP_PKEY_free(p->ca_key);
    EVP_PKEY_free(p->leaf_key);
    EVP_PKEY_free(p->other_ca_key);
    free(p->roots);
    free(p->other_roots);
}

static shiro_status post(const pki *p, server *s, const char *host, int split, int timeout, shiro_https_response *response, const char *roots,
                           size_t roots_len) {
    static const char *const headers[] = {"Content-Type: application/json; charset=UTF-8", "User-Agent: test/1", NULL};
    shiro_https_request r;
    shiro_proxy proxy;
    memset(&r, 0, sizeof(r));
    r.host = host;
    r.connect_ip = "127.0.0.1";
    r.port = s->port;
    r.path = "/v0a4471/reg";
    r.headers = headers;
    r.body = (const uint8_t *)"{\"a\":1}";
    r.body_len = 7;
    r.roots_pem = roots ? roots : p->roots;
    r.roots_len = roots ? roots_len : p->roots_len;
    r.split_hello = split;
    r.timeout_ms = timeout;
    if (s->proxy_type != SHIRO_PROXY_NONE) {
        memset(&proxy, 0, sizeof(proxy));
        proxy.type = s->proxy_type;
        snprintf(proxy.host, sizeof(proxy.host), "127.0.0.1");
        snprintf(proxy.username, sizeof(proxy.username), "user");
        snprintf(proxy.password, sizeof(proxy.password), "pass");
        proxy.port = s->port;
        r.proxy = &proxy;
        r.port = 443;
        r.connect_ip = "192.0.2.1";
    }
    return shiro_https_post(&r, response);
}

static const char ok_reply[] = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 11\r\n\r\n{\"ok\":true}";

static void a_good_exchange(pki *p) {
    server s;
    shiro_https_response r;
    server_start(&s, p->leaf, p->leaf_key, BEHAVE_ANSWER, (const uint8_t *)ok_reply, strlen(ok_reply));
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 5000, &r, NULL, 0), SHIRO_OK);
    server_stop(&s);
    CHECK_EQ_INT(r.status, 200);
    CHECK_EQ_INT(r.body_len, 11);
    CHECK_MEM(r.body, "{\"ok\":true}", 11);
    CHECK(strstr(s.request, "POST /v0a4471/reg HTTP/1.1\r\n") == s.request);
    CHECK(strstr(s.request, "\r\nHost: api.test.invalid\r\n") != NULL);
    CHECK(strstr(s.request, "\r\nContent-Type: application/json; charset=UTF-8\r\n") != NULL);
    CHECK(strstr(s.request, "\r\nContent-Length: 7\r\n") != NULL);
    CHECK(strstr(s.request, "\r\nConnection: close\r\n") != NULL);
    CHECK(strstr(s.request, "\r\n\r\n{\"a\":1}") != NULL);
    CHECK(s.first_peek > 100);
    shiro_https_response_free(&r);
    CHECK(r.body == NULL);
}

static void statuses_and_framing(pki *p) {
    static const char not_found[] = "HTTP/1.1 404 Not Found\r\nContent-Length: 3\r\n\r\nnop";
    static const char chunked[] = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nwiki\r\n5\r\npedia\r\n0\r\n\r\n";
    static const char to_close[] = "HTTP/1.0 200 OK\r\n\r\nuntil the close";
    static const char cut[] = "HTTP/1.1 200 OK\r\nContent-Length: 50\r\n\r\nshort";
    server s;
    shiro_https_response r;
    server_start(&s, p->leaf, p->leaf_key, BEHAVE_ANSWER, (const uint8_t *)not_found, strlen(not_found));
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 5000, &r, NULL, 0), SHIRO_OK);
    server_stop(&s);
    CHECK_EQ_INT(r.status, 404);
    CHECK_EQ_INT(r.body_len, 3);
    shiro_https_response_free(&r);

    server_start(&s, p->leaf, p->leaf_key, BEHAVE_ANSWER, (const uint8_t *)chunked, strlen(chunked));
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 5000, &r, NULL, 0), SHIRO_OK);
    server_stop(&s);
    CHECK_EQ_INT(r.body_len, 9);
    CHECK_MEM(r.body, "wikipedia", 9);
    shiro_https_response_free(&r);

    server_start(&s, p->leaf, p->leaf_key, BEHAVE_ANSWER, (const uint8_t *)to_close, strlen(to_close));
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 5000, &r, NULL, 0), SHIRO_OK);
    server_stop(&s);
    CHECK_EQ_INT(r.body_len, strlen("until the close"));
    shiro_https_response_free(&r);

    server_start(&s, p->leaf, p->leaf_key, BEHAVE_ANSWER, (const uint8_t *)cut, strlen(cut));
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 5000, &r, NULL, 0), SHIRO_E_IO);
    server_stop(&s);
    CHECK(r.body == NULL);
}

static void certificates_that_must_be_refused(pki *p) {
    server s;
    shiro_https_response r;
    /* the right certificate asked for under another name */
    server_start(&s, p->leaf, p->leaf_key, BEHAVE_ANSWER, (const uint8_t *)ok_reply, strlen(ok_reply));
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "evil.test.invalid", 0, 5000, &r, NULL, 0), SHIRO_E_SECURITY);
    server_stop(&s);
    CHECK(r.body == NULL);
    CHECK_EQ_INT(s.request_len, 0);
    /* a certificate made for another name */
    server_start(&s, p->wrong_name, p->leaf_key, BEHAVE_ANSWER, (const uint8_t *)ok_reply, strlen(ok_reply));
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 5000, &r, NULL, 0), SHIRO_E_SECURITY);
    server_stop(&s);
    CHECK_EQ_INT(s.request_len, 0);
    /* expired */
    server_start(&s, p->expired, p->leaf_key, BEHAVE_ANSWER, (const uint8_t *)ok_reply, strlen(ok_reply));
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 5000, &r, NULL, 0), SHIRO_E_SECURITY);
    server_stop(&s);
    CHECK_EQ_INT(s.request_len, 0);
    /* signed by a root the request does not trust */
    server_start(&s, p->foreign, p->leaf_key, BEHAVE_ANSWER, (const uint8_t *)ok_reply, strlen(ok_reply));
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 5000, &r, NULL, 0), SHIRO_E_SECURITY);
    server_stop(&s);
    CHECK_EQ_INT(s.request_len, 0);
    /* the good certificate, but only the other root is trusted */
    server_start(&s, p->leaf, p->leaf_key, BEHAVE_ANSWER, (const uint8_t *)ok_reply, strlen(ok_reply));
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 5000, &r, p->other_roots, p->other_roots_len), SHIRO_E_SECURITY);
    server_stop(&s);
    CHECK_EQ_INT(s.request_len, 0);
    /* a certificate that vouches for itself */
    server_start(&s, p->self_signed, p->leaf_key, BEHAVE_ANSWER, (const uint8_t *)ok_reply, strlen(ok_reply));
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 5000, &r, NULL, 0), SHIRO_E_SECURITY);
    server_stop(&s);
    CHECK_EQ_INT(s.request_len, 0);
    /* a server that only speaks TLS 1.1 */
    server_start(&s, p->leaf, p->leaf_key, BEHAVE_ANSWER, (const uint8_t *)ok_reply, strlen(ok_reply));
    s.max_version = TLS1_1_VERSION;
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 5000, &r, NULL, 0), SHIRO_E_SECURITY);
    server_stop(&s);
    CHECK_EQ_INT(s.request_len, 0);
    /* TLS 1.2 is enough */
    server_start(&s, p->leaf, p->leaf_key, BEHAVE_ANSWER, (const uint8_t *)ok_reply, strlen(ok_reply));
    s.max_version = TLS1_2_VERSION;
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 5000, &r, NULL, 0), SHIRO_OK);
    server_stop(&s);
    shiro_https_response_free(&r);
}

static void broken_servers(pki *p) {
    static const char huge_head[] = "HTTP/1.1 200 OK\r\nContent-Length: 300000\r\n\r\n";
    server s;
    shiro_https_response r;
    uint8_t *huge;
    size_t head = strlen(huge_head);
    server_start(&s, p->leaf, p->leaf_key, BEHAVE_CLOSE, NULL, 0);
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 5000, &r, NULL, 0), SHIRO_E_IO);
    server_stop(&s);
    server_start(&s, p->leaf, p->leaf_key, BEHAVE_GARBAGE, NULL, 0);
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 5000, &r, NULL, 0), SHIRO_E_MALFORMED);
    server_stop(&s);
    server_start(&s, p->leaf, p->leaf_key, BEHAVE_SILENT, NULL, 0);
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 400, &r, NULL, 0), SHIRO_E_TIMEOUT);
    server_stop(&s);
    huge = (uint8_t *)malloc(head + 300000);
    memcpy(huge, huge_head, head);
    memset(huge + head, 'x', 300000);
    server_start(&s, p->leaf, p->leaf_key, BEHAVE_ANSWER, huge, head + 300000);
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 5000, &r, NULL, 0), SHIRO_E_LIMIT);
    server_stop(&s);
    free(huge);
    /* nothing listens there */
    {
        shiro_https_request q;
        memset(&q, 0, sizeof(q));
        q.host = "api.test.invalid";
        q.connect_ip = "127.0.0.1";
        q.port = 1;
        q.path = "/x";
        q.roots_pem = p->roots;
        q.roots_len = p->roots_len;
        q.timeout_ms = 2000;
        CHECK_EQ_INT(shiro_https_post(&q, &r), SHIRO_E_IO);
    }
}

static void split_hello(pki *p) {
    server s;
    shiro_https_response r;
    server_start(&s, p->leaf, p->leaf_key, BEHAVE_ANSWER, (const uint8_t *)ok_reply, strlen(ok_reply));
    server_run(&s);
    CHECK_EQ_INT(post(p, &s, "api.test.invalid", 1, 5000, &r, NULL, 0), SHIRO_OK);
    server_stop(&s);
    CHECK_EQ_INT(r.status, 200);
    /* the first thing that reached the server was a piece of a few bytes, not the whole hello */
    CHECK(s.first_peek > 0 && s.first_peek <= 24);
    shiro_https_response_free(&r);
}

static void bad_requests(pki *p) {
    shiro_https_request q;
    shiro_https_response r;
    static const char *const bad_header[] = {"X: a\r\nInjected: 1", NULL};
    static const char *const no_colon[] = {"nonsense", NULL};
    memset(&q, 0, sizeof(q));
    q.host = "api.test.invalid";
    q.port = 443;
    q.path = "/x";
    q.roots_pem = p->roots;
    q.roots_len = p->roots_len;
    q.timeout_ms = 1000;
    q.headers = bad_header;
    CHECK_EQ_INT(shiro_https_post(&q, &r), SHIRO_E_ARG);
    q.headers = no_colon;
    CHECK_EQ_INT(shiro_https_post(&q, &r), SHIRO_E_ARG);
    q.headers = NULL;
    q.roots_pem = NULL;
    q.roots_len = 0;
    CHECK_EQ_INT(shiro_https_post(&q, &r), SHIRO_E_ARG);
    q.roots_pem = "not a certificate";
    q.roots_len = 17;
    CHECK_EQ_INT(shiro_https_post(&q, &r), SHIRO_E_ARG);
    q.roots_pem = p->roots;
    q.roots_len = p->roots_len;
    q.host = "";
    CHECK_EQ_INT(shiro_https_post(&q, &r), SHIRO_E_ARG);
    q.host = "a b";
    CHECK_EQ_INT(shiro_https_post(&q, &r), SHIRO_E_ARG);
    q.host = "api.test.invalid";
    q.path = "x";
    CHECK_EQ_INT(shiro_https_post(&q, &r), SHIRO_E_ARG);
    q.path = "/x\r\nHost: evil";
    CHECK_EQ_INT(shiro_https_post(&q, &r), SHIRO_E_ARG);
    q.path = "/x";
    q.port = 0;
    CHECK_EQ_INT(shiro_https_post(&q, &r), SHIRO_E_ARG);
    q.port = 443;
    q.timeout_ms = 0;
    CHECK_EQ_INT(shiro_https_post(&q, &r), SHIRO_E_ARG);
    CHECK_EQ_INT(shiro_https_post(NULL, &r), SHIRO_E_ARG);
    shiro_https_response_free(NULL);
}

static void proxied_tls(pki *p) {
    for (int kind = SHIRO_PROXY_SOCKS5; kind <= SHIRO_PROXY_HTTP; ++kind) {
        X509 *certificates[] = {p->leaf, p->wrong_name, p->expired, p->foreign, p->self_signed};
        for (size_t i = 0; i < sizeof(certificates) / sizeof(certificates[0]); ++i) {
            server s;
            shiro_https_response r;
            server_start(&s, certificates[i], p->leaf_key, BEHAVE_ANSWER, (const uint8_t *)ok_reply, strlen(ok_reply));
            s.proxy_type = (shiro_proxy_type)kind;
            server_run(&s);
            CHECK_EQ_INT(post(p, &s, "api.test.invalid", 0, 5000, &r, NULL, 0), i == 0 ? SHIRO_OK : SHIRO_E_SECURITY);
            server_stop(&s);
            CHECK(s.proxy_matched);
            if (i == 0) {
                CHECK_EQ_INT(r.status, 200);
                CHECK(strcmp(s.sni, "api.test.invalid") == 0);
                CHECK(strstr(s.request, "Host: api.test.invalid\r\n") != NULL);
                CHECK(strstr(s.request, "Proxy-Authorization:") == NULL);
                CHECK(strstr(s.request, "user:pass") == NULL);
                shiro_https_response_free(&r);
            } else {
                CHECK_EQ_INT(s.request_len, 0);
                CHECK(r.body == NULL);
            }
        }
    }
}

int main(void) {
    pki p;
    pki_make(&p);
    a_good_exchange(&p);
    statuses_and_framing(&p);
    certificates_that_must_be_refused(&p);
    broken_servers(&p);
    split_hello(&p);
    bad_requests(&p);
    proxied_tls(&p);
    pki_free(&p);
    return test_finish("test_shiro_https");
}
