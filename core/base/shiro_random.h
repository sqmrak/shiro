#ifndef SHIRO_RANDOM_H
#define SHIRO_RANDOM_H

#include <stddef.h>
#include <stdint.h>

#include "shiro_status.h"

/* wireguard private keys and handshake nonces require kernel entropy */
shiro_status shiro_random(void *buf, size_t n);
shiro_status shiro_random_u64(uint64_t *out);

#endif
