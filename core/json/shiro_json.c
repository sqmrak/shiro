#include "shiro_json.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct shiro_json {
    uint8_t kind;
    uint8_t is_int;
    uint8_t flag;
    int64_t integer;
    const char *text;
    size_t text_len;
    const char *key;
    shiro_json *first;
    shiro_json *last;
    shiro_json *next;
    size_t count;
};

struct shiro_json_doc {
    shiro_json *nodes;
    size_t node_cap;
    size_t node_count;
    char *pool;
    size_t pool_cap;
    size_t pool_len;
    const char *input;
    size_t input_len;
    size_t pos;
    shiro_status status;
};

static void fail(shiro_json_doc *d, shiro_status status) {
    if (d->status == SHIRO_OK) d->status = status;
}

static int at_end(const shiro_json_doc *d) {
    return d->pos >= d->input_len;
}

static void skip_space(shiro_json_doc *d) {
    while (!at_end(d)) {
        char c = d->input[d->pos];
        if (c != ' ' && c != '\t' && c != '\n' && c != '\r') break;
        ++d->pos;
    }
}

static shiro_json *new_node(shiro_json_doc *d, shiro_json_type kind) {
    shiro_json *n;
    if (d->node_count >= d->node_cap) {
        fail(d, SHIRO_E_LIMIT);
        return NULL;
    }
    n = &d->nodes[d->node_count++];
    memset(n, 0, sizeof(*n));
    n->kind = (uint8_t)kind;
    return n;
}

static int hex4(const char *s, uint32_t *out) {
    uint32_t v = 0;
    int i;
    for (i = 0; i < 4; ++i) {
        char c = s[i];
        v <<= 4;
        if (c >= '0' && c <= '9') v |= (uint32_t)(c - '0');
        else if (c >= 'a' && c <= 'f') v |= (uint32_t)(c - 'a' + 10);
        else if (c >= 'A' && c <= 'F') v |= (uint32_t)(c - 'A' + 10);
        else return 0;
    }
    *out = v;
    return 1;
}

