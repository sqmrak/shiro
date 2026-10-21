#include "shiro_tunnel.h"
#include "shiro_interface.h"
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#define JOURNAL "/var/root/Library/Shiro/routes"

void shiro_tunnel_init(shiro_tunnel *tunnel) {
    memset(tunnel, 0, sizeof(*tunnel));
    utun_device_init(&tunnel->device);
    utun_dns_init(&tunnel->dns);
}

static int save_plan(const tun_plan_t *plan) {
    char data[16384];
    int n = tun_plan_save_leftovers(plan, data, sizeof(data));
    if (n < 0) return -1;
    int fd = open(JOURNAL ".tmp", O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0600);
    if (fd < 0) return -1;
    size_t done = 0;
    while (done < (size_t)n) {
        ssize_t written = write(fd, data + done, (size_t)n - done);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) { close(fd); unlink(JOURNAL ".tmp"); return -1; }
        done += (size_t)written;
    }
    int rc = fsync(fd);
    if (close(fd) != 0) rc = -1;
    if (rc == 0) rc = rename(JOURNAL ".tmp", JOURNAL);
    if (rc != 0) unlink(JOURNAL ".tmp");
    return rc;
}

int shiro_tunnel_recover(void) {
    char text[16385];
    int fd = open(JOURNAL, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return errno == ENOENT ? 0 : -1;
    size_t used = 0;
    while (used < sizeof(text)) {
        ssize_t n = read(fd, text + used, sizeof(text) - used);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) { close(fd); return -1; }
        if (!n) break;
        used += (size_t)n;
    }
    close(fd);
    tun_plan_t plan;
    utun_route_result_t result;
    if (used == sizeof(text) || tun_plan_load_leftovers(text, used, &plan) != TUN_PLAN_OK) return -1;
    if (utun_route_revert(&plan, utun_route_system_executor(), &result) != UTUN_ROUTE_OK) {
        fprintf(stderr, "shiro: route recovery: %s\n", result.rollback_message);
        return -1;
    }
    return unlink(JOURNAL);
}

void shiro_tunnel_close(shiro_tunnel *tunnel) {
    utun_dns_withdraw(&tunnel->dns);
    if (tunnel->applied) {
        utun_route_result_t result;
        if (utun_route_revert(&tunnel->plan, utun_route_system_executor(), &result) == UTUN_ROUTE_OK) {
            if (unlink(JOURNAL) != 0 && errno != ENOENT) perror("shiro: remove route journal");
        } else fprintf(stderr, "shiro: route cleanup: %s\n", result.rollback_message);
        tunnel->applied = 0;
    }
    utun_device_close(&tunnel->device);
}

int shiro_tunnel_open(shiro_tunnel *tunnel, uint32_t address, uint32_t endpoint, const shiro_routing *routing, const char *dns, char *error, size_t cap) {
    if (!tunnel || !routing || !dns || !error || !cap || !address || !endpoint) return -1;
    error[0] = '\0';
    if (tunnel->device.fd >= 0 || tunnel->applied) {
        snprintf(error, cap, "the previous tunnel is still open"); return -1;
    }
    if (shiro_tunnel_recover() != 0) {
        snprintf(error, cap, "the previous routes could not be removed"); return -1;
    }
    tun_plan_input_t input;
    utun_route_path_t path;
    utun_route_error_t route_error;
    shiro_interface interface;
    uint32_t endpoint_be = htonl(endpoint), address_be = htonl(address);
    memset(&input, 0, sizeof(input));
    memset(&interface, 0, sizeof(interface));
    if (utun_route_system_path((uint8_t *)&endpoint_be, 4, &path, &route_error) != 0) {
        snprintf(error, cap, "%s", route_error.message);
        return -1;
    }
    if (strncmp(path.ifname, "utun", 4) == 0 || strncmp(path.ifname, "ipsec", 5) == 0) {
        snprintf(error, cap, "another VPN owns the physical route, disconnect it first");
        return -1;
    }
    if (utun_device_open(&tunnel->device, 0) != UTUN_DEVICE_OK) {
        snprintf(error, cap, "cannot open utun: %s (errno %d)", utun_device_status_name(UTUN_DEVICE_ERR_CONNECT), tunnel->device.last_errno);
        return -1;
    }
    snprintf(input.ifname, sizeof(input.ifname), "%s", tunnel->device.ifname);
    snprintf(input.physical_ifname, sizeof(input.physical_ifname), "%s", path.ifname);
    input.route_ipv4 = input.enable_ipv6 = 1;
    input.have_gateway4 = path.via_gateway;
    memcpy(input.gateway4, path.gateway, 4);
    input.endpoint_count = 1;
    input.endpoints[0].address_len = 4;
    memcpy(input.endpoints[0].address, &endpoint_be, 4);
    for (size_t i = 0; i < routing->direct_count; ++i) {
        tun_plan_cidr_t *cidr = &input.direct_policies[input.direct_policy_count++];
        uint32_t be = htonl(routing->direct[i].network);
        memcpy(cidr->address, &be, 4);
        cidr->address_len = 4;
        cidr->prefix = (uint8_t)routing->direct[i].prefix;
    }
    if (tun_plan_build(&input, &tunnel->plan) != TUN_PLAN_OK) {
        snprintf(error, cap, "cannot build the route plan");
        goto fail;
    }
    snprintf(interface.ifname, sizeof(interface.ifname), "%s", input.ifname);
    inet_ntop(AF_INET, &address_be, interface.ipv4, sizeof(interface.ipv4));
    snprintf(interface.peer4, sizeof(interface.peer4), "%s", interface.ipv4);
    snprintf(interface.ipv6, sizeof(interface.ipv6), "fd00:5348::1");
    interface.has_ipv4 = interface.has_ipv6 = 1;
    interface.mtu = 1280;
    if (shiro_interface_up(&interface) != 0) {
        snprintf(error, cap, "cannot configure %s (errno %d)", input.ifname, errno);
        goto fail;
    }
    utun_route_result_t result;
    if (utun_route_apply_verified(&tunnel->plan, utun_route_system_executor(), &result) != UTUN_ROUTE_OK) {
        snprintf(error, cap, "%s", result.failed_message);
        if (result.rollback_failures) {
            fprintf(stderr, "shiro: rollback: %s\n", result.rollback_message);
            if (save_plan(&tunnel->plan) != 0) perror("shiro: save failed rollback");
        }
        goto fail;
    }
    tunnel->applied = 1;
    if (save_plan(&tunnel->plan) != 0) {
        snprintf(error, cap, "cannot save the route recovery journal");
        goto fail;
    }
    if (utun_dns_publish(&tunnel->dns, input.ifname, interface.ipv4, interface.peer4, dns, error, cap) != 0) goto fail;
    return 0;
fail:
    shiro_tunnel_close(tunnel);
    return -1;
}
