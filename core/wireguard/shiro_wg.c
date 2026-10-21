#include "shiro_wg.h"

#include <string.h>

#include "shiro_blake2s.h"
#include "shiro_bytes.h"
#include "shiro_crypto.h"
#include "shiro_random.h"

#define TYPE_INITIATION 1u
#define TYPE_RESPONSE 2u
#define TYPE_DATA 4u
#define MAX_COUNTER ((uint64_t)1 << 60)

static const char construction[] = "Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s";
static const char identifier[] = "WireGuard v1 zx2c4 Jason@zx2c4.com";
static const char label_mac1[] = "mac1----";

static int all_zero(const uint8_t *p, size_t n) {
    uint8_t acc = 0;
    size_t i;
    for (i = 0; i < n; ++i) acc |= p[i];
    return acc == 0;
}

shiro_status shiro_wg_config_check(const shiro_wg_config *c) {
    if (!c) return SHIRO_E_ARG;
    if (all_zero(c->private_key, SHIRO_WG_KEY_LEN) || all_zero(c->peer_public, SHIRO_WG_KEY_LEN)) return SHIRO_E_ARG;
    if (c->junk_count > SHIRO_WG_MAX_JUNK || c->junk_max > SHIRO_WG_MAX_JUNK_LEN || (c->junk_count && c->junk_max < c->junk_min)) return SHIRO_E_ARG;
    if (c->s1 > SHIRO_WG_MAX_PREFIX || c->s2 > SHIRO_WG_MAX_PREFIX) return SHIRO_E_ARG;
    return SHIRO_OK;
}

/* hash of the parts joined */
static void hash2(uint8_t out[32], const void *a, size_t alen, const void *b, size_t blen) {
    shiro_blake2s_ctx ctx;
    (void)shiro_blake2s_init(&ctx, 32, NULL, 0);
    if (alen) shiro_blake2s_update(&ctx, a, alen);
    if (blen) shiro_blake2s_update(&ctx, b, blen);
    shiro_blake2s_final(&ctx, out);
}

/* HKDF with HMAC-BLAKE2s as the whitepaper has it: up to three outputs of 32 bytes. Any output may be null; out and key may overlap */
static void kdf(uint8_t *out1, uint8_t *out2, uint8_t *out3, const uint8_t key[32], const void *input, size_t input_len) {
    uint8_t prk[32], t1[32], t2[32], t3[32], buf[33];
    (void)shiro_blake2s_hmac(prk, key, 32, input, input_len);
    buf[0] = 1;
    (void)shiro_blake2s_hmac(t1, prk, 32, buf, 1);
    memcpy(buf, t1, 32);
    buf[32] = 2;
    (void)shiro_blake2s_hmac(t2, prk, 32, buf, 33);
    memcpy(buf, t2, 32);
    buf[32] = 3;
    (void)shiro_blake2s_hmac(t3, prk, 32, buf, 33);
    if (out1) memcpy(out1, t1, 32);
    if (out2) memcpy(out2, t2, 32);
    if (out3) memcpy(out3, t3, 32);
    shiro_wipe(prk, sizeof(prk));
    shiro_wipe(t1, sizeof(t1));
    shiro_wipe(t2, sizeof(t2));
    shiro_wipe(t3, sizeof(t3));
    shiro_wipe(buf, sizeof(buf));
}

static void handshake_nonce(uint8_t nonce[12]) {
    memset(nonce, 0, 12);
}

static void data_nonce(uint8_t nonce[12], uint64_t counter) {
    memset(nonce, 0, 4);
    shiro_put_u64le(nonce + 4, counter);
}

static shiro_status random_below(uint32_t bound, uint32_t *out) {
    uint64_t r;
    if (shiro_random_u64(&r) != SHIRO_OK) return SHIRO_E_CRYPTO;
    *out = bound ? (uint32_t)(r % bound) : 0;
    return SHIRO_OK;
}

