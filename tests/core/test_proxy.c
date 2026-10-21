#include <arpa/inet.h>
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include "shiro_proxy.h"
#include "test_util.h"

typedef struct step {
    const uint8_t *expect;
    size_t expect_len;
    const uint8_t *reply;
    size_t reply_len;
} step;

typedef struct fixture {
    int listener, matched;
    uint16_t port;
    pthread_t thread;
    const step *steps;
    size_t count;
} fixture;

static int receive_exact(int fd, uint8_t *buf, size_t len) {
    while (len) {
        ssize_t n = recv(fd, buf, len, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return 0;
        buf += n; len -= (size_t)n;
    }
    return 1;
}

static void *serve(void *context) {
    fixture *f = context;
    int fd = accept(f->listener, NULL, NULL);
    uint8_t buf[1600];
    struct timeval timeout = {2, 0};
    if (fd < 0) return NULL;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    f->matched = 1;
    for (size_t i = 0; i < f->count; ++i) {
        const step *s = &f->steps[i];
        if (s->expect_len > sizeof(buf) || !receive_exact(fd, buf, s->expect_len) || memcmp(buf, s->expect, s->expect_len) != 0) {
            f->matched = 0; break;
        }
        /* separate writes exercise replies that arrive in partial reads */
        for (size_t j = 0; j < s->reply_len; ++j)
            if (send(fd, s->reply + j, 1, MSG_NOSIGNAL) != 1) break;
    }
    if (f->count && f->steps[f->count - 1].reply_len == 0) {
        /* wait for the client's timeout and close, without a timing sleep */
        (void)recv(fd, buf, sizeof(buf), 0);
    }
    close(fd);
    return NULL;
}

static void start(fixture *f, const step *steps, size_t count) {
    struct sockaddr_in address;
    socklen_t len = sizeof(address);
    memset(f, 0, sizeof(*f));
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    f->listener = socket(AF_INET, SOCK_STREAM, 0);
    CHECK(f->listener >= 0);
    CHECK_EQ_INT(bind(f->listener, (struct sockaddr *)&address, sizeof(address)), 0);
    CHECK_EQ_INT(listen(f->listener, 1), 0);
    CHECK_EQ_INT(getsockname(f->listener, (struct sockaddr *)&address, &len), 0);
    f->port = ntohs(address.sin_port);
    f->steps = steps; f->count = count;
    CHECK_EQ_INT(pthread_create(&f->thread, NULL, serve, f), 0);
}

static void exchange(const char *scheme, const char *login, const step *steps, size_t count, shiro_status expected, int sentinel) {
    fixture f;
    shiro_proxy proxy;
    shiro_socket socket;
    char url[SHIRO_PROXY_URL_MAX + 1];
    start(&f, steps, count);
    snprintf(url, sizeof(url), "%s://%s127.0.0.1:%u", scheme, login, (unsigned)f.port);
    CHECK_EQ_INT(shiro_proxy_parse(url, strlen(url), &proxy), SHIRO_OK);
    shiro_socket_init(&socket);
    CHECK_EQ_INT(shiro_proxy_connect(&socket, &proxy, "api.test.invalid", 443, 150), expected);
    if (expected != SHIRO_OK) CHECK_EQ_INT(socket.fd, -1);
    else if (sentinel) {
        uint8_t byte = 0;
        size_t got = 0;
        CHECK_EQ_INT(shiro_socket_read(&socket, &byte, 1, &got, 1000), SHIRO_OK);
        CHECK_EQ_INT(got, 1);
        CHECK_EQ_INT(byte, '!');
    }
    shiro_socket_close(&socket);
    CHECK_EQ_INT(pthread_join(f.thread, NULL), 0);
    CHECK(f.matched);
    close(f.listener);
}

static void parsing(void) {
    static const char *const bad[] = {
        "socks5://", "http://", "https://example.com:443", "socks5://example.com", "http://:80",
        "http://host:0", "http://host:65536", "http://host:-1", "http://host:12x", "http://host:999999999999",
        "http://host:80/path", "http://host:80?x=1", "http://host:80#x", "http://host:80\r\nX:evil",
        "http://u:p@x@y:80", "socks5://user@host:1", "http://:p@host:1", "socks5://u:@host:1",
        "http://u:%00@host:1", "http://u:%0d@host:1", "http://u:%0a@host:1", "http://u:%xy@host:1",
        "http://u:%@host:1", "http://u:%a@host:1", "http://u%3aname:p@host:1", "http://[bad]:80",
        "http://[::1:80", "http://::1:80", "http://[::1]:", "http://a..b:80", "http://a b:80", "http://host:"
    };
    shiro_proxy proxy;
    CHECK_EQ_INT(shiro_proxy_parse("", 0, &proxy), SHIRO_OK);
    CHECK_EQ_INT(proxy.type, SHIRO_PROXY_NONE);
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i) {
        memset(&proxy, 0xff, sizeof(proxy));
        CHECK_EQ_INT(shiro_proxy_parse(bad[i], strlen(bad[i]), &proxy), SHIRO_E_ARG);
        CHECK_EQ_INT(proxy.type, SHIRO_PROXY_NONE);
        CHECK_EQ_INT(proxy.password[0], 0);
    }
    const char *url = "socks5://user:p%40ss%3Aword@[::1]:65535";
    CHECK_EQ_INT(shiro_proxy_parse(url, strlen(url), &proxy), SHIRO_OK);
    CHECK(strcmp(proxy.username, "user") == 0);
    CHECK(strcmp(proxy.password, "p@ss:word") == 0);
    CHECK(strcmp(proxy.host, "::1") == 0);
    CHECK_EQ_INT(proxy.port, 65535);
    CHECK_EQ_INT(proxy.type, SHIRO_PROXY_SOCKS5);
    CHECK_EQ_INT(shiro_proxy_parse("http://host:1\0bad", 17, &proxy), SHIRO_E_ARG);
    CHECK_EQ_INT(shiro_proxy_parse(NULL, 0, &proxy), SHIRO_E_ARG);
    CHECK_EQ_INT(shiro_proxy_parse("", 0, NULL), SHIRO_E_ARG);
    char long_url[SHIRO_PROXY_URL_MAX + 2];
    memset(long_url, 'a', sizeof(long_url));
    CHECK_EQ_INT(shiro_proxy_parse(long_url, sizeof(long_url), &proxy), SHIRO_E_ARG);
    char credentials[600];
    memset(credentials, 'u', sizeof(credentials));
    memcpy(credentials, "socks5://", 9);
    memcpy(credentials + 9 + 255, ":p@host:1", 10);
    CHECK_EQ_INT(shiro_proxy_parse(credentials, 9 + 255 + 9, &proxy), SHIRO_OK);
    CHECK_EQ_INT(strlen(proxy.username), 255);
    memmove(credentials + 9 + 256, credentials + 9 + 255, 10);
    credentials[9 + 255] = 'u';
    CHECK_EQ_INT(shiro_proxy_parse(credentials, 9 + 256 + 9, &proxy), SHIRO_E_ARG);
}

