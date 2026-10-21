#include "shiro_packet.h"
#include "shiro_udp.h"
#include "test_util.h"
int main(void) {
    uint8_t packet[1300];
    size_t n = 0, length = 99;
    uint32_t source = 1, destination = 1;
    memset(packet, 0, sizeof(packet));
    CHECK_EQ_INT(shiro_udp_build(0xac100002, 1000, 0x08080808, 53, 1, (const uint8_t *)"dns", 3, packet, sizeof(packet), &n), SHIRO_OK);
    CHECK_EQ_INT(shiro_packet_ipv4(packet, n, &length, &source, &destination), 0);
    CHECK_EQ_INT(length, n);
    CHECK_EQ_INT(source, 0xac100002);
    CHECK_EQ_INT(destination, 0x08080808);
    CHECK_EQ_INT(shiro_packet_ipv4(packet, n + 8, &length, &source, &destination), 0);
    CHECK(shiro_packet_ipv4(packet, n - 1, &length, &source, &destination) != 0);
    CHECK_EQ_INT(length, 0);
    CHECK_EQ_INT(destination, 0);
    packet[0] = 0x44;
    CHECK(shiro_packet_ipv4(packet, n, &length, &source, &destination) != 0);
    packet[0] = 0x65;
    CHECK(shiro_packet_ipv4(packet, n, &length, &source, &destination) != 0);
    packet[0] = 0x45; packet[10] ^= 1;
    CHECK(shiro_packet_ipv4(packet, n, &length, &source, &destination) != 0);
    for (size_t i = 0; i < 20; ++i) CHECK(shiro_packet_ipv4(packet, i, &length, &source, &destination) != 0);
    return test_finish("packet");
}