static int hex_value(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

shiro_status shiro_wg_signature_render(const char *spec, uint32_t unix_seconds, uint8_t *out, size_t cap, size_t *len) {
    size_t n = 0;
    const char *p = spec;
    if (len) *len = 0;
    if (!spec || !out || !len) return SHIRO_E_ARG;
    for (;;) {
        char kind;
        while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') ++p;
        if (!*p) break;
        if (*p != '<') return SHIRO_E_MALFORMED;
        ++p;
        while (*p == ' ') ++p;
        kind = *p;
        if (kind >= 'A' && kind <= 'Z') kind = (char)(kind - 'A' + 'a');
        if (kind == 'b') {
            ++p;
            while (*p == ' ') ++p;
            if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) p += 2;
            while (hex_value(*p) >= 0) {
                int hi = hex_value(p[0]), lo = hex_value(p[1]);
                if (lo < 0) return SHIRO_E_MALFORMED;
                if (n >= cap) return SHIRO_E_LIMIT;
                out[n++] = (uint8_t)(hi << 4 | lo);
                p += 2;
            }
        } else if (kind == 'r') {
            unsigned count = 0;
            ++p;
            while (*p == ' ') ++p;
            if (*p < '0' || *p > '9') return SHIRO_E_MALFORMED;
            while (*p >= '0' && *p <= '9') {
                count = count * 10 + (unsigned)(*p - '0');
                if (count > SHIRO_WG_MAX_PREFIX) return SHIRO_E_MALFORMED;
                ++p;
            }
            if (count == 0) return SHIRO_E_MALFORMED;
            if (cap - n < count) return SHIRO_E_LIMIT;
            if (shiro_random(out + n, count) != SHIRO_OK) return SHIRO_E_CRYPTO;
            n += count;
        } else if (kind == 't' || kind == 'c') {
            if (cap - n < 4) return SHIRO_E_LIMIT;
            shiro_put_u32le(out + n, kind == 't' ? unix_seconds : 1u);
            n += 4;
            ++p;
        } else {
            return SHIRO_E_MALFORMED;
        }
        while (*p == ' ') ++p;
        if (*p != '>') return SHIRO_E_MALFORMED;
        ++p;
    }
    if (n == 0) return SHIRO_E_MALFORMED;
    *len = n;
    return SHIRO_OK;
}

/* the value a message type has on the wire */
static uint32_t wire_type(uint32_t standard, uint32_t configured) {
    return configured ? configured : standard;
}

/* the reserved bytes go in after the mac, as the clients that talk to WARP do it: the server does not count them in the mac */
static void put_header(uint8_t *out, uint32_t type, const uint8_t reserved[3], int has_reserved) {
    shiro_put_u32le(out, type);
    if (has_reserved) memcpy(out + 1, reserved, 3);
}

static int header_matches(const uint8_t *in, uint32_t expected, int has_reserved) {
    uint32_t actual = shiro_get_u32le(in);
    if (actual == expected) return 1;
    /* a peer that fills the reserved bytes leaves only the first byte of the type */
    if (has_reserved && expected < 256u) return (actual & 0xFFu) == expected;
    return 0;
}

