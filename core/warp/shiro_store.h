#ifndef SHIRO_STORE_H
#define SHIRO_STORE_H

#include <stddef.h>
#include <stdint.h>

#include "shiro_status.h"
#include "shiro_warp.h"

/* the bytes of the file the phone keeps its WARP account in: the private key, the server key and the addresses the registration returned. A file that
   was cut, written by another version or edited by hand is refused whole, because a tunnel built on half an identity fails far from the cause */

#define SHIRO_STORE_LEN 113u

/* SHIRO_E_ARG for an identity the tunnel could not use (no endpoint, no address, no port, more ports than the identity holds), SHIRO_E_LIMIT when cap is
   smaller than SHIRO_STORE_LEN */
shiro_status shiro_store_pack(const shiro_warp_identity *identity, uint8_t *out, size_t cap, size_t *len);

/* SHIRO_E_MALFORMED for a wrong size, magic or flag, or for the same identity that pack would refuse. out is zeroed on every failure */
shiro_status shiro_store_unpack(const uint8_t *data, size_t len, shiro_warp_identity *out);

#endif
