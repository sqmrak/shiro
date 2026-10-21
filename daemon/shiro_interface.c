#include "shiro_interface.h"
#include <arpa/inet.h>
#include <stdio.h>
#include <string.h>
#include <net/if.h>
#include <netinet/in.h>
#include <sys/ioctl.h>
#include <sys/sockio.h>
#include <unistd.h>
#if defined(__APPLE__)
struct shiro_in6_addrlifetime {
    uint32_t expire;
    uint32_t preferred;
    uint32_t valid_lifetime;
    uint32_t preferred_lifetime;
};

struct shiro_in6_aliasreq {
    char ifra_name[IFNAMSIZ];
    struct sockaddr_in6 ifra_addr;
    struct sockaddr_in6 ifra_dstaddr;
    struct sockaddr_in6 ifra_prefixmask;
    int ifra_flags;
    struct shiro_in6_addrlifetime ifra_lifetime;
};

#define SHIRO_SIOCAIFADDR_IN6 _IOW('i', 26, struct shiro_in6_aliasreq)
#endif

#if defined(__APPLE__)
static int set_ifaddr4(int fd, const char *ifname, const char *ip, unsigned long request) {
    struct ifreq ifr;
    memset(&ifr, 0, sizeof ifr);
    snprintf(ifr.ifr_name, sizeof ifr.ifr_name, "%s", ifname);
    struct sockaddr_in *sin = (struct sockaddr_in *)&ifr.ifr_addr;
    sin->sin_len = sizeof *sin;
    sin->sin_family = AF_INET;
    if (inet_pton(AF_INET, ip, &sin->sin_addr) != 1) return -1;
    return ioctl(fd, request, &ifr);
}

static int set_ifaddr6(const char *ifname, const char *ip) {
    struct shiro_in6_aliasreq request;
    memset(&request, 0, sizeof request);
    snprintf(request.ifra_name, sizeof request.ifra_name, "%s", ifname);
    request.ifra_addr.sin6_len = sizeof request.ifra_addr;
    request.ifra_addr.sin6_family = AF_INET6;
    request.ifra_prefixmask.sin6_len = sizeof request.ifra_prefixmask;
    request.ifra_prefixmask.sin6_family = AF_INET6;
    memset(request.ifra_prefixmask.sin6_addr.s6_addr, 0xff,
           sizeof request.ifra_prefixmask.sin6_addr.s6_addr);
    request.ifra_lifetime.valid_lifetime = UINT32_MAX;
    request.ifra_lifetime.preferred_lifetime = UINT32_MAX;
    if (inet_pton(AF_INET6, ip, &request.ifra_addr.sin6_addr) != 1) return -1;
    int fd = socket(AF_INET6, SOCK_DGRAM, 0);
    if (fd < 0) return -1;
    int rc = ioctl(fd, SHIRO_SIOCAIFADDR_IN6, &request);
    close(fd);
    return rc;
}

int shiro_interface_up(const shiro_interface *plan) {
    if (!plan || !plan->has_ipv4) return -1;
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return -1;
    int ok = set_ifaddr4(fd, plan->ifname, plan->ipv4, SIOCSIFADDR) == 0 &&
             set_ifaddr4(fd, plan->ifname,
                         plan->peer4[0] ? plan->peer4 : plan->ipv4,
                         SIOCSIFDSTADDR) == 0;
    if (ok) {
        struct ifreq ifr;
        memset(&ifr, 0, sizeof ifr);
        snprintf(ifr.ifr_name, sizeof ifr.ifr_name, "%s", plan->ifname);
        struct sockaddr_in *mask = (struct sockaddr_in *)&ifr.ifr_addr;
        mask->sin_len = sizeof *mask;
        mask->sin_family = AF_INET;
        mask->sin_addr.s_addr = htonl(0xffffffffU);
        ok = ioctl(fd, SIOCSIFNETMASK, &ifr) == 0;
        if (ok && ioctl(fd, SIOCGIFFLAGS, &ifr) == 0) {
            ifr.ifr_flags |= IFF_UP | IFF_RUNNING;
            ok = ioctl(fd, SIOCSIFFLAGS, &ifr) == 0;
        }
        if (ok) {
            memset(&ifr, 0, sizeof ifr);
            snprintf(ifr.ifr_name, sizeof ifr.ifr_name, "%s", plan->ifname);
            ifr.ifr_mtu = plan->mtu;
            ok = ioctl(fd, SIOCSIFMTU, &ifr) == 0;
        }
    }
    close(fd);
    if (ok && plan->has_ipv6) ok = set_ifaddr6(plan->ifname, plan->ipv6) == 0;
    return ok ? 0 : -1;
}

#endif