shiro_status shiro_wg_handshake_begin(shiro_wg_handshake *hs, const shiro_wg_config *config, uint64_t unix_seconds, uint32_t nanos,
                                          shiro_wg_emit emit, void *context) {
    uint8_t message[SHIRO_WG_MAX_PREFIX + SHIRO_WG_INITIATION_LEN];
    uint8_t datagram[SHIRO_WG_MAX_JUNK_LEN > 2048 ? SHIRO_WG_MAX_JUNK_LEN : 2048];
    uint8_t *init = message;
    uint8_t shared[32], key[32], nonce[12], tag[SHIRO_WG_TAG_LEN], stamp[12], mac[16];
    uint8_t ephemeral_public[32];
    size_t prefix, i;
    shiro_status status;
    if (!hs || !config || !emit) return SHIRO_E_ARG;
    status = shiro_wg_config_check(config);
    if (status != SHIRO_OK) return status;
    memset(hs, 0, sizeof(*hs));
    hs->config = *config;
    status = shiro_x25519_public(config->private_key, hs->static_public);
    if (status != SHIRO_OK) return status;
    hash2(hs->mac1_key, label_mac1, sizeof(label_mac1) - 1, config->peer_public, 32);
    handshake_nonce(nonce);

    /* the random bytes that start the datagram are cut off by the peer, so they are drawn before the message is laid out behind them */
    prefix = config->s1;
    if (prefix && shiro_random(message, prefix) != SHIRO_OK) goto fail_crypto;
    init = message + prefix;
    memset(init, 0, SHIRO_WG_INITIATION_LEN);

    {
        uint32_t index;
        if (shiro_random(&index, sizeof(index)) != SHIRO_OK) goto fail_crypto;
        hs->local_index = index;
    }
    hash2(hs->chain, construction, sizeof(construction) - 1, NULL, 0);
    hash2(hs->hash, hs->chain, 32, identifier, sizeof(identifier) - 1);
    hash2(hs->hash, hs->hash, 32, config->peer_public, 32);

    if (shiro_random(hs->ephemeral_private, 32) != SHIRO_OK) goto fail_crypto;
    status = shiro_x25519_public(hs->ephemeral_private, ephemeral_public);
    if (status != SHIRO_OK) goto fail;
    kdf(hs->chain, NULL, NULL, hs->chain, ephemeral_public, 32);
    hash2(hs->hash, hs->hash, 32, ephemeral_public, 32);

    status = shiro_x25519_shared(hs->ephemeral_private, config->peer_public, shared);
    if (status != SHIRO_OK) goto fail;
    kdf(hs->chain, key, NULL, hs->chain, shared, 32);
    status = shiro_chacha20poly1305_seal(key, nonce, hs->hash, 32, hs->static_public, 32, init + 40, tag);
    if (status != SHIRO_OK) goto fail;
    memcpy(init + 72, tag, SHIRO_WG_TAG_LEN);
    hash2(hs->hash, hs->hash, 32, init + 40, 48);

    status = shiro_x25519_shared(config->private_key, config->peer_public, shared);
    if (status != SHIRO_OK) goto fail;
    kdf(hs->chain, key, NULL, hs->chain, shared, 32);
    /* TAI64N: seconds since 1970 plus 2^62 and 10 (the leap seconds), then the nanoseconds, both big endian */
    shiro_put_u64be(stamp, unix_seconds + 0x400000000000000aull);
    shiro_put_u32be(stamp + 8, nanos);
    status = shiro_chacha20poly1305_seal(key, nonce, hs->hash, 32, stamp, 12, init + 88, tag);
    if (status != SHIRO_OK) goto fail;
    memcpy(init + 100, tag, SHIRO_WG_TAG_LEN);
    hash2(hs->hash, hs->hash, 32, init + 88, 28);

    shiro_put_u32le(init, wire_type(TYPE_INITIATION, config->h1));
    shiro_put_u32le(init + 4, hs->local_index);
    memcpy(init + 8, ephemeral_public, 32);
    status = shiro_blake2s(mac, 16, hs->mac1_key, 32, init, 116);
    if (status != SHIRO_OK) goto fail;
    memcpy(init + 116, mac, 16);
    /* mac2 stays zero: the peer never asked for a cookie */
    put_header(init, wire_type(TYPE_INITIATION, config->h1), config->reserved, config->has_reserved);

    for (i = 0; i < SHIRO_WG_SIGNATURES; ++i) {
        size_t n = 0;
        if (!config->signature[i] || !config->signature[i][0]) continue;
        status = shiro_wg_signature_render(config->signature[i], (uint32_t)unix_seconds, datagram, sizeof(datagram), &n);
        if (status != SHIRO_OK) goto fail;
        emit(context, datagram, n);
    }
    for (i = 0; i < config->junk_count; ++i) {
        uint32_t extra, length;
        if (random_below((uint32_t)(config->junk_max - config->junk_min + 1), &extra) != SHIRO_OK) goto fail_crypto;
        length = config->junk_min + extra;
        if (length == 0) continue;
        if (shiro_random(datagram, length) != SHIRO_OK) goto fail_crypto;
        emit(context, datagram, length);
    }
    emit(context, message, prefix + SHIRO_WG_INITIATION_LEN);
    hs->pending = 1;
    shiro_wipe(shared, sizeof(shared));
    shiro_wipe(key, sizeof(key));
    return SHIRO_OK;
fail_crypto:
    status = SHIRO_E_CRYPTO;
fail:
    shiro_wipe(shared, sizeof(shared));
    shiro_wipe(key, sizeof(key));
    shiro_wg_handshake_clear(hs);
    return status;
}

