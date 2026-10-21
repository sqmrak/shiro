#ifndef SHIRO_WARP_H
#define SHIRO_WARP_H

#include <stddef.h>
#include <stdint.h>

#include "shiro_status.h"
#include "shiro_wg.h"

/* what Cloudflare WARP needs from a client that is not Cloudflare's: a key and an account made through the registration API, the endpoint that account is
   served from, and the framing options that get the handshake through a network which drops plain WireGuard. Nothing here touches the network */

#define SHIRO_WARP_MAX_PORTS 16
#define SHIRO_WARP_MTU 1280
#define SHIRO_WARP_INSTALL_ID_LEN 22
#define SHIRO_WARP_SIGNATURE_MAX 2048

typedef struct shiro_warp_identity {
    uint8_t private_key[SHIRO_WG_KEY_LEN];
    uint8_t peer_public[SHIRO_WG_KEY_LEN];
    uint8_t reserved[3];
    int has_reserved;
    uint32_t address;                       /* the IPv4 address of this phone inside the tunnel */
    uint32_t endpoint_ip;                   /* of the WireGuard server, host order */
    uint16_t ports[SHIRO_WARP_MAX_PORTS];
    size_t port_count;
} shiro_warp_identity;

/* RFC 4648 base64 with padding. decode is strict: no white space, no missing padding, no stray bits in the last character */
shiro_status shiro_base64_encode(const uint8_t *data, size_t len, char *out, size_t cap, size_t *out_len);
shiro_status shiro_base64_decode(const char *text, size_t text_len, uint8_t *out, size_t cap, size_t *out_len);

/* "a.b.c.d" and nothing else (no leading zeros, no spaces) into host order */
shiro_status shiro_warp_parse_ipv4(const char *text, size_t len, uint32_t *out);

/* a new private key (clamped, from the system's entropy) and its public key */
shiro_status shiro_warp_generate_key(uint8_t private_key[SHIRO_WG_KEY_LEN], uint8_t public_key[SHIRO_WG_KEY_LEN]);

/* the JSON the registration call posts. install_id is SHIRO_WARP_INSTALL_ID_LEN letters and digits drawn by the caller, tos the time as
   "2026-10-21T12:34:56.789Z". SHIRO_E_LIMIT when cap is too small */
shiro_status shiro_warp_registration_body(const uint8_t public_key[SHIRO_WG_KEY_LEN], const char *install_id, const char *tos, char *out, size_t cap,
                                              size_t *len);

/* the answer of the registration call. Every field that is used is checked for its type and its size, and the private key is only copied in. SHIRO_E_MALFORMED
   for an answer that is not what the API returns */
shiro_status shiro_warp_parse_registration(const char *json, size_t len, const uint8_t private_key[SHIRO_WG_KEY_LEN], shiro_warp_identity *out);

typedef struct shiro_warp_profile {
    char signature[2][SHIRO_WARP_SIGNATURE_MAX];
} shiro_warp_profile;

/* the WireGuard configuration for the identity with the framing WARP is reached with: four junk datagrams of 40 to 70 bytes, then two that look like SIP
   (an INVITE and a 100 Trying) before the initiation. The signature texts live in profile, which has to outlive the handshake call */
shiro_status shiro_warp_wg_config(const shiro_warp_identity *identity, shiro_warp_profile *profile, shiro_wg_config *out);

/* the server for an attempt: the first ones are the endpoint the account came with on each of its ports, the later ones are other WARP addresses
   and ports drawn at random. Never fails for a valid identity */
shiro_status shiro_warp_endpoint(const shiro_warp_identity *identity, unsigned attempt, uint32_t *ip, uint16_t *port);

#endif