static void socks(void) {
    static const uint8_t hello[] = {5, 1, 0}, auth_hello[] = {5, 1, 2};
    static const uint8_t no_auth[] = {5, 0}, user_auth[] = {5, 2}, refused[] = {5, 255};
    static const uint8_t auth[] = {1, 4, 'u','s','e','r', 4, 'p','a','s','s'};
    static const uint8_t auth_ok[] = {1, 0}, auth_bad[] = {1, 1};
    static const uint8_t connect[] = {5, 1, 0, 3, 16, 'a','p','i','.','t','e','s','t','.','i','n','v','a','l','i','d', 1, 187};
    static const uint8_t ok[] = {5,0,0,1,127,0,0,1,0,80,'!'};
    step steps[] = {{hello, sizeof(hello), no_auth, sizeof(no_auth)}, {connect, sizeof(connect), ok, sizeof(ok)}};
    exchange("socks5", "", steps, 2, SHIRO_OK, 1);
    static const uint8_t replies[][24] = {
        {5,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,80,'!'},
        {5,0,0,3,1,'a',0,80,'!'}, {5,0,0,3,0}, {5,0,1,1}, {4,0,0,1}, {5,0,0,9}, {5,5,0,1}, {5,0}
    };
    static const size_t lengths[] = {23, 9, 5, 4, 4, 4, 4, 2};
    static const shiro_status statuses[] = {SHIRO_OK, SHIRO_OK, SHIRO_E_MALFORMED, SHIRO_E_MALFORMED,
        SHIRO_E_MALFORMED, SHIRO_E_MALFORMED, SHIRO_E_PROXY, SHIRO_E_EOF};
    for (size_t i = 0; i < sizeof(lengths) / sizeof(lengths[0]); ++i) {
        steps[1].reply = replies[i]; steps[1].reply_len = lengths[i];
        exchange("socks5", "", steps, 2, statuses[i], statuses[i] == SHIRO_OK);
    }
    step login[] = {{auth_hello, sizeof(auth_hello), user_auth, sizeof(user_auth)},
        {auth, sizeof(auth), auth_ok, sizeof(auth_ok)}, {connect, sizeof(connect), ok, sizeof(ok)}};
    exchange("socks5", "user:pass@", login, 3, SHIRO_OK, 1);
    login[1].reply = auth_bad;
    exchange("socks5", "user:pass@", login, 2, SHIRO_E_PROXY_AUTH, 0);
    login[0].reply = no_auth;
    exchange("socks5", "user:pass@", login, 1, SHIRO_E_PROXY_AUTH, 0);
    char max_login[513];
    uint8_t max_auth[513];
    memset(max_login, 'u', 255);
    max_login[255] = ':';
    memset(max_login + 256, 'p', 255);
    max_login[511] = '@'; max_login[512] = 0;
    max_auth[0] = 1; max_auth[1] = 255;
    memset(max_auth + 2, 'u', 255);
    max_auth[257] = 255;
    memset(max_auth + 258, 'p', 255);
    login[0].reply = user_auth;
    login[1].expect = max_auth; login[1].expect_len = sizeof(max_auth); login[1].reply = auth_ok;
    exchange("socks5", max_login, login, 3, SHIRO_OK, 1);
    steps[0].reply = refused;
    exchange("socks5", "", steps, 1, SHIRO_E_PROXY_AUTH, 0);
    steps[0].reply_len = 0;
    exchange("socks5", "", steps, 1, SHIRO_E_TIMEOUT, 0);
}

