#include "shiro_crypto.h"
#include <string.h>
#include <openssl/evp.h>

shiro_status shiro_x25519_public(const uint8_t priv[SHIRO_X25519_LEN], uint8_t pub[SHIRO_X25519_LEN]) {
    EVP_PKEY *key;
    size_t len = SHIRO_X25519_LEN;
    shiro_status status = SHIRO_E_CRYPTO;
    if (!priv || !pub) return SHIRO_E_ARG;
    key = EVP_PKEY_new_raw_private_key(EVP_PKEY_X25519, NULL, priv, SHIRO_X25519_LEN);
    if (!key) return SHIRO_E_CRYPTO;
    if (EVP_PKEY_get_raw_public_key(key, pub, &len) == 1 && len == SHIRO_X25519_LEN) status = SHIRO_OK;
    EVP_PKEY_free(key);
    return status;
}

shiro_status shiro_x25519_shared(const uint8_t priv[SHIRO_X25519_LEN], const uint8_t peer[SHIRO_X25519_LEN], uint8_t out[SHIRO_X25519_LEN]) {
    EVP_PKEY *own, *other;
    EVP_PKEY_CTX *ctx = NULL;
    size_t len = SHIRO_X25519_LEN;
    uint8_t zero = 0;
    size_t i;
    shiro_status status = SHIRO_E_CRYPTO;
    if (!priv || !peer || !out) return SHIRO_E_ARG;
    own = EVP_PKEY_new_raw_private_key(EVP_PKEY_X25519, NULL, priv, SHIRO_X25519_LEN);
    other = EVP_PKEY_new_raw_public_key(EVP_PKEY_X25519, NULL, peer, SHIRO_X25519_LEN);
    if (!own || !other) goto done;
    ctx = EVP_PKEY_CTX_new(own, NULL);
    if (!ctx || EVP_PKEY_derive_init(ctx) != 1 || EVP_PKEY_derive_set_peer(ctx, other) != 1) goto done;
    /* with two well formed keys the only way derive fails is a peer point of small order, which openssl refuses */
    if (EVP_PKEY_derive(ctx, out, &len) != 1) {
        status = SHIRO_E_SECURITY;
        goto done;
    }
    if (len != SHIRO_X25519_LEN) goto done;
    for (i = 0; i < SHIRO_X25519_LEN; ++i) zero |= out[i];
    if (zero == 0) {
        status = SHIRO_E_SECURITY;
        goto done;
    }
    status = SHIRO_OK;
done:
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(own);
    EVP_PKEY_free(other);
    if (status != SHIRO_OK) shiro_wipe(out, SHIRO_X25519_LEN);
    return status;
}

static shiro_status chacha_run(int encrypt, const uint8_t key[SHIRO_CHACHA_KEY_LEN], const uint8_t nonce[SHIRO_CHACHA_NONCE_LEN],
                                 const uint8_t *ad, size_t ad_len, const uint8_t *in, size_t len, uint8_t *out, uint8_t *tag) {
    EVP_CIPHER_CTX *ctx;
    uint8_t final_block[SHIRO_POLY1305_TAG_LEN];
    int outl = 0;
    shiro_status status = SHIRO_E_CRYPTO;
    if (!key || !nonce || (ad_len && !ad) || (len && (!in || !out)) || !tag || ad_len > 0x40000000u || len > 0x40000000u) return SHIRO_E_ARG;
    ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return SHIRO_E_NOMEM;
    if (EVP_CipherInit_ex(ctx, EVP_chacha20_poly1305(), NULL, key, nonce, encrypt) != 1) goto done;
    if (!encrypt && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_TAG, SHIRO_POLY1305_TAG_LEN, tag) != 1) goto done;
    if (ad_len && EVP_CipherUpdate(ctx, NULL, &outl, ad, (int)ad_len) != 1) goto done;
    if (len) {
        if (EVP_CipherUpdate(ctx, out, &outl, in, (int)len) != 1 || (size_t)outl != len) goto done;
    }
    if (EVP_CipherFinal_ex(ctx, final_block, &outl) != 1) {
        /* a decryption whose tag fails ends here, and nothing it produced may be used */
        status = encrypt ? SHIRO_E_CRYPTO : SHIRO_E_SECURITY;
        if (!encrypt && len) shiro_wipe(out, len);
        goto done;
    }
    if (encrypt && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_GET_TAG, SHIRO_POLY1305_TAG_LEN, tag) != 1) goto done;
    status = SHIRO_OK;
done:
    EVP_CIPHER_CTX_free(ctx);
    return status;
}

shiro_status shiro_chacha20poly1305_seal(const uint8_t key[SHIRO_CHACHA_KEY_LEN], const uint8_t nonce[SHIRO_CHACHA_NONCE_LEN],
                                             const uint8_t *ad, size_t ad_len, const uint8_t *in, size_t len, uint8_t *out,
                                             uint8_t tag[SHIRO_POLY1305_TAG_LEN]) {
    return chacha_run(1, key, nonce, ad, ad_len, in, len, out, tag);
}

shiro_status shiro_chacha20poly1305_open(const uint8_t key[SHIRO_CHACHA_KEY_LEN], const uint8_t nonce[SHIRO_CHACHA_NONCE_LEN],
                                             const uint8_t *ad, size_t ad_len, const uint8_t *in, size_t len, uint8_t *out,
                                             const uint8_t tag[SHIRO_POLY1305_TAG_LEN]) {
    uint8_t copy[SHIRO_POLY1305_TAG_LEN];
    shiro_status status;
    if (!tag) return SHIRO_E_ARG;
    memcpy(copy, tag, sizeof(copy));
    status = chacha_run(0, key, nonce, ad, ad_len, in, len, out, copy);
    return status;
}
