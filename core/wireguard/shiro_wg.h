#ifndef SHIRO_WG_H
#define SHIRO_WG_H

#include <stddef.h>
#include <stdint.h>

#include "shiro_status.h"

/* the initiating side of WireGuard (Noise IKpsk2 over curve25519, ChaCha20-Poly1305 and BLAKE2s) with the framing options of AmneziaWG: a random prefix on the
   first message, junk datagrams and signature datagrams ahead of it, other values for the message type field, and the three reserved header bytes that WARP
   reads as the client id. No sockets and no clock live here: the owner sends the datagrams, and passes the wall clock and the monotonic clock in */

#define SHIRO_WG_KEY_LEN 32
#define SHIRO_WG_INITIATION_LEN 148
#define SHIRO_WG_RESPONSE_LEN 92
#define SHIRO_WG_HEADER_LEN 16
#define SHIRO_WG_TAG_LEN 16
#define SHIRO_WG_REPLAY_BITS 256
/* the largest IP packet the tunnel carries */
#define SHIRO_WG_MAX_PLAIN 1500
#define SHIRO_WG_MAX_DATAGRAM (SHIRO_WG_HEADER_LEN + SHIRO_WG_MAX_PLAIN + 16 + SHIRO_WG_TAG_LEN)
#define SHIRO_WG_MAX_JUNK 32
#define SHIRO_WG_MAX_JUNK_LEN 1400
#define SHIRO_WG_MAX_PREFIX 1024
#define SHIRO_WG_SIGNATURES 5
/* the timers of the protocol (WireGuard whitepaper, section 6.1) */
#define SHIRO_WG_REKEY_AFTER_MS 120000u
#define SHIRO_WG_REJECT_AFTER_MS 180000u
#define SHIRO_WG_KEEPALIVE_MS 25000u

typedef struct shiro_wg_config {
    uint8_t private_key[SHIRO_WG_KEY_LEN];
    uint8_t peer_public[SHIRO_WG_KEY_LEN];
    uint8_t preshared[SHIRO_WG_KEY_LEN];      /* all zeros when the peer has none */
    uint8_t reserved[3];
    int has_reserved;
    uint16_t junk_count, junk_min, junk_max;
    uint16_t s1, s2;                            /* random bytes in front of the initiation, and in front of the response the peer sends */
    uint32_t h1, h2, h4;                        /* type field of the initiation, the response and the data message; 0 keeps 1, 2 and 4 */
    /* texts such as "<b 0x4142><r 8><t>" that become datagrams of their own; NULL or empty ones are skipped. They must outlive the handshake call */
    const char *signature[SHIRO_WG_SIGNATURES];
} shiro_wg_config;

/* the sizes and counts must be inside their limits and the keys must not be zero */
shiro_status shiro_wg_config_check(const shiro_wg_config *config);

/* a signature text turned into bytes: <b 0x..> literal bytes, <r N> N random bytes (up to 1024), <t> the unix time in seconds as 4 bytes little endian, <c> a
   counter field (4 bytes, value 1). SHIRO_E_MALFORMED for anything else, SHIRO_E_LIMIT when it does not fit in cap */
shiro_status shiro_wg_signature_render(const char *spec, uint32_t unix_seconds, uint8_t *out, size_t cap, size_t *len);

typedef struct shiro_wg_session {
    int active;
    uint8_t send_key[SHIRO_WG_KEY_LEN];
    uint8_t recv_key[SHIRO_WG_KEY_LEN];
    uint32_t local_index;
    uint32_t remote_index;
    uint32_t data_type;
    uint8_t reserved[3];
    int has_reserved;
    uint64_t send_counter;
    int received_any;
    uint64_t recv_max;
    uint64_t recv_window[SHIRO_WG_REPLAY_BITS / 64];
    uint64_t born_ms;                           /* the monotonic time the keys were made */
} shiro_wg_session;

typedef struct shiro_wg_handshake {
    int pending;
    shiro_wg_config config;
    uint8_t static_public[SHIRO_WG_KEY_LEN];
    uint8_t mac1_key[SHIRO_WG_KEY_LEN];
    uint8_t ephemeral_private[SHIRO_WG_KEY_LEN];
    uint8_t chain[SHIRO_WG_KEY_LEN];
    uint8_t hash[SHIRO_WG_KEY_LEN];
    uint32_t local_index;
} shiro_wg_handshake;

/* one datagram to send; called in order: the signatures, then the junk, then the initiation */
typedef void (*shiro_wg_emit)(void *context, const uint8_t *data, size_t len);

/* builds the initiation and hands every datagram to emit. unix_seconds and nanos stamp the message (TAI64N). SHIRO_E_CRYPTO when the system has no entropy,
   SHIRO_E_SECURITY when the peer key is a point of small order */
shiro_status shiro_wg_handshake_begin(shiro_wg_handshake *hs, const shiro_wg_config *config, uint64_t unix_seconds, uint32_t nanos,
                                          shiro_wg_emit emit, void *context);

/* a datagram that may be the answer. SHIRO_E_MALFORMED when it is not a response to this initiation (the owner keeps waiting and may pass other datagrams on
   to shiro_wg_open), SHIRO_E_SECURITY when it claims to be one and fails to authenticate (the handshake is dead then). On success session is filled in */
shiro_status shiro_wg_handshake_finish(shiro_wg_handshake *hs, const uint8_t *packet, size_t len, uint64_t now_ms, shiro_wg_session *session);

/* wipes keys and state */
void shiro_wg_handshake_clear(shiro_wg_handshake *hs);
void shiro_wg_session_clear(shiro_wg_session *session);

/* one IP packet (or none, for a keepalive) into a data datagram. The plain text is padded with zeros to a multiple of 16 bytes as the protocol does, so the IP
   total length field has to be what tells where the packet ends. out needs SHIRO_WG_MAX_DATAGRAM bytes. SHIRO_E_STATE when the session is not active or its
   counter is spent, SHIRO_E_LIMIT for a packet over SHIRO_WG_MAX_PLAIN */
shiro_status shiro_wg_seal(shiro_wg_session *session, const uint8_t *plain, size_t len, uint8_t *out, size_t cap, size_t *out_len);

/* a datagram of the peer. SHIRO_OK with *plain_len 0 is a keepalive. SHIRO_E_MALFORMED when it is not a data message for this session, SHIRO_E_RETRY for a
   counter that was seen or is too old, SHIRO_E_SECURITY when it does not authenticate. plain needs SHIRO_WG_MAX_DATAGRAM bytes */
shiro_status shiro_wg_open(shiro_wg_session *session, const uint8_t *packet, size_t len, uint8_t *plain, size_t cap, size_t *plain_len);

/* the age of the keys in milliseconds on the monotonic clock the owner uses */
uint64_t shiro_wg_session_age_ms(const shiro_wg_session *session, uint64_t now_ms);

#endif
