#ifndef SHIRO_BYTES_H
#define SHIRO_BYTES_H

#include <stddef.h>
#include <stdint.h>

#include "shiro_status.h"

typedef struct shiro_slice {
    const uint8_t *data;
    size_t len;
} shiro_slice;

typedef struct shiro_reader {
    const uint8_t *data;
    size_t len;
    size_t pos;
    shiro_status status;
} shiro_reader;

void shiro_reader_init(shiro_reader *r, const uint8_t *data, size_t len);
size_t shiro_reader_left(const shiro_reader *r);
uint8_t shiro_rd_u8(shiro_reader *r);
uint32_t shiro_rd_u32le(shiro_reader *r);
uint64_t shiro_rd_u64le(shiro_reader *r);
uint32_t shiro_rd_u32be(shiro_reader *r);
const uint8_t *shiro_rd_bytes(shiro_reader *r, size_t n);

typedef struct shiro_writer {
    uint8_t *data;
    size_t len;
    size_t cap;
    size_t max;
    shiro_status status;
} shiro_writer;

void shiro_writer_init(shiro_writer *w, size_t max);
void shiro_writer_free(shiro_writer *w);
uint8_t *shiro_writer_take(shiro_writer *w, size_t *len);
shiro_status shiro_wr_reserve(shiro_writer *w, size_t extra);
shiro_status shiro_wr_bytes(shiro_writer *w, const void *data, size_t n);
shiro_status shiro_wr_zero(shiro_writer *w, size_t n);
shiro_status shiro_wr_u8(shiro_writer *w, uint8_t v);
shiro_status shiro_wr_u32le(shiro_writer *w, uint32_t v);
shiro_status shiro_wr_u64le(shiro_writer *w, uint64_t v);
shiro_status shiro_wr_u32be(shiro_writer *w, uint32_t v);

void shiro_put_u32le(uint8_t *out, uint32_t v);
void shiro_put_u64le(uint8_t *out, uint64_t v);
void shiro_put_u32be(uint8_t *out, uint32_t v);
void shiro_put_u64be(uint8_t *out, uint64_t v);
uint32_t shiro_get_u32le(const uint8_t *in);
uint64_t shiro_get_u64le(const uint8_t *in);
uint32_t shiro_get_u32be(const uint8_t *in);
uint64_t shiro_get_u64be(const uint8_t *in);

int shiro_ct_equal(const void *a, const void *b, size_t n);
/* a plain memset on a dead buffer is removed by the optimizer, key material would stay in memory */
void shiro_wipe(void *p, size_t n);

#endif
