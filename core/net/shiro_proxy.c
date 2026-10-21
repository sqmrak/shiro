#include "shiro_proxy.h"

#include <arpa/inet.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <openssl/evp.h>

#include "shiro_bytes.h"
#include "shiro_clock.h"

static int hex_digit(unsigned char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int decode_credential(const char *text, size_t len, char out[256]) {
    size_t n = 0;
    for (size_t i = 0; i < len; ++i) {
        unsigned char c = (unsigned char)text[i];
        if (c == '%') {
            int hi, lo;
            if (len - i < 3) return 0;
            hi = hex_digit((unsigned char)text[i + 1]);
            lo = hex_digit((unsigned char)text[i + 2]);
            if (hi < 0 || lo < 0) return 0;
            c = (unsigned char)(hi * 16 + lo);
            i += 2;
        }
        if (c < 0x20 || c == 0x7f || n == 255) return 0;
        out[n++] = (char)c;
    }
    out[n] = 0;
    return n != 0;
}

static int valid_host(const char *host) {
    unsigned char address[16];
    size_t n = strlen(host);
    if (!n || n > 253) return 0;
    if (strchr(host, ':')) return inet_pton(AF_INET6, host, address) == 1;
    for (size_t i = 0; i < n; ++i) {
        unsigned char c = (unsigned char)host[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '-' || c == '.')) return 0;
        if (c == '.' && (i == 0 || host[i - 1] == '.')) return 0;
    }
    return host[0] != '-' && host[n - 1] != '-';
}

shiro_status shiro_proxy_parse(const char *url, size_t len, shiro_proxy *out) {
    shiro_proxy parsed;
    const char *begin, *end, *at, *colon, *port;
    size_t host_len;
    unsigned value = 0;
    shiro_status status = SHIRO_E_ARG;
    if (!out) return SHIRO_E_ARG;
    memset(out, 0, sizeof(*out));
    memset(&parsed, 0, sizeof(parsed));
    if (!url || len > SHIRO_PROXY_URL_MAX || memchr(url, 0, len)) return SHIRO_E_ARG;
    if (!len) return SHIRO_OK;
    if (len >= 9 && memcmp(url, "socks5://", 9) == 0) {
        parsed.type = SHIRO_PROXY_SOCKS5;
        begin = url + 9;
    } else if (len >= 7 && memcmp(url, "http://", 7) == 0) {
        parsed.type = SHIRO_PROXY_HTTP;
        begin = url + 7;
    } else return SHIRO_E_ARG;
    end = url + len;
    if (begin >= end) goto done;
    for (const char *p = begin; p < end; ++p) {
        unsigned char c = (unsigned char)*p;
        if (c <= 0x20 || c >= 0x7f || c == '/' || c == '?' || c == '#' || c == '\\') goto done;
    }
    at = memchr(begin, '@', (size_t)(end - begin));
    if (at) {
        colon = memchr(begin, ':', (size_t)(at - begin));
        if (!colon || memchr(at + 1, '@', (size_t)(end - at - 1)) ||
            !decode_credential(begin, (size_t)(colon - begin), parsed.username) ||
            !decode_credential(colon + 1, (size_t)(at - colon - 1), parsed.password) || strchr(parsed.username, ':')) goto done;
        begin = at + 1;
    }
    if (begin == end) goto done;
    if (*begin == '[') {
        const char *bracket = memchr(begin, ']', (size_t)(end - begin));
        if (!bracket || end - bracket < 3 || bracket[1] != ':') goto done;
        ++begin;
        host_len = (size_t)(bracket - begin);
        port = bracket + 2;
        if (!memchr(begin, ':', host_len)) goto done;
    } else {
        colon = memchr(begin, ':', (size_t)(end - begin));
        if (!colon) goto done;
        host_len = (size_t)(colon - begin);
        port = colon + 1;
    }
    if (!host_len || host_len >= sizeof(parsed.host) || port == end) goto done;
    memcpy(parsed.host, begin, host_len);
    if (!valid_host(parsed.host)) goto done;
    for (const char *p = port; p < end; ++p) {
        if (*p < '0' || *p > '9' || value > 6553) goto done;
        value = value * 10 + (unsigned)(*p - '0');
        if (value > 65535) goto done;
    }
    if (!value) goto done;
    parsed.port = (uint16_t)value;
    *out = parsed;
    status = SHIRO_OK;
done:
    shiro_wipe(&parsed, sizeof(parsed));
    return status;
}

