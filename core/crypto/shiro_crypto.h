#ifndef SHIRO_CRYPTO_H
#define SHIRO_CRYPTO_H

#include <stddef.h>
#include <stdint.h>

#include "shiro_bytes.h"
#include "shiro_status.h"

/* openssl stays behind this boundary so protocol code builds against 1.1.1 and 3.x */

/* the WireGuard primitives: the curve25519 function of RFC 7748 and the AEAD of RFC 8439 with a 12 byte nonce */
#define SHIRO_X25519_LEN 32
#define SHIRO_CHACHA_KEY_LEN 32
#define SHIRO_CHACHA_NONCE_LEN 12
#define SHIRO_POLY1305_TAG_LEN 16

/* the public key of a private key (which need not be clamped) */
shiro_status shiro_x25519_public(const uint8_t priv[SHIRO_X25519_LEN], uint8_t pub[SHIRO_X25519_LEN]);
/* the shared secret; SHIRO_E_SECURITY when the peer key is a point of small order (the secret would be all zeros) */
shiro_status shiro_x25519_shared(const uint8_t priv[SHIRO_X25519_LEN], const uint8_t peer[SHIRO_X25519_LEN], uint8_t out[SHIRO_X25519_LEN]);

/* out holds len bytes and may be the same buffer as in; ad may be empty */
shiro_status shiro_chacha20poly1305_seal(const uint8_t key[SHIRO_CHACHA_KEY_LEN], const uint8_t nonce[SHIRO_CHACHA_NONCE_LEN],
                                             const uint8_t *ad, size_t ad_len, const uint8_t *in, size_t len, uint8_t *out,
                                             uint8_t tag[SHIRO_POLY1305_TAG_LEN]);
/* SHIRO_E_SECURITY when the tag does not match; out is wiped then */
shiro_status shiro_chacha20poly1305_open(const uint8_t key[SHIRO_CHACHA_KEY_LEN], const uint8_t nonce[SHIRO_CHACHA_NONCE_LEN],
                                             const uint8_t *ad, size_t ad_len, const uint8_t *in, size_t len, uint8_t *out,
                                             const uint8_t tag[SHIRO_POLY1305_TAG_LEN]);


#endif
