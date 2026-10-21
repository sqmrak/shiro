#include "shiro_store.h"

#include <string.h>

#include "shiro_bytes.h"

static const uint8_t store_magic[4] = {'E', 'X', 'W', '1'};

static int identity_usable(const shiro_warp_identity *identity) {
    return identity->endpoint_ip != 0 && identity->address != 0 && identity->port_count >= 1 && identity->port_count <= SHIRO_WARP_MAX_PORTS;
}

shiro_status shiro_store_pack(const shiro_warp_identity *identity, uint8_t *out, size_t cap, size_t *len) {
    uint8_t *p = out;
    size_t i;
    if (len) *len = 0;
    if (!identity || !out || !len || !identity_usable(identity)) return SHIRO_E_ARG;
    if (cap < SHIRO_STORE_LEN) return SHIRO_E_LIMIT;
    memcpy(p, store_magic, sizeof(store_magic));
    p += sizeof(store_magic);
    memcpy(p, identity->private_key, SHIRO_WG_KEY_LEN);
    p += SHIRO_WG_KEY_LEN;
    memcpy(p, identity->peer_public, SHIRO_WG_KEY_LEN);
    p += SHIRO_WG_KEY_LEN;
    *p++ = identity->has_reserved ? 1u : 0u;
    memcpy(p, identity->reserved, sizeof(identity->reserved));
    p += sizeof(identity->reserved);
    shiro_put_u32le(p, identity->address);
    p += 4;
    shiro_put_u32le(p, identity->endpoint_ip);
    p += 4;
    *p++ = (uint8_t)identity->port_count;
    for (i = 0; i < SHIRO_WARP_MAX_PORTS; ++i) {
        uint16_t port = i < identity->port_count ? identity->ports[i] : 0;
        *p++ = (uint8_t)(port & 0xffu);
        *p++ = (uint8_t)(port >> 8);
    }
    *len = (size_t)(p - out);
    return SHIRO_OK;
}

shiro_status shiro_store_unpack(const uint8_t *data, size_t len, shiro_warp_identity *out) {
    const uint8_t *p = data;
    size_t i;
    if (!out) return SHIRO_E_ARG;
    memset(out, 0, sizeof(*out));
    if (!data || len != SHIRO_STORE_LEN || memcmp(p, store_magic, sizeof(store_magic)) != 0) return SHIRO_E_MALFORMED;
    p += sizeof(store_magic);
    memcpy(out->private_key, p, SHIRO_WG_KEY_LEN);
    p += SHIRO_WG_KEY_LEN;
    memcpy(out->peer_public, p, SHIRO_WG_KEY_LEN);
    p += SHIRO_WG_KEY_LEN;
    if (*p > 1u) goto malformed;
    out->has_reserved = *p++;
    memcpy(out->reserved, p, sizeof(out->reserved));
    p += sizeof(out->reserved);
    out->address = shiro_get_u32le(p);
    p += 4;
    out->endpoint_ip = shiro_get_u32le(p);
    p += 4;
    out->port_count = *p++;
    if (!identity_usable(out)) goto malformed;
    for (i = 0; i < SHIRO_WARP_MAX_PORTS; ++i) {
        uint16_t port = (uint16_t)(p[0] | (p[1] << 8));
        p += 2;
        /* a slot past the count holds zero, anything else means the file was not written by pack */
        if (i < out->port_count ? port == 0 : port != 0) goto malformed;
        out->ports[i] = port;
    }
    return SHIRO_OK;
malformed:
    shiro_wipe(out, sizeof(*out));
    return SHIRO_E_MALFORMED;
}
