#ifndef SHIRO_INTERFACE_H
#define SHIRO_INTERFACE_H
#include <stdint.h>
typedef struct {
 char ifname[32], ipv4[64], peer4[64], ipv6[64];
 int has_ipv4, has_ipv6;
 uint16_t mtu;
} shiro_interface;
int shiro_interface_up(const shiro_interface *plan);
#endif