static size_t put_utf8(char *out, uint32_t cp) {
    if (cp < 0x80) {
        out[0] = (char)cp;
        return 1;
    }
    if (cp < 0x800) {
        out[0] = (char)(0xC0 | (cp >> 6));
        out[1] = (char)(0x80 | (cp & 0x3F));
        return 2;
    }
    if (cp < 0x10000) {
        out[0] = (char)(0xE0 | (cp >> 12));
        out[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        out[2] = (char)(0x80 | (cp & 0x3F));
        return 3;
    }
    out[0] = (char)(0xF0 | (cp >> 18));
    out[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
    out[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
    out[3] = (char)(0x80 | (cp & 0x3F));
    return 4;
}

/* the length of the well formed UTF-8 sequence at s, or 0; overlong forms, surrogates and values past U+10FFFF are refused */
static size_t utf8_len(const unsigned char *s, size_t left) {
    unsigned char c = s[0];
    if (c < 0x80) return 1;
    if (c >= 0xC2 && c <= 0xDF) return left >= 2 && (s[1] & 0xC0) == 0x80 ? 2 : 0;
    if (c >= 0xE0 && c <= 0xEF) {
        if (left < 3 || (s[1] & 0xC0) != 0x80 || (s[2] & 0xC0) != 0x80) return 0;
        if (c == 0xE0 && s[1] < 0xA0) return 0;
        if (c == 0xED && s[1] > 0x9F) return 0;
        return 3;
    }
    if (c >= 0xF0 && c <= 0xF4) {
        if (left < 4 || (s[1] & 0xC0) != 0x80 || (s[2] & 0xC0) != 0x80 || (s[3] & 0xC0) != 0x80) return 0;
        if (c == 0xF0 && s[1] < 0x90) return 0;
        if (c == 0xF4 && s[1] > 0x8F) return 0;
        return 4;
    }
    return 0;
}

/* reads a string after the opening quote into the pool; returns its start, or NULL with the failure set */
static const char *read_string(shiro_json_doc *d, size_t *len_out) {
    char *start = d->pool + d->pool_len;
    size_t used = 0;
    for (;;) {
        unsigned char c;
        if (at_end(d)) {
            fail(d, SHIRO_E_MALFORMED);
            return NULL;
        }
        c = (unsigned char)d->input[d->pos];
        if (c == '"') {
            ++d->pos;
            break;
        }
        if (c < 0x20) {
            fail(d, SHIRO_E_MALFORMED);
            return NULL;
        }
        if (d->pool_len + used + 5 > d->pool_cap) {
            fail(d, SHIRO_E_LIMIT);
            return NULL;
        }
        if (c == '\\') {
            char e;
            ++d->pos;
            if (at_end(d)) {
                fail(d, SHIRO_E_MALFORMED);
                return NULL;
            }
            e = d->input[d->pos++];
            switch (e) {
            case '"': start[used++] = '"'; break;
            case '\\': start[used++] = '\\'; break;
            case '/': start[used++] = '/'; break;
            case 'b': start[used++] = '\b'; break;
            case 'f': start[used++] = '\f'; break;
            case 'n': start[used++] = '\n'; break;
            case 'r': start[used++] = '\r'; break;
            case 't': start[used++] = '\t'; break;
            case 'u': {
                uint32_t cp, low;
                if (d->input_len - d->pos < 4 || !hex4(d->input + d->pos, &cp)) {
                    fail(d, SHIRO_E_MALFORMED);
                    return NULL;
                }
                d->pos += 4;
                if (cp >= 0xD800 && cp <= 0xDBFF) {
                    /* a high surrogate must be followed by \u and a low surrogate; together they are one code point */
                    if (d->input_len - d->pos < 6 || d->input[d->pos] != '\\' || d->input[d->pos + 1] != 'u' ||
                        !hex4(d->input + d->pos + 2, &low) || low < 0xDC00 || low > 0xDFFF) {
                        fail(d, SHIRO_E_MALFORMED);
                        return NULL;
                    }
                    d->pos += 6;
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
                    fail(d, SHIRO_E_MALFORMED);
                    return NULL;
                }
                if (cp == 0) {
                    fail(d, SHIRO_E_MALFORMED);
                    return NULL;
                }
                used += put_utf8(start + used, cp);
                break;
            }
            default:
                fail(d, SHIRO_E_MALFORMED);
                return NULL;
            }
        } else {
            size_t n = utf8_len((const unsigned char *)d->input + d->pos, d->input_len - d->pos);
            if (n == 0) {
                fail(d, SHIRO_E_MALFORMED);
                return NULL;
            }
            memcpy(start + used, d->input + d->pos, n);
            used += n;
            d->pos += n;
        }
    }
    start[used] = '\0';
    d->pool_len += used + 1;
    *len_out = used;
    return start;
}

static shiro_json *parse_value(shiro_json_doc *d, int depth);

static int read_number(shiro_json_doc *d, shiro_json *n) {
    size_t begin = d->pos, i;
    char buf[40];
    int integral = 1;
    int negative = 0;
    if (!at_end(d) && d->input[d->pos] == '-') {
        negative = 1;
        ++d->pos;
    }
    if (at_end(d)) return 0;
    if (d->input[d->pos] == '0') {
        ++d->pos;
    } else if (d->input[d->pos] >= '1' && d->input[d->pos] <= '9') {
        while (!at_end(d) && d->input[d->pos] >= '0' && d->input[d->pos] <= '9') ++d->pos;
    } else {
        return 0;
    }
    if (!at_end(d) && d->input[d->pos] == '.') {
        size_t digits = 0;
        integral = 0;
        ++d->pos;
        while (!at_end(d) && d->input[d->pos] >= '0' && d->input[d->pos] <= '9') {
            ++d->pos;
            ++digits;
        }
        if (digits == 0) return 0;
    }
    if (!at_end(d) && (d->input[d->pos] == 'e' || d->input[d->pos] == 'E')) {
        size_t digits = 0;
        integral = 0;
        ++d->pos;
        if (!at_end(d) && (d->input[d->pos] == '+' || d->input[d->pos] == '-')) ++d->pos;
        while (!at_end(d) && d->input[d->pos] >= '0' && d->input[d->pos] <= '9') {
            ++d->pos;
            ++digits;
        }
        if (digits == 0) return 0;
    }
    /* a number longer than the buffer is no integer this protocol sends */
    if (d->pos - begin >= sizeof(buf)) {
        n->is_int = 0;
        return 1;
    }
    memcpy(buf, d->input + begin, d->pos - begin);
    buf[d->pos - begin] = '\0';
    if (integral) {
        int64_t value = 0;
        size_t digits = d->pos - begin - (size_t)negative;
        /* up to 18 digits always fit; 19 may overflow, which is checked on the way */
        if (digits <= 19) {
            int overflow = 0;
            for (i = (size_t)negative; buf[i]; ++i) {
                int digit = buf[i] - '0';
                if (negative) {
                    if (value < (INT64_MIN + digit) / 10) {
                        overflow = 1;
                        break;
                    }
                    value = value * 10 - digit;
                } else {
                    if (value > (INT64_MAX - digit) / 10) {
                        overflow = 1;
                        break;
                    }
                    value = value * 10 + digit;
                }
            }
            if (!overflow) {
                n->is_int = 1;
                n->integer = value;
            }
        }
    }
    return 1;
}

static int expect_word(shiro_json_doc *d, const char *word) {
    size_t n = strlen(word);
    if (d->input_len - d->pos < n || memcmp(d->input + d->pos, word, n) != 0) return 0;
    d->pos += n;
    return 1;
}

static void append_child(shiro_json *parent, shiro_json *child) {
    if (parent->last) parent->last->next = child;
    else parent->first = child;
    parent->last = child;
    ++parent->count;
}

static shiro_json *parse_value(shiro_json_doc *d, int depth) {
    shiro_json *n;
    char c;
    skip_space(d);
    if (at_end(d)) {
        fail(d, SHIRO_E_MALFORMED);
        return NULL;
    }
    c = d->input[d->pos];
    if (c == '{' || c == '[') {
        int is_object = c == '{';
        char close = is_object ? '}' : ']';
        if (depth >= SHIRO_JSON_MAX_DEPTH) {
            fail(d, SHIRO_E_LIMIT);
            return NULL;
        }
        n = new_node(d, is_object ? SHIRO_JSON_OBJECT : SHIRO_JSON_ARRAY);
        if (!n) return NULL;
        ++d->pos;
        skip_space(d);
        if (!at_end(d) && d->input[d->pos] == close) {
            ++d->pos;
            return n;
        }
        for (;;) {
            shiro_json *child;
            const char *key = NULL;
            skip_space(d);
            if (is_object) {
                size_t key_len;
                if (at_end(d) || d->input[d->pos] != '"') {
                    fail(d, SHIRO_E_MALFORMED);
                    return NULL;
                }
                ++d->pos;
                key = read_string(d, &key_len);
                if (!key) return NULL;
                skip_space(d);
                if (at_end(d) || d->input[d->pos] != ':') {
                    fail(d, SHIRO_E_MALFORMED);
                    return NULL;
                }
                ++d->pos;
            }
            child = parse_value(d, depth + 1);
            if (!child) return NULL;
            child->key = key;
            append_child(n, child);
            skip_space(d);
            if (at_end(d)) {
                fail(d, SHIRO_E_MALFORMED);
                return NULL;
            }
            if (d->input[d->pos] == ',') {
                ++d->pos;
                continue;
            }
            if (d->input[d->pos] == close) {
                ++d->pos;
                return n;
            }
            fail(d, SHIRO_E_MALFORMED);
            return NULL;
        }
    }
    if (c == '"') {
        size_t len;
        const char *s;
        n = new_node(d, SHIRO_JSON_STRING);
        if (!n) return NULL;
        ++d->pos;
        s = read_string(d, &len);
        if (!s) return NULL;
        n->text = s;
        n->text_len = len;
        return n;
    }
    if (c == 't' || c == 'f') {
        n = new_node(d, SHIRO_JSON_BOOL);
        if (!n) return NULL;
        if (c == 't' ? expect_word(d, "true") : expect_word(d, "false")) {
            n->flag = c == 't';
            return n;
        }
        fail(d, SHIRO_E_MALFORMED);
        return NULL;
    }
    if (c == 'n') {
        n = new_node(d, SHIRO_JSON_NULL);
        if (!n) return NULL;
        if (expect_word(d, "null")) return n;
        fail(d, SHIRO_E_MALFORMED);
        return NULL;
    }
    n = new_node(d, SHIRO_JSON_NUMBER);
    if (!n) return NULL;
    if (!read_number(d, n)) {
        fail(d, SHIRO_E_MALFORMED);
        return NULL;
    }
    return n;
}

shiro_status shiro_json_parse(const char *text, size_t len, shiro_json_doc **out) {
    shiro_json_doc *d;
    shiro_json *root;
    shiro_status status;
    if (out) *out = NULL;
    if (!out || (!text && len)) return SHIRO_E_ARG;
    if (len == 0) return SHIRO_E_MALFORMED;
    if (len > SHIRO_JSON_MAX_TEXT) return SHIRO_E_LIMIT;
    d = (shiro_json_doc *)calloc(1, sizeof(*d));
    if (!d) return SHIRO_E_NOMEM;
    /* every value takes at least one byte of the text, and a string needs one byte more than its text for the NUL */
    d->node_cap = len < SHIRO_JSON_MAX_NODES ? len : SHIRO_JSON_MAX_NODES;
    d->pool_cap = len + 8;
    d->nodes = (shiro_json *)calloc(d->node_cap, sizeof(shiro_json));
    d->pool = (char *)calloc(d->pool_cap, 1);
    if (!d->nodes || !d->pool) {
        shiro_json_free(d);
        return SHIRO_E_NOMEM;
    }
    d->input = text;
    d->input_len = len;
    root = parse_value(d, 0);
    if (root) {
        skip_space(d);
        if (!at_end(d)) fail(d, SHIRO_E_MALFORMED);
    }
    if (d->status != SHIRO_OK || !root) {
        status = d->status != SHIRO_OK ? d->status : SHIRO_E_MALFORMED;
        shiro_json_free(d);
        return status;
    }
    *out = d;
    return SHIRO_OK;
}

void shiro_json_free(shiro_json_doc *doc) {
    if (!doc) return;
    free(doc->nodes);
    free(doc->pool);
    free(doc);
}

const shiro_json *shiro_json_root(const shiro_json_doc *doc) {
    return doc && doc->node_count ? &doc->nodes[0] : NULL;
}

shiro_json_type shiro_json_kind(const shiro_json *node) {
    return node ? (shiro_json_type)node->kind : SHIRO_JSON_NULL;
}

const shiro_json *shiro_json_get(const shiro_json *object, const char *key) {
    const shiro_json *m, *found = NULL;
    if (!object || !key || object->kind != SHIRO_JSON_OBJECT) return NULL;
    for (m = object->first; m; m = m->next) {
        if (m->key && strcmp(m->key, key) == 0) found = m;
    }
    return found;
}

const shiro_json *shiro_json_first(const shiro_json *node) {
    return node ? node->first : NULL;
}

const shiro_json *shiro_json_next(const shiro_json *node) {
    return node ? node->next : NULL;
}

size_t shiro_json_count(const shiro_json *node) {
    return node ? node->count : 0;
}

const char *shiro_json_key(const shiro_json *node) {
    return node ? node->key : NULL;
}

const char *shiro_json_string(const shiro_json *node, size_t *len) {
    if (len) *len = 0;
    if (!node || node->kind != SHIRO_JSON_STRING) return NULL;
    if (len) *len = node->text_len;
    return node->text;
}

shiro_status shiro_json_int(const shiro_json *node, int64_t *out) {
    if (out) *out = 0;
    if (!node || !out || node->kind != SHIRO_JSON_NUMBER || !node->is_int) return SHIRO_E_MALFORMED;
    *out = node->integer;
    return SHIRO_OK;
}

shiro_status shiro_json_bool(const shiro_json *node, int *out) {
    if (out) *out = 0;
    if (!node || !out || node->kind != SHIRO_JSON_BOOL) return SHIRO_E_MALFORMED;
    *out = node->flag;
    return SHIRO_OK;
}

/* writing */

static void out_fail(shiro_json_out *o, shiro_status status) {
    if (o->status == SHIRO_OK) o->status = status;
}

static void out_raw(shiro_json_out *o, const char *text, size_t n) {
    if (o->status != SHIRO_OK) return;
    /* one byte stays free for the NUL */
    if (n >= o->cap - o->len) {
        out_fail(o, SHIRO_E_LIMIT);
        return;
    }
    memcpy(o->buf + o->len, text, n);
    o->len += n;
}

/* what comes before a value: nothing at the top, the key's colon already written in an object, a comma between array items */
static void out_value_start(shiro_json_out *o) {
    if (o->status != SHIRO_OK) return;
    if (o->depth == 0) {
        if (o->len != 0) out_fail(o, SHIRO_E_STATE);
        return;
    }
    if (o->is_object[o->depth - 1]) {
        if (!o->key_pending) {
            out_fail(o, SHIRO_E_STATE);
            return;
        }
        o->key_pending = 0;
    } else {
        if (o->member_count[o->depth - 1]) out_raw(o, ",", 1);
        if (o->member_count[o->depth - 1] < 255) ++o->member_count[o->depth - 1];
    }
}

static void out_quoted(shiro_json_out *o, const char *s) {
    static const char hex[] = "0123456789abcdef";
    const unsigned char *p = (const unsigned char *)s;
    out_raw(o, "\"", 1);
    for (; *p && o->status == SHIRO_OK; ++p) {
        if (*p == '"') out_raw(o, "\\\"", 2);
        else if (*p == '\\') out_raw(o, "\\\\", 2);
        else if (*p == '\n') out_raw(o, "\\n", 2);
        else if (*p == '\r') out_raw(o, "\\r", 2);
        else if (*p == '\t') out_raw(o, "\\t", 2);
        else if (*p < 0x20) {
            char esc[6] = {'\\', 'u', '0', '0', hex[*p >> 4], hex[*p & 15]};
            out_raw(o, esc, 6);
        } else {
            out_raw(o, (const char *)p, 1);
        }
    }
    out_raw(o, "\"", 1);
}

void shiro_json_out_init(shiro_json_out *out, char *buf, size_t cap) {
    memset(out, 0, sizeof(*out));
    out->buf = buf;
    out->cap = cap;
    if (!buf || cap < 2) out->status = SHIRO_E_ARG;
    else buf[0] = '\0';
}

static void out_open(shiro_json_out *o, int object) {
    out_value_start(o);
    if (o->status != SHIRO_OK) return;
    if (o->depth >= SHIRO_JSON_MAX_DEPTH) {
        out_fail(o, SHIRO_E_LIMIT);
        return;
    }
    out_raw(o, object ? "{" : "[", 1);
    o->is_object[o->depth] = (uint8_t)object;
    o->member_count[o->depth] = 0;
    ++o->depth;
}

void shiro_json_out_object(shiro_json_out *out) { out_open(out, 1); }
void shiro_json_out_array(shiro_json_out *out) { out_open(out, 0); }

void shiro_json_out_end(shiro_json_out *out) {
    if (out->status != SHIRO_OK) return;
    if (out->depth == 0 || out->key_pending) {
        out_fail(out, SHIRO_E_STATE);
        return;
    }
    --out->depth;
    out_raw(out, out->is_object[out->depth] ? "}" : "]", 1);
}

void shiro_json_out_key(shiro_json_out *out, const char *key) {
    if (out->status != SHIRO_OK) return;
    if (!key || out->depth == 0 || !out->is_object[out->depth - 1] || out->key_pending) {
        out_fail(out, SHIRO_E_STATE);
        return;
    }
    if (out->member_count[out->depth - 1]) out_raw(out, ",", 1);
    if (out->member_count[out->depth - 1] < 255) ++out->member_count[out->depth - 1];
    out_quoted(out, key);
    out_raw(out, ":", 1);
    out->key_pending = 1;
}

void shiro_json_out_string(shiro_json_out *out, const char *value) {
    out_value_start(out);
    if (!value) {
        out_fail(out, SHIRO_E_ARG);
        return;
    }
    out_quoted(out, value);
}

void shiro_json_out_int(shiro_json_out *out, int64_t value) {
    char text[24];
    int n = snprintf(text, sizeof(text), "%lld", (long long)value);
    out_value_start(out);
    if (n < 0 || (size_t)n >= sizeof(text)) {
        out_fail(out, SHIRO_E_LIMIT);
        return;
    }
    out_raw(out, text, (size_t)n);
}

void shiro_json_out_bool(shiro_json_out *out, int value) {
    out_value_start(out);
    out_raw(out, value ? "true" : "false", value ? 4 : 5);
}

shiro_status shiro_json_out_finish(shiro_json_out *out, size_t *len) {
    if (len) *len = 0;
    if (!out || !len) return SHIRO_E_ARG;
    if (out->status != SHIRO_OK) return out->status;
    if (out->depth != 0 || out->key_pending || out->len == 0) return SHIRO_E_STATE;
    out->buf[out->len] = '\0';
    *len = out->len;
    return SHIRO_OK;
}
