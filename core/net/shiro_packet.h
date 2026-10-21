#ifndef SHIRO_PACKET_H
#define SHIRO_PACKET_H
#include <stddef.h>
#include <stdint.h>
/* wireguard pads plaintext to 16 bytes, ipv4 total length excludes that padding */
int shiro_packet_ipv4(const uint8_t *packet, size_t available, size_t *length, uint32_t *source, uint32_t *destination);
#endif
