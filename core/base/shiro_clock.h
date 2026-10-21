#ifndef SHIRO_CLOCK_H
#define SHIRO_CLOCK_H

#include <stdint.h>

/* injected so protocol state machines run in tests without sleeping */
typedef struct shiro_clock {
    uint64_t (*realtime_ms)(void *ctx);
    uint64_t (*monotonic_ms)(void *ctx);
    void *ctx;
} shiro_clock;

extern const shiro_clock shiro_system_clock;

#endif