static void http(void) {
    static const char request[] = "CONNECT api.test.invalid:443 HTTP/1.1\r\nHost: api.test.invalid:443\r\n\r\n";
    static const char auth_request[] = "CONNECT api.test.invalid:443 HTTP/1.1\r\nHost: api.test.invalid:443\r\nProxy-Authorization: Basic dXNlcjpwYXNz\r\n\r\n";
    static const char *const replies[] = {
        "HTTP/1.1 200 Connection established\r\n\r\n!", "HTTP/1.0 200 OK\r\nX-Test: yes\r\n\r\n!",
        "HTTP/1.1 407 Auth required\r\n\r\n", "HTTP/1.1 403 Denied\r\n\r\n", "HTTP/1.1 302 Redirect\r\n\r\n",
        "HTTP/1.1 200 OK\r\nBroken\r\n\r\n", "HTTP/1.1 200 OK\nInjected\r\n\r\n",
        "HTTP/1.1 200 OK\r\n X: yes\r\n\r\n", "HTTP/1.1 20a OK\r\n\r\n", "HTTP/2.0 200 OK\r\n\r\n",
        "HTTP/1.1 200 OK\r\n", ""
    };
    static const shiro_status statuses[] = {SHIRO_OK, SHIRO_OK, SHIRO_E_PROXY_AUTH, SHIRO_E_PROXY, SHIRO_E_PROXY,
        SHIRO_E_MALFORMED, SHIRO_E_MALFORMED, SHIRO_E_MALFORMED, SHIRO_E_MALFORMED, SHIRO_E_MALFORMED, SHIRO_E_EOF, SHIRO_E_TIMEOUT};
    step s = {(const uint8_t *)request, sizeof(request) - 1, NULL, 0};
    for (size_t i = 0; i < sizeof(replies) / sizeof(replies[0]); ++i) {
        s.reply = (const uint8_t *)replies[i]; s.reply_len = strlen(replies[i]);
        exchange("http", "", &s, 1, statuses[i], statuses[i] == SHIRO_OK);
    }
    s.expect = (const uint8_t *)auth_request; s.expect_len = sizeof(auth_request) - 1;
    s.reply = (const uint8_t *)replies[0]; s.reply_len = strlen(replies[0]);
    exchange("http", "user:pass@", &s, 1, SHIRO_OK, 1);
    uint8_t huge[8300];
    memset(huge, 'a', sizeof(huge));
    memcpy(huge, "HTTP/1.1 200 OK\r\nX: ", 20);
    s.expect = (const uint8_t *)request; s.expect_len = sizeof(request) - 1;
    s.reply = huge; s.reply_len = sizeof(huge);
    exchange("http", "", &s, 1, SHIRO_E_LIMIT, 0);
}

int main(void) {
    signal(SIGPIPE, SIG_IGN);
    parsing();
    socks();
    http();
    return test_finish("proxy");
}
