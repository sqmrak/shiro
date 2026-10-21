#ifndef SHIRO_ROUTING_H
#define SHIRO_ROUTING_H
#include <stddef.h>
#include <stdint.h>
#define SHIRO_RULE_MAX 32
#define SHIRO_RULE_TEXT_MAX 1024

typedef struct { uint32_t network, mask; unsigned prefix; } shiro_network;
typedef struct {
    shiro_network direct[SHIRO_RULE_MAX], block[SHIRO_RULE_MAX];
    size_t direct_count, block_count;
} shiro_routing;
int shiro_networks_parse(const char *text, shiro_network *out, size_t cap, size_t *count);
int shiro_routing_parse(const char *direct, const char *block, shiro_routing *out);
int shiro_routing_blocked(const shiro_routing *rules, uint32_t address);
#endif
