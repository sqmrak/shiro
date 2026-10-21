#include "shiro_http.h"

#include <string.h>

static int is_token_char(uint8_t c) {
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) return 1;
    return c && strchr("!#$%&'*+-.^_`|~", c) != NULL;
}

static int iequal(const uint8_t *a, size_t alen, const char *b) {
    size_t i;
    if (alen != strlen(b)) return 0;
    for (i = 0; i < alen; ++i) {
        uint8_t x = a[i], y = (uint8_t)b[i];
        if (x >= 'A' && x <= 'Z') x = (uint8_t)(x + 32);
        if (y >= 'A' && y <= 'Z') y = (uint8_t)(y + 32);
        if (x != y) return 0;
    }
    return 1;
}

/* the position of the CRLF that ends the line starting at from, or len when there is none */
static size_t find_crlf(const uint8_t *data, size_t len, size_t from) {
    size_t i;
    for (i = from; i + 1 < len; ++i) {
        if (data[i] == '\r' && data[i + 1] == '\n') return i;
    }
    return len;
}

static int hex_digit(uint8_t c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static shiro_status decode_chunked(const uint8_t *data, size_t len, int eof, uint8_t *body, size_t cap, size_t *body_len) {
    size_t pos = 0, out = 0;
    for (;;) {
        size_t line_end = find_crlf(data, len, pos), size = 0, digits = 0;
        if (line_end >= len) return len - pos > 64 ? SHIRO_E_MALFORMED : SHIRO_E_TRUNCATED;
        while (pos + digits < line_end && hex_digit(data[pos + digits]) >= 0) {
            size = size << 4 | (size_t)hex_digit(data[pos + digits]);
            if (++digits > 8) return SHIRO_E_MALFORMED;
        }
        if (digits == 0) return SHIRO_E_MALFORMED;
        /* chunk extensions are allowed and ignored, nothing else may follow the size */
        if (pos + digits < line_end && data[pos + digits] != ';') return SHIRO_E_MALFORMED;
        pos = line_end + 2;
        if (size == 0) {
            /* trailers, then the empty line */
            for (;;) {
                size_t end = find_crlf(data, len, pos);
                if (end >= len) return SHIRO_E_TRUNCATED;
                if (end == pos) {
                    *body_len = out;
                    return SHIRO_OK;
                }
                pos = end + 2;
            }
        }
        if (size > cap - out) return SHIRO_E_LIMIT;
        if (len - pos < size + 2) return SHIRO_E_TRUNCATED;
        memcpy(body + out, data + pos, size);
        out += size;
        pos += size;
        if (data[pos] != '\r' || data[pos + 1] != '\n') return SHIRO_E_MALFORMED;
        pos += 2;
    }
    (void)eof;
}

shiro_status shiro_http_parse_response(const uint8_t *data, size_t len, int eof, shiro_http_response *out, uint8_t *body, size_t cap) {
    size_t pos, line_end, body_start;
    int status;
    int chunked = 0, has_length = 0, i;
    size_t content_length = 0;
    if (out) memset(out, 0, sizeof(*out));
    if (!data || !out || (cap && !body)) return SHIRO_E_ARG;
    line_end = find_crlf(data, len, 0);
    if (line_end >= len) return len > 512 ? SHIRO_E_MALFORMED : (eof ? SHIRO_E_MALFORMED : SHIRO_E_TRUNCATED);
    if (line_end < 12 || memcmp(data, "HTTP/1.", 7) != 0 || (data[7] != '0' && data[7] != '1') || data[8] != ' ') return SHIRO_E_MALFORMED;
    status = 0;
    for (i = 9; i < 12; ++i) {
        if (data[i] < '0' || data[i] > '9') return SHIRO_E_MALFORMED;
        status = status * 10 + (data[i] - '0');
    }
    if (status < 100 || status > 599 || (line_end > 12 && data[12] != ' ')) return SHIRO_E_MALFORMED;
    /* an interim answer would be followed by the real one; a registration call never asks for that, so it is a sign of something else answering */
    if (status < 200) return SHIRO_E_MALFORMED;
    pos = line_end + 2;
    for (;;) {
        size_t end = find_crlf(data, len, pos), colon, name_len, vstart, vend;
        if (pos > SHIRO_HTTP_MAX_HEADERS) return SHIRO_E_LIMIT;
        if (end >= len) return eof ? SHIRO_E_MALFORMED : SHIRO_E_TRUNCATED;
        if (end == pos) {
            body_start = pos + 2;
            break;
        }
        for (colon = pos; colon < end && data[colon] != ':'; ++colon) {
            if (!is_token_char(data[colon])) return SHIRO_E_MALFORMED;
        }
        if (colon == pos || colon >= end) return SHIRO_E_MALFORMED;
        name_len = colon - pos;
        vstart = colon + 1;
        while (vstart < end && (data[vstart] == ' ' || data[vstart] == '\t')) ++vstart;
        vend = end;
        while (vend > vstart && (data[vend - 1] == ' ' || data[vend - 1] == '\t')) --vend;
        if (iequal(data + pos, name_len, "content-length")) {
            size_t k, value = 0;
            if (vend == vstart || vend - vstart > 9) return SHIRO_E_MALFORMED;
            for (k = vstart; k < vend; ++k) {
                if (data[k] < '0' || data[k] > '9') return SHIRO_E_MALFORMED;
                value = value * 10 + (size_t)(data[k] - '0');
            }
            if (has_length && value != content_length) return SHIRO_E_MALFORMED;
            has_length = 1;
            content_length = value;
        } else if (iequal(data + pos, name_len, "transfer-encoding")) {
            if (!iequal(data + vstart, vend - vstart, "chunked")) return SHIRO_E_MALFORMED;
            chunked = 1;
        }
        pos = end + 2;
    }
    if (chunked && has_length) return SHIRO_E_MALFORMED;
    out->status = status;
    if (status == 204 || status == 304) return SHIRO_OK;
    if (chunked) return decode_chunked(data + body_start, len - body_start, eof, body, cap, &out->body_len);
    if (has_length) {
        if (content_length > cap) return SHIRO_E_LIMIT;
        if (len - body_start < content_length) return SHIRO_E_TRUNCATED;
        memcpy(body, data + body_start, content_length);
        out->body_len = content_length;
        return SHIRO_OK;
    }
    /* no framing: the body runs to the end of the connection */
    if (!eof) return SHIRO_E_TRUNCATED;
    if (len - body_start > cap) return SHIRO_E_LIMIT;
    memcpy(body, data + body_start, len - body_start);
    out->body_len = len - body_start;
    return SHIRO_OK;
}
