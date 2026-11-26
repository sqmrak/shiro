#ifndef SHIRO_TUNNEL_H
#define SHIRO_TUNNEL_H
#include "utun_device.h"
#include "utun_route.h"
#include "utun_dns.h"
#include "shiro_routing.h"
typedef struct {
    utun_device_t device;
    tun_plan_t plan;
    utun_dns_t dns;
    int applied;
    /* the physical interface the utun is bound to now, empty when unbound */
    char delegate[16];
} shiro_tunnel;
void shiro_tunnel_init(shiro_tunnel *tunnel);
int shiro_tunnel_open(shiro_tunnel *tunnel, uint32_t address, uint32_t endpoint, const shiro_routing *routing, const char *dns, char *error, size_t cap);
void shiro_tunnel_close(shiro_tunnel *tunnel);
/* follow wifi and cellular changes under an open tunnel. returns 1 and fills
   live when the binding changed, 0 when it did not, -1 when the kernel refused */
int shiro_tunnel_follow_network(shiro_tunnel *tunnel, char *live, size_t cap);
int shiro_tunnel_recover(void);
#endif