shiro_status shiro_wg_handshake_finish(shiro_wg_handshake *hs, const uint8_t *packet, size_t len, uint64_t now_ms, shiro_wg_session *session) {
    const uint8_t *msg;
    uint8_t chain[32], hash[32], shared[32], tau[32], key[32], nonce[12], empty[1], sent[32], received[32];
    shiro_status status;
    size_t offset = 0;
    if (!hs || !packet || !session) return SHIRO_E_ARG;
    if (!hs->pending) return SHIRO_E_STATE;
    if (hs->config.s2 && len >= (size_t)hs->config.s2 + SHIRO_WG_RESPONSE_LEN) offset = hs->config.s2;
    if (len != offset + SHIRO_WG_RESPONSE_LEN) return SHIRO_E_MALFORMED;
    msg = packet + offset;
    if (!header_matches(msg, wire_type(TYPE_RESPONSE, hs->config.h2), hs->config.has_reserved)) return SHIRO_E_MALFORMED;
    if (shiro_get_u32le(msg + 8) != hs->local_index) return SHIRO_E_MALFORMED;

    memcpy(chain, hs->chain, 32);
    memcpy(hash, hs->hash, 32);
    handshake_nonce(nonce);
    kdf(chain, NULL, NULL, chain, msg + 12, 32);
    hash2(hash, hash, 32, msg + 12, 32);
    status = shiro_x25519_shared(hs->ephemeral_private, msg + 12, shared);
    if (status != SHIRO_OK) goto done;
    kdf(chain, NULL, NULL, chain, shared, 32);
    status = shiro_x25519_shared(hs->config.private_key, msg + 12, shared);
    if (status != SHIRO_OK) goto done;
    kdf(chain, NULL, NULL, chain, shared, 32);
    kdf(chain, tau, key, chain, hs->config.preshared, 32);
    hash2(hash, hash, 32, tau, 32);
    status = shiro_chacha20poly1305_open(key, nonce, hash, 32, NULL, 0, empty, msg + 44);
    if (status != SHIRO_OK) goto done;
    hash2(hash, hash, 32, msg + 44, SHIRO_WG_TAG_LEN);
    kdf(sent, received, NULL, chain, NULL, 0);

    memset(session, 0, sizeof(*session));
    memcpy(session->send_key, sent, 32);
    memcpy(session->recv_key, received, 32);
    session->local_index = hs->local_index;
    session->remote_index = shiro_get_u32le(msg + 4);
    session->data_type = wire_type(TYPE_DATA, hs->config.h4);
    memcpy(session->reserved, hs->config.reserved, 3);
    session->has_reserved = hs->config.has_reserved;
    session->born_ms = now_ms;
    session->active = 1;
    shiro_wg_handshake_clear(hs);
done:
    /* an answer that fails to authenticate ends this attempt; one that merely was for someone else did not get here */
    if (status != SHIRO_OK) shiro_wg_handshake_clear(hs);
    shiro_wipe(chain, sizeof(chain));
    shiro_wipe(shared, sizeof(shared));
    shiro_wipe(tau, sizeof(tau));
    shiro_wipe(key, sizeof(key));
    shiro_wipe(sent, sizeof(sent));
    shiro_wipe(received, sizeof(received));
    return status;
}

void shiro_wg_handshake_clear(shiro_wg_handshake *hs) {
    if (hs) shiro_wipe(hs, sizeof(*hs));
}

void shiro_wg_session_clear(shiro_wg_session *session) {
    if (session) shiro_wipe(session, sizeof(*session));
}

uint64_t shiro_wg_session_age_ms(const shiro_wg_session *session, uint64_t now_ms) {
    if (!session || !session->active || now_ms < session->born_ms) return 0;
    return now_ms - session->born_ms;
}

shiro_status shiro_wg_seal(shiro_wg_session *s, const uint8_t *plain, size_t len, uint8_t *out, size_t cap, size_t *out_len) {
    uint8_t nonce[12], tag[SHIRO_WG_TAG_LEN];
    size_t padded;
    shiro_status status;
    if (out_len) *out_len = 0;
    if (!s || !out || !out_len || (len && !plain)) return SHIRO_E_ARG;
    if (!s->active || s->send_counter >= MAX_COUNTER) return SHIRO_E_STATE;
    if (len > SHIRO_WG_MAX_PLAIN) return SHIRO_E_LIMIT;
    padded = (len + 15) & ~(size_t)15;
    if (cap < SHIRO_WG_HEADER_LEN + padded + SHIRO_WG_TAG_LEN) return SHIRO_E_LIMIT;
    memset(out, 0, SHIRO_WG_HEADER_LEN);
    put_header(out, s->data_type, s->reserved, s->has_reserved);
    shiro_put_u32le(out + 4, s->remote_index);
    shiro_put_u64le(out + 8, s->send_counter);
    if (len) memcpy(out + SHIRO_WG_HEADER_LEN, plain, len);
    if (padded > len) memset(out + SHIRO_WG_HEADER_LEN + len, 0, padded - len);
    data_nonce(nonce, s->send_counter);
    status = shiro_chacha20poly1305_seal(s->send_key, nonce, NULL, 0, out + SHIRO_WG_HEADER_LEN, padded, out + SHIRO_WG_HEADER_LEN, tag);
    if (status != SHIRO_OK) return status;
    memcpy(out + SHIRO_WG_HEADER_LEN + padded, tag, SHIRO_WG_TAG_LEN);
    ++s->send_counter;
    *out_len = SHIRO_WG_HEADER_LEN + padded + SHIRO_WG_TAG_LEN;
    return SHIRO_OK;
}

