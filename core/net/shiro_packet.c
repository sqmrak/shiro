#include "shiro_packet.h"
int shiro_packet_ipv4(const uint8_t *packet, size_t available, size_t *length, uint32_t *source, uint32_t *destination) {
    if (length) *length = 0;
    if (source) *source = 0;
    if (destination) *destination = 0;
    if (!packet || !length || !source || !destination || available < 20 || (packet[0] >> 4) != 4) return -1;
    size_t header = (size_t)(packet[0] & 15) * 4;
    size_t total = ((size_t)packet[2] << 8) | packet[3];
    if (header < 20 || header > total || total > available || total > 1280) return -1;
    uint32_t sum = 0;
    for (size_t i = 0; i < header; i += 2) sum += ((uint32_t)packet[i] << 8) | packet[i + 1];
    while (sum >> 16) sum = (sum & 65535u) + (sum >> 16);
    if (sum != 65535u) return -1;
    *source = ((uint32_t)packet[12] << 24) | ((uint32_t)packet[13] << 16) | ((uint32_t)packet[14] << 8) | packet[15];
    *destination = ((uint32_t)packet[16] << 24) | ((uint32_t)packet[17] << 16) | ((uint32_t)packet[18] << 8) | packet[19];
    *length = total;
    return 0;
}
