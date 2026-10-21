#include "shiro_routing.h"
#include <stdio.h>
#include <string.h>

int shiro_networks_parse(const char *text, shiro_network *out, size_t cap, size_t *count) {
    const char *p = text;
    size_t used = 0;
    if (count) *count = 0;
    if (!text || !out || !count || strlen(text) >= SHIRO_RULE_TEXT_MAX) return -1;
    while (*p) {
        unsigned a, b, c, d, bits;
        int n = 0;
        uint32_t ip, mask;
        while (*p == ' ' || *p == '\n' || *p == '\r' || *p == '\t' || *p == ',') ++p;
        if (!*p) break;
        if (*p < '0' || *p > '9' || sscanf(p, "%3u.%3u.%3u.%3u/%2u%n", &a, &b, &c, &d, &bits, &n) != 5 || n <= 0) return -1;
        if (a > 255 || b > 255 || c > 255 || d > 255 || bits < 2 || bits > 32 || used >= cap) return -1;
        p += n;
        if (*p && *p != ' ' && *p != '\n' && *p != '\r' && *p != '\t' && *p != ',') return -1;
        ip = (a << 24) | (b << 16) | (c << 8) | d;
        mask = UINT32_MAX << (32 - bits);
        if ((ip & mask) != ip || ip == 0 || a >= 224 || a == 127) return -1;
        for (size_t i = 0; i < used; ++i)
            if ((ip & out[i].mask) == out[i].network || (out[i].network & mask) == ip) return -1;
        out[used].network = ip;
        out[used].mask = mask;
        out[used++].prefix = bits;
    }
    *count = used;
    return 0;
}

int shiro_routing_parse(const char *direct, const char *block, shiro_routing *out) {
    shiro_routing parsed;
    if (!out) return -1;
    memset(out, 0, sizeof(*out));
    memset(&parsed, 0, sizeof(parsed));
    if (shiro_networks_parse(direct, parsed.direct, SHIRO_RULE_MAX, &parsed.direct_count) != 0 ||
        shiro_networks_parse(block, parsed.block, SHIRO_RULE_MAX, &parsed.block_count) != 0) return -1;
    /* a kernel bypass route must never take precedence over a block rule */
    for (size_t i = 0; i < parsed.direct_count; ++i)
        for (size_t j = 0; j < parsed.block_count; ++j)
            if ((parsed.direct[i].network & parsed.block[j].mask) == parsed.block[j].network ||
                (parsed.block[j].network & parsed.direct[i].mask) == parsed.direct[i].network) return -1;
    *out = parsed;
    return 0;
}

int shiro_routing_blocked(const shiro_routing *rules, uint32_t address) {
    if (!rules) return 0;
    for (size_t i = 0; i < rules->block_count; ++i)
        if ((address & rules->block[i].mask) == rules->block[i].network) return 1;
    return 0;
}
