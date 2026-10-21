#ifndef SHIRO_TEST_SHIRO_RESPONDER_H
#define SHIRO_TEST_SHIRO_RESPONDER_H

#include "shiro_blake2s.h"
#include "shiro_bytes.h"
#include "shiro_crypto.h"
#include "shiro_random.h"
#include "shiro_wg.h"

#include <string.h>

/* the responder is written here from the whitepaper, so the initiator is checked against a second reading of the protocol and not against itself */

typedef struct responder {
    uint8_t priv[32], pub[32], peer_pub[32], psk[32];
    uint8_t chain[32], hash[32];
    uint32_t index, peer_index;
    uint8_t send_key[32], recv_key[32];
    uint64_t seen_stamp_sec;
    uint32_t seen_stamp_nanos;
} responder;

static void hash2(uint8_t out[32], const void *a, size_t al, const void *b, size_t bl) {
    shiro_blake2s_ctx c;
    shiro_blake2s_init(&c, 32, NULL, 0);
    shiro_blake2s_update(&c, a, al);
    if (bl) shiro_blake2s_update(&c, b, bl);
    shiro_blake2s_final(&c, out);
}

static void hkdf(uint8_t *o1, uint8_t *o2, uint8_t *o3, const uint8_t key[32], const void *in, size_t len) {
    uint8_t prk[32], t[3][32], buf[33];
    shiro_blake2s_hmac(prk, key, 32, in, len);
    buf[0] = 1;
    shiro_blake2s_hmac(t[0], prk, 32, buf, 1);
    memcpy(buf, t[0], 32);
    buf[32] = 2;
    shiro_blake2s_hmac(t[1], prk, 32, buf, 33);
    memcpy(buf, t[1], 32);
    buf[32] = 3;
    shiro_blake2s_hmac(t[2], prk, 32, buf, 33);
    if (o1) memcpy(o1, t[0], 32);
    if (o2) memcpy(o2, t[1], 32);
    if (o3) memcpy(o3, t[2], 32);
}

static void responder_init(responder *r, const uint8_t priv[32], const uint8_t peer_pub[32]) {
    memset(r, 0, sizeof(*r));
    memcpy(r->priv, priv, 32);
    shiro_x25519_public(priv, r->pub);
    memcpy(r->peer_pub, peer_pub, 32);
}

/* consumes an initiation of 148 bytes; fills the response (92 bytes). Returns 0 when everything checked out */
static int responder_answer(responder *r, const uint8_t *init, uint8_t *response, uint32_t type_init, uint32_t type_response) {
    uint8_t shared[32], key[32], nonce[12] = {0}, plain[32], mac1_key[32], mac[16], eph_priv[32], eph_pub[32], stamp[12], empty[1];
    uint8_t tag[16], tau[32];
    if ((shiro_get_u32le(init) & 0xFFu) != (type_init & 0xFFu)) return 1;
    /* mac1 covers the first 116 bytes with the reserved bytes still zero, which is what the initiator signed */
    {
        uint8_t copy[116];
        memcpy(copy, init, 116);
        /* the reserved bytes went in after the signature, so the signed header is the plain type value */
        shiro_put_u32le(copy, type_init);
        hash2(mac1_key, "mac1----", 8, r->pub, 32);
        shiro_blake2s(mac, 16, mac1_key, 32, copy, 116);
        if (memcmp(mac, init + 116, 16) != 0) return 2;
    }
    if (!(init[132] == 0 && !memcmp(init + 132, init + 133, 15))) return 3;
    hash2(r->chain, "Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s", strlen("Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s"), NULL, 0);
    hash2(r->hash, r->chain, 32, "WireGuard v1 zx2c4 Jason@zx2c4.com", strlen("WireGuard v1 zx2c4 Jason@zx2c4.com"));
    hash2(r->hash, r->hash, 32, r->pub, 32);
    hkdf(r->chain, NULL, NULL, r->chain, init + 8, 32);
    hash2(r->hash, r->hash, 32, init + 8, 32);
    if (shiro_x25519_shared(r->priv, init + 8, shared) != SHIRO_OK) return 4;
    hkdf(r->chain, key, NULL, r->chain, shared, 32);
    if (shiro_chacha20poly1305_open(key, nonce, r->hash, 32, init + 40, 32, plain, init + 72) != SHIRO_OK) return 5;
    if (memcmp(plain, r->peer_pub, 32) != 0) return 6;
    hash2(r->hash, r->hash, 32, init + 40, 48);
    if (shiro_x25519_shared(r->priv, plain, shared) != SHIRO_OK) return 7;
    hkdf(r->chain, key, NULL, r->chain, shared, 32);
    if (shiro_chacha20poly1305_open(key, nonce, r->hash, 32, init + 88, 12, stamp, init + 100) != SHIRO_OK) return 8;
    r->seen_stamp_sec = shiro_get_u64be(stamp) - 0x400000000000000aull;
    r->seen_stamp_nanos = shiro_get_u32be(stamp + 8);
    hash2(r->hash, r->hash, 32, init + 88, 28);
    r->peer_index = shiro_get_u32le(init + 4);

    shiro_random(eph_priv, 32);
    shiro_x25519_public(eph_priv, eph_pub);
    shiro_random(&r->index, sizeof(r->index));
    hkdf(r->chain, NULL, NULL, r->chain, eph_pub, 32);
    hash2(r->hash, r->hash, 32, eph_pub, 32);
    shiro_x25519_shared(eph_priv, init + 8, shared);
    hkdf(r->chain, NULL, NULL, r->chain, shared, 32);
    shiro_x25519_shared(eph_priv, plain, shared);
    hkdf(r->chain, NULL, NULL, r->chain, shared, 32);
    hkdf(r->chain, tau, key, r->chain, r->psk, 32);
    hash2(r->hash, r->hash, 32, tau, 32);
    shiro_chacha20poly1305_seal(key, nonce, r->hash, 32, empty, 0, empty, tag);
    hash2(r->hash, r->hash, 32, tag, 16);
    /* the responder receives with the first key and sends with the second */
    hkdf(r->recv_key, r->send_key, NULL, r->chain, NULL, 0);

    memset(response, 0, SHIRO_WG_RESPONSE_LEN);
    shiro_put_u32le(response, type_response);
    shiro_put_u32le(response + 4, r->index);
    shiro_put_u32le(response + 8, r->peer_index);
    memcpy(response + 12, eph_pub, 32);
    memcpy(response + 44, tag, 16);
    hash2(mac1_key, "mac1----", 8, plain, 32);
    shiro_blake2s(mac, 16, mac1_key, 32, response, 60);
    memcpy(response + 60, mac, 16);
    return 0;
}

#endif