static int time_left(uint64_t deadline) {
    uint64_t now = shiro_system_clock.monotonic_ms(NULL);
    return now >= deadline ? 0 : (int)(deadline - now > INT_MAX ? INT_MAX : deadline - now);
}

static shiro_status write_bytes(shiro_socket *socket, const uint8_t *data, size_t len, uint64_t deadline) {
    int left = time_left(deadline);
    return left ? shiro_socket_write_all(socket, data, len, left) : SHIRO_E_TIMEOUT;
}

static shiro_status read_bytes(shiro_socket *socket, uint8_t *data, size_t len, uint64_t deadline) {
    while (len) {
        size_t got = 0;
        int left = time_left(deadline);
        shiro_status status;
        if (!left) return SHIRO_E_TIMEOUT;
        status = shiro_socket_read(socket, data, len, &got, left);
        if (status != SHIRO_OK) return status;
        data += got;
        len -= got;
    }
    return SHIRO_OK;
}

static shiro_status socks_connect(shiro_socket *socket, const shiro_proxy *proxy, const char *host, uint16_t port, uint64_t deadline) {
    uint8_t buf[513], reply[4];
    size_t ulen = strlen(proxy->username), plen = strlen(proxy->password), n = strlen(host);
    shiro_status status;
    buf[0] = 5; buf[1] = 1; buf[2] = ulen ? 2 : 0;
    status = write_bytes(socket, buf, 3, deadline);
    if (status != SHIRO_OK) return status;
    status = read_bytes(socket, reply, 2, deadline);
    if (status != SHIRO_OK) return status;
    if (reply[0] != 5) return SHIRO_E_MALFORMED;
    /* a configured login must not silently downgrade to unauthenticated access */
    if (reply[1] != buf[2]) return SHIRO_E_PROXY_AUTH;
    if (ulen) {
        buf[0] = 1; buf[1] = (uint8_t)ulen;
        memcpy(buf + 2, proxy->username, ulen);
        buf[2 + ulen] = (uint8_t)plen;
        memcpy(buf + 3 + ulen, proxy->password, plen);
        status = write_bytes(socket, buf, 3 + ulen + plen, deadline);
        shiro_wipe(buf, sizeof(buf));
        if (status != SHIRO_OK) return status;
        status = read_bytes(socket, reply, 2, deadline);
        if (status != SHIRO_OK) return status;
        if (reply[0] != 1) return SHIRO_E_MALFORMED;
        if (reply[1] != 0) return SHIRO_E_PROXY_AUTH;
    }
    buf[0] = 5; buf[1] = 1; buf[2] = 0; buf[3] = 3; buf[4] = (uint8_t)n;
    memcpy(buf + 5, host, n);
    buf[5 + n] = (uint8_t)(port >> 8); buf[6 + n] = (uint8_t)port;
    status = write_bytes(socket, buf, n + 7, deadline);
    if (status != SHIRO_OK) return status;
    status = read_bytes(socket, reply, sizeof(reply), deadline);
    if (status != SHIRO_OK) return status;
    if (reply[0] != 5 || reply[2] != 0) return SHIRO_E_MALFORMED;
    if (reply[1] > 8) return SHIRO_E_MALFORMED;
    if (reply[1] != 0) return SHIRO_E_PROXY;
    if (reply[3] == 1) n = 4;
    else if (reply[3] == 4) n = 16;
    else if (reply[3] == 3) {
        status = read_bytes(socket, buf, 1, deadline);
        if (status != SHIRO_OK) return status;
        n = buf[0];
        if (!n) return SHIRO_E_MALFORMED;
    } else return SHIRO_E_MALFORMED;
    return read_bytes(socket, buf, n + 2, deadline);
}

