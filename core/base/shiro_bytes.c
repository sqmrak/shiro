#include "shiro_bytes.h"

#include <stdlib.h>
#include <string.h>

void shiro_put_u32le(uint8_t *out, uint32_t v) {
    out[0] = (uint8_t)v;
    out[1] = (uint8_t)(v >> 8);
    out[2] = (uint8_t)(v >> 16);
    out[3] = (uint8_t)(v >> 24);
}

void shiro_put_u64le(uint8_t *out, uint64_t v) {
    shiro_put_u32le(out, (uint32_t)v);
    shiro_put_u32le(out + 4, (uint32_t)(v >> 32));
}

void shiro_put_u32be(uint8_t *out, uint32_t v) {
    out[0] = (uint8_t)(v >> 24);
    out[1] = (uint8_t)(v >> 16);
    out[2] = (uint8_t)(v >> 8);
    out[3] = (uint8_t)v;
}

void shiro_put_u64be(uint8_t *out, uint64_t v) {
    shiro_put_u32be(out, (uint32_t)(v >> 32));
    shiro_put_u32be(out + 4, (uint32_t)v);
}

uint32_t shiro_get_u32le(const uint8_t *in) {
    return (uint32_t)in[0] | ((uint32_t)in[1] << 8) | ((uint32_t)in[2] << 16) | ((uint32_t)in[3] << 24);
}

uint64_t shiro_get_u64le(const uint8_t *in) {
    return (uint64_t)shiro_get_u32le(in) | ((uint64_t)shiro_get_u32le(in + 4) << 32);
}

uint32_t shiro_get_u32be(const uint8_t *in) {
    return ((uint32_t)in[0] << 24) | ((uint32_t)in[1] << 16) | ((uint32_t)in[2] << 8) | (uint32_t)in[3];
}

uint64_t shiro_get_u64be(const uint8_t *in) {
    return ((uint64_t)shiro_get_u32be(in) << 32) | (uint64_t)shiro_get_u32be(in + 4);
}

void shiro_reader_init(shiro_reader *r, const uint8_t *data, size_t len) {
    r->data = data;
    r->len = data ? len : 0;
    r->pos = 0;
    r->status = SHIRO_OK;
}

size_t shiro_reader_left(const shiro_reader *r) {
    return r->len - r->pos;
}

const uint8_t *shiro_rd_bytes(shiro_reader *r, size_t n) {
    const uint8_t *p;
    if (r->status != SHIRO_OK) return NULL;
    if (n > r->len - r->pos) {
        r->status = SHIRO_E_TRUNCATED;
        return NULL;
    }
    p = r->data + r->pos;
    r->pos += n;
    return p;
}

uint8_t shiro_rd_u8(shiro_reader *r) {
    const uint8_t *p = shiro_rd_bytes(r, 1);
    return p ? p[0] : 0;
}

uint32_t shiro_rd_u32le(shiro_reader *r) {
    const uint8_t *p = shiro_rd_bytes(r, 4);
    return p ? shiro_get_u32le(p) : 0;
}

uint64_t shiro_rd_u64le(shiro_reader *r) {
    const uint8_t *p = shiro_rd_bytes(r, 8);
    return p ? shiro_get_u64le(p) : 0;
}

uint32_t shiro_rd_u32be(shiro_reader *r) {
    const uint8_t *p = shiro_rd_bytes(r, 4);
    return p ? shiro_get_u32be(p) : 0;
}

void shiro_writer_init(shiro_writer *w, size_t max) {
    w->data = NULL;
    w->len = 0;
    w->cap = 0;
    w->max = max;
    w->status = SHIRO_OK;
}

void shiro_writer_free(shiro_writer *w) {
    free(w->data);
    w->data = NULL;
    w->len = 0;
    w->cap = 0;
}

uint8_t *shiro_writer_take(shiro_writer *w, size_t *len) {
    uint8_t *p = w->data;
    if (len) *len = w->len;
    w->data = NULL;
    w->len = 0;
    w->cap = 0;
    return p;
}

shiro_status shiro_wr_reserve(shiro_writer *w, size_t extra) {
    size_t need, cap;
    uint8_t *grown;
    if (w->status != SHIRO_OK) return w->status;
    if (extra > w->max - w->len) {
        w->status = SHIRO_E_LIMIT;
        return w->status;
    }
    need = w->len + extra;
    if (need <= w->cap) return SHIRO_OK;
    cap = w->cap ? w->cap : 256;
    while (cap < need) {
        if (cap > w->max / 2) {
            cap = w->max;
            break;
        }
        cap *= 2;
    }
    if (cap < need) cap = need;
    grown = (uint8_t *)realloc(w->data, cap);
    if (!grown) {
        w->status = SHIRO_E_NOMEM;
        return w->status;
    }
    w->data = grown;
    w->cap = cap;
    return SHIRO_OK;
}

shiro_status shiro_wr_bytes(shiro_writer *w, const void *data, size_t n) {
    shiro_status s;
    if (n == 0) return w->status;
    if (!data) return SHIRO_E_ARG;
    s = shiro_wr_reserve(w, n);
    if (s != SHIRO_OK) return s;
    memcpy(w->data + w->len, data, n);
    w->len += n;
    return SHIRO_OK;
}

shiro_status shiro_wr_zero(shiro_writer *w, size_t n) {
    shiro_status s = shiro_wr_reserve(w, n);
    if (s != SHIRO_OK) return s;
    if (n) memset(w->data + w->len, 0, n);
    w->len += n;
    return SHIRO_OK;
}

shiro_status shiro_wr_u8(shiro_writer *w, uint8_t v) {
    return shiro_wr_bytes(w, &v, 1);
}

shiro_status shiro_wr_u32le(shiro_writer *w, uint32_t v) {
    uint8_t b[4];
    shiro_put_u32le(b, v);
    return shiro_wr_bytes(w, b, 4);
}

shiro_status shiro_wr_u64le(shiro_writer *w, uint64_t v) {
    uint8_t b[8];
    shiro_put_u64le(b, v);
    return shiro_wr_bytes(w, b, 8);
}

shiro_status shiro_wr_u32be(shiro_writer *w, uint32_t v) {
    uint8_t b[4];
    shiro_put_u32be(b, v);
    return shiro_wr_bytes(w, b, 4);
}

int shiro_ct_equal(const void *a, const void *b, size_t n) {
    const volatile uint8_t *x = (const volatile uint8_t *)a;
    const volatile uint8_t *y = (const volatile uint8_t *)b;
    uint8_t diff = 0;
    size_t i;
    for (i = 0; i < n; ++i) diff |= (uint8_t)(x[i] ^ y[i]);
    return diff == 0;
}

void shiro_wipe(void *p, size_t n) {
    volatile uint8_t *v = (volatile uint8_t *)p;
    size_t i;
    for (i = 0; i < n; ++i) v[i] = 0;
}