/* the sliding window of counters seen: bit n of the window says that recv_max - n arrived */
static int replay_seen(const shiro_wg_session *s, uint64_t counter) {
    uint64_t back;
    if (!s->received_any) return 0;
    if (counter > s->recv_max) return 0;
    back = s->recv_max - counter;
    if (back >= SHIRO_WG_REPLAY_BITS) return 1;
    return (s->recv_window[back / 64] >> (back % 64) & 1u) != 0;
}

static void replay_shift(shiro_wg_session *s, uint64_t by) {
    size_t words = SHIRO_WG_REPLAY_BITS / 64, i;
    if (by >= SHIRO_WG_REPLAY_BITS) {
        memset(s->recv_window, 0, sizeof(s->recv_window));
        return;
    }
    {
        size_t whole = (size_t)(by / 64);
        unsigned bits = (unsigned)(by % 64);
        for (i = words; i-- > 0;) {
            uint64_t v = i >= whole ? s->recv_window[i - whole] << bits : 0;
            if (bits && i > whole) v |= s->recv_window[i - whole - 1] >> (64 - bits);
            s->recv_window[i] = v;
        }
    }
}

static void replay_mark(shiro_wg_session *s, uint64_t counter) {
    if (!s->received_any) {
        memset(s->recv_window, 0, sizeof(s->recv_window));
        s->recv_window[0] = 1;
        s->recv_max = counter;
        s->received_any = 1;
        return;
    }
    if (counter > s->recv_max) {
        replay_shift(s, counter - s->recv_max);
        s->recv_window[0] |= 1u;
        s->recv_max = counter;
    } else {
        uint64_t back = s->recv_max - counter;
        s->recv_window[back / 64] |= (uint64_t)1 << (back % 64);
    }
}

shiro_status shiro_wg_open(shiro_wg_session *s, const uint8_t *packet, size_t len, uint8_t *plain, size_t cap, size_t *plain_len) {
    uint8_t nonce[12];
    uint64_t counter;
    size_t body;
    shiro_status status;
    if (plain_len) *plain_len = 0;
    if (!s || !packet || !plain || !plain_len) return SHIRO_E_ARG;
    if (!s->active) return SHIRO_E_STATE;
    if (len < SHIRO_WG_HEADER_LEN + SHIRO_WG_TAG_LEN || len > SHIRO_WG_MAX_DATAGRAM) return SHIRO_E_MALFORMED;
    if (!header_matches(packet, s->data_type, s->has_reserved)) return SHIRO_E_MALFORMED;
    if (shiro_get_u32le(packet + 4) != s->local_index) return SHIRO_E_MALFORMED;
    counter = shiro_get_u64le(packet + 8);
    if (counter >= MAX_COUNTER) return SHIRO_E_MALFORMED;
    if (replay_seen(s, counter)) return SHIRO_E_RETRY;
    body = len - SHIRO_WG_HEADER_LEN - SHIRO_WG_TAG_LEN;
    if (cap < body) return SHIRO_E_LIMIT;
    data_nonce(nonce, counter);
    status = shiro_chacha20poly1305_open(s->recv_key, nonce, NULL, 0, packet + SHIRO_WG_HEADER_LEN, body, plain, packet + SHIRO_WG_HEADER_LEN + body);
    if (status != SHIRO_OK) return status;
    /* only a datagram that authenticated moves the window, or a forged counter far ahead would lock the real ones out */
    replay_mark(s, counter);
    *plain_len = body;
    return SHIRO_OK;
}
