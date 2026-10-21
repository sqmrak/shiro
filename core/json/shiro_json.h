#ifndef SHIRO_JSON_H
#define SHIRO_JSON_H

#include <stddef.h>
#include <stdint.h>

#include "shiro_status.h"

/* registration replies have bounded depth, node count and UTF-8 text */

#define SHIRO_JSON_MAX_DEPTH 12
#define SHIRO_JSON_MAX_TEXT (64u * 1024u)
#define SHIRO_JSON_MAX_NODES 4096u

typedef enum shiro_json_type {
    SHIRO_JSON_NULL,
    SHIRO_JSON_BOOL,
    SHIRO_JSON_NUMBER,
    SHIRO_JSON_STRING,
    SHIRO_JSON_ARRAY,
    SHIRO_JSON_OBJECT
} shiro_json_type;

typedef struct shiro_json shiro_json;
typedef struct shiro_json_doc shiro_json_doc;

/* parses a whole document, which must be one value and nothing after it but white space. SHIRO_E_MALFORMED for anything that is not
   JSON (a bare value is fine), a string with a control character, a bad escape or invalid UTF-8, a NUL in a string, a number that does
   not follow the grammar; SHIRO_E_LIMIT for a document over the caps. *out is NULL on failure */
shiro_status shiro_json_parse(const char *text, size_t len, shiro_json_doc **out);
void shiro_json_free(shiro_json_doc *doc);
const shiro_json *shiro_json_root(const shiro_json_doc *doc);

shiro_json_type shiro_json_kind(const shiro_json *node);

/* the last member of an object with that key, or NULL; also NULL when node is not an object */
const shiro_json *shiro_json_get(const shiro_json *object, const char *key);

/* array elements and object members in document order: first and next are NULL at the end, and for a node that holds none */
const shiro_json *shiro_json_first(const shiro_json *node);
const shiro_json *shiro_json_next(const shiro_json *node);
size_t shiro_json_count(const shiro_json *node);
/* the key of an object member, NULL for anything else */
const char *shiro_json_key(const shiro_json *node);

/* the string value, NUL terminated, with its length in bytes; NULL when node is not a string */
const char *shiro_json_string(const shiro_json *node, size_t *len);
/* an integral number that fits int64; SHIRO_E_MALFORMED for a fraction, an exponent form or a value out of range, and for a
   node that is no number */
shiro_status shiro_json_int(const shiro_json *node, int64_t *out);
shiro_status shiro_json_bool(const shiro_json *node, int *out);

/* writing: values go to a buffer the caller owns, commas and the colons come by themselves. A failed step (a buffer too small, a
   misplaced call, a nesting too deep) sticks, and finish reports it */
typedef struct shiro_json_out {
    char *buf;
    size_t cap;
    size_t len;
    shiro_status status;
    int depth;
    uint8_t member_count[SHIRO_JSON_MAX_DEPTH];
    uint8_t is_object[SHIRO_JSON_MAX_DEPTH];
    uint8_t key_pending;
} shiro_json_out;

void shiro_json_out_init(shiro_json_out *out, char *buf, size_t cap);
void shiro_json_out_object(shiro_json_out *out);
void shiro_json_out_array(shiro_json_out *out);
void shiro_json_out_end(shiro_json_out *out);
/* the key of the next object member; the value follows in the next call */
void shiro_json_out_key(shiro_json_out *out, const char *key);
void shiro_json_out_string(shiro_json_out *out, const char *value);
void shiro_json_out_int(shiro_json_out *out, int64_t value);
void shiro_json_out_bool(shiro_json_out *out, int value);
/* SHIRO_OK with the length (the text is NUL terminated) once exactly one value is complete */
shiro_status shiro_json_out_finish(shiro_json_out *out, size_t *len);

#endif