static int header_token(unsigned char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') || strchr("!#$%&'*+-.^_`|~", c) != NULL;
}

static shiro_status connect_response(char *header) {
    char *end = strstr(header, "\r\n"), *line;
    int code;
    for (char *p = header; *p; ++p)
        if ((*p == '\r' && p[1] != '\n') || (*p == '\n' && (p == header || p[-1] != '\r'))) return SHIRO_E_MALFORMED;
    if (!end || end - header < 13 ||
        (memcmp(header, "HTTP/1.1 ", 9) != 0 && memcmp(header, "HTTP/1.0 ", 9) != 0) ||
        header[9] < '1' || header[9] > '5' || header[10] < '0' || header[10] > '9' ||
        header[11] < '0' || header[11] > '9' || header[12] != ' ') return SHIRO_E_MALFORMED;
    code = (header[9] - '0') * 100 + (header[10] - '0') * 10 + header[11] - '0';
    line = end + 2;
    while (line[0]) {
        char *colon;
        end = strstr(line, "\r\n");
        if (!end) return SHIRO_E_MALFORMED;
        if (end == line) break;
        colon = memchr(line, ':', (size_t)(end - line));
        if (!colon || colon == line) return SHIRO_E_MALFORMED;
        for (char *p = line; p < colon; ++p) if (!header_token((unsigned char)*p)) return SHIRO_E_MALFORMED;
        line = end + 2;
    }
    if (code == 407) return SHIRO_E_PROXY_AUTH;
    return code >= 200 && code <= 299 ? SHIRO_OK : SHIRO_E_PROXY;
}

static shiro_status http_connect(shiro_socket *socket, const shiro_proxy *proxy, const char *host, uint16_t port, uint64_t deadline) {
    char request[1536], credentials[512], auth[685], response[8193];
    size_t used, n = 0;
    int w;
    shiro_status status;
    w = snprintf(request, sizeof(request), "CONNECT %s:%u HTTP/1.1\r\nHost: %s:%u\r\n", host, (unsigned)port, host, (unsigned)port);
    if (w < 0 || (size_t)w >= sizeof(request)) return SHIRO_E_ARG;
    used = (size_t)w;
    if (proxy->username[0]) {
        w = snprintf(credentials, sizeof(credentials), "%s:%s", proxy->username, proxy->password);
        if (w < 0 || (size_t)w >= sizeof(credentials)) return SHIRO_E_ARG;
        int encoded = EVP_EncodeBlock((unsigned char *)auth, (const unsigned char *)credentials, w);
        if (encoded < 0 || (size_t)encoded >= sizeof(auth)) {
            shiro_wipe(credentials, sizeof(credentials));
            shiro_wipe(auth, sizeof(auth));
            return SHIRO_E_CRYPTO;
        }
        w = snprintf(request + used, sizeof(request) - used, "Proxy-Authorization: Basic %s\r\n", auth);
        shiro_wipe(credentials, sizeof(credentials));
        shiro_wipe(auth, sizeof(auth));
        if (w < 0 || (size_t)w >= sizeof(request) - used) { shiro_wipe(request, sizeof(request)); return SHIRO_E_LIMIT; }
        used += (size_t)w;
    }
    request[used++] = '\r'; request[used++] = '\n';
    status = write_bytes(socket, (const uint8_t *)request, used, deadline);
    shiro_wipe(request, sizeof(request));
    if (status != SHIRO_OK) return status;
    /* read exactly through the headers, leaving any tunnel bytes in the socket */
    n = 0;
    while (n < sizeof(response) - 1) {
        unsigned char c;
        status = read_bytes(socket, &c, 1, deadline);
        if (status != SHIRO_OK) return status;
        if ((c < 0x20 && c != '\r' && c != '\n' && c != '\t') || c == 0x7f) return SHIRO_E_MALFORMED;
        response[n++] = (char)c;
        if (n >= 4 && memcmp(response + n - 4, "\r\n\r\n", 4) == 0) {
            response[n] = 0;
            return connect_response(response);
        }
    }
    return SHIRO_E_LIMIT;
}

shiro_status shiro_proxy_connect(shiro_socket *socket, const shiro_proxy *proxy, const char *host, uint16_t port, int timeout_ms) {
    uint64_t deadline;
    shiro_status status;
    if (!socket || !proxy || !host || !valid_host(host) || strchr(host, ':') || !port || timeout_ms <= 0 ||
        (proxy->type != SHIRO_PROXY_SOCKS5 && proxy->type != SHIRO_PROXY_HTTP) ||
        !memchr(proxy->host, 0, sizeof(proxy->host)) || !valid_host(proxy->host) || !proxy->port ||
        !memchr(proxy->username, 0, sizeof(proxy->username)) || !memchr(proxy->password, 0, sizeof(proxy->password))) return SHIRO_E_ARG;
    if (socket->fd >= 0) return SHIRO_E_STATE;
    deadline = shiro_system_clock.monotonic_ms(NULL) + (uint64_t)timeout_ms;
    status = shiro_socket_connect(socket, proxy->host, proxy->port, timeout_ms);
    if (status != SHIRO_OK) return status;
    if (proxy->type == SHIRO_PROXY_SOCKS5) status = socks_connect(socket, proxy, host, port, deadline);
    else status = http_connect(socket, proxy, host, port, deadline);
    if (status != SHIRO_OK) shiro_socket_close(socket);
    return status;
}
