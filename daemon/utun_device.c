#include "utun_device.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

void utun_device_init(utun_device_t *device) {
    if (!device) return;
    memset(device, 0, sizeof *device);
    device->fd = -1;
}

const char *utun_device_status_name(utun_device_status_t status) {
    switch (status) {
    case UTUN_DEVICE_OK:          return "ok";
    case UTUN_DEVICE_AGAIN:       return "again";
    case UTUN_DEVICE_EOF:         return "eof";
    case UTUN_DEVICE_ERR_ARG:     return "arg";
    case UTUN_DEVICE_ERR_UNSUPPORTED: return "unsupported";
    case UTUN_DEVICE_ERR_CONTROL: return "control";
    case UTUN_DEVICE_ERR_OPEN:    return "open";
    case UTUN_DEVICE_ERR_CONNECT: return "connect";
    case UTUN_DEVICE_ERR_NAME:    return "name";
    case UTUN_DEVICE_ERR_NONBLOCK: return "nonblock";
    case UTUN_DEVICE_ERR_IO:      return "io";
    case UTUN_DEVICE_ERR_SHORT:   return "short";
    }
    return "unknown";
}

static int set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) return -1;
    return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

utun_device_status_t utun_device_adopt(utun_device_t *device, int fd,
                                       const char *ifname) {
    if (!device || fd < 0 || device->fd >= 0) return UTUN_DEVICE_ERR_ARG;
    if (set_nonblocking(fd) != 0) {
        device->last_errno = errno;
        return UTUN_DEVICE_ERR_NONBLOCK;
    }
    device->fd = fd;
    snprintf(device->ifname, sizeof device->ifname, "%s", ifname ? ifname : "");
    return UTUN_DEVICE_OK;
}

utun_device_status_t utun_device_read_frame(utun_device_t *device, uint8_t *frame,
                                            size_t cap, size_t *frame_len) {
    if (frame_len) *frame_len = 0;
    if (!device || !frame || !frame_len || cap == 0) return UTUN_DEVICE_ERR_ARG;
    if (device->fd < 0) return UTUN_DEVICE_ERR_ARG;

    ssize_t got;
    do {
        got = read(device->fd, frame, cap);
    } while (got < 0 && errno == EINTR);

    if (got < 0) {
        device->last_errno = errno;
        if (errno == EAGAIN || errno == EWOULDBLOCK) return UTUN_DEVICE_AGAIN;
        return UTUN_DEVICE_ERR_IO;
    }
    if (got == 0) return UTUN_DEVICE_EOF;

    *frame_len = (size_t)got;
    ++device->frames_in;
    device->bytes_in += (uint64_t)got;
    return UTUN_DEVICE_OK;
}

utun_device_status_t utun_device_write_frame(utun_device_t *device,
                                             const uint8_t *frame, size_t len) {
    if (!device || !frame || len == 0) return UTUN_DEVICE_ERR_ARG;
    if (device->fd < 0) return UTUN_DEVICE_ERR_ARG;

    ssize_t wrote;
    do {
        wrote = write(device->fd, frame, len);
    } while (wrote < 0 && errno == EINTR);

    if (wrote < 0) {
        device->last_errno = errno;
        device->last_block_nobufs = errno == ENOBUFS;
        /* ENOBUFS is the kernel running out of buffers for the moment, which
           darwin reports on a full datagram queue instead of EAGAIN */
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == ENOBUFS)
            return UTUN_DEVICE_AGAIN;
        return UTUN_DEVICE_ERR_IO;
    }
    if ((size_t)wrote != len) {
        device->last_errno = 0;
        return UTUN_DEVICE_ERR_SHORT;
    }

    ++device->frames_out;
    device->bytes_out += len;
    return UTUN_DEVICE_OK;
}

/* a link-local or loopback address does not mean the link carries traffic */
int utun_device_address_usable(const struct sockaddr *sa) {
    if (!sa) return 0;
    if (sa->sa_family == AF_INET) {
        uint32_t ip = ntohl(((const struct sockaddr_in *)sa)->sin_addr.s_addr);
        return ip != 0 && (ip & 0xff000000U) != 0x7f000000U && (ip & 0xffff0000U) != 0xa9fe0000U;
    }
    if (sa->sa_family == AF_INET6) {
        const uint8_t *a = ((const struct sockaddr_in6 *)sa)->sin6_addr.s6_addr;
        int low = 1;
        for (int i = 0; i < 15; ++i) if (a[i]) { low = 0; break; }
        if (low && a[15] <= 1) return 0;
        return !(a[0] == 0xfe && (a[1] & 0xc0) == 0x80);
    }
    return 0;
}

void utun_device_close(utun_device_t *device) {
    if (!device || device->fd < 0) return;
    close(device->fd);
    device->fd = -1;
}

#if defined(__APPLE__)

/* the ios 5 sdk net/if.h uses struct sockaddr without including it */
#include <sys/socket.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <sys/ioctl.h>

#ifndef AF_SYSTEM
#define AF_SYSTEM 32
#endif
#ifndef PF_SYSTEM
#define PF_SYSTEM AF_SYSTEM
#endif
#ifndef SYSPROTO_CONTROL
#define SYSPROTO_CONTROL 2
#endif
#ifndef AF_SYS_CONTROL
#define AF_SYS_CONTROL 2
#endif
#ifndef UTUN_OPT_IFNAME
#define UTUN_OPT_IFNAME 2
#endif
#ifndef UTUN_OPT_SET_DELEGATE_INTERFACE
#define UTUN_OPT_SET_DELEGATE_INTERFACE 15
#endif

#define UTUN_KCTL_NAME_MAX 96

struct utun_ctl_info {
    unsigned int ctl_id;
    char ctl_name[UTUN_KCTL_NAME_MAX];
};

/* declared locally because the iphoneos 5 sdk does not ship sys/kern_control.h
   in a form both slices agree on */
struct utun_sockaddr_ctl {
    unsigned char  sc_len;
    unsigned char  sc_family;
    unsigned short ss_sysaddr;
    unsigned int   sc_id;
    unsigned int   sc_unit;
    unsigned int   sc_reserved[5];
};

#ifndef UTUN_CTLIOCGINFO
#define UTUN_CTLIOCGINFO _IOWR('N', 3, struct utun_ctl_info)
#endif

static int control_id(unsigned int *out_id, int *out_errno) {
    struct utun_ctl_info info;
    memset(&info, 0, sizeof info);
    strncpy(info.ctl_name, "com.apple.net.utun_control", sizeof info.ctl_name - 1);
    int fd = socket(PF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL);
    if (fd < 0) {
        *out_errno = errno;
        return -1;
    }
    if (ioctl(fd, UTUN_CTLIOCGINFO, &info) != 0) {
        *out_errno = errno;
        close(fd);
        return -1;
    }
    close(fd);
    *out_id = info.ctl_id;
    return 0;
}

/* one attempt on a fresh socket: a refused unit must not leave a half
   connected descriptor behind for the next try */
static int connect_unit(unsigned int ctl_id, unsigned int sc_unit, int *out_errno) {
    int fd = socket(PF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL);
    if (fd < 0) {
        *out_errno = errno;
        return -1;
    }
    struct utun_sockaddr_ctl addr;
    memset(&addr, 0, sizeof addr);
    addr.sc_len = sizeof addr;
    addr.sc_family = AF_SYSTEM;
    addr.ss_sysaddr = AF_SYS_CONTROL;
    addr.sc_id = ctl_id;
    addr.sc_unit = sc_unit;
    if (connect(fd, (struct sockaddr *)&addr, sizeof addr) != 0) {
        *out_errno = errno;
        close(fd);
        return -1;
    }
    return fd;
}

utun_device_status_t utun_device_open(utun_device_t *device, unsigned first_unit) {
    if (!device) return UTUN_DEVICE_ERR_ARG;
    if (device->fd >= 0) return UTUN_DEVICE_ERR_ARG;

    unsigned int ctl_id = 0;
    int saved = 0;
    if (control_id(&ctl_id, &saved) != 0) {
        device->last_errno = saved;
        return UTUN_DEVICE_ERR_CONTROL;
    }

    int fd = -1;
    unsigned claimed = 0;
    /* sc_unit is the interface number plus one, and zero asks the kernel to
       pick. the automatic pick is tried first, then each unit in range */
    if (first_unit == 0) {
        fd = connect_unit(ctl_id, 0, &saved);
        if (fd >= 0) claimed = 0;
    }
    for (unsigned unit = first_unit; fd < 0 && unit < first_unit + UTUN_DEVICE_MAX_UNITS;
         ++unit) {
        fd = connect_unit(ctl_id, unit + 1, &saved);
        if (fd >= 0) claimed = unit;
    }
    if (fd < 0) {
        device->last_errno = saved;
        return UTUN_DEVICE_ERR_CONNECT;
    }

    char ifname[sizeof device->ifname];
    memset(ifname, 0, sizeof ifname);
    socklen_t got = (socklen_t)sizeof ifname;
    if (getsockopt(fd, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, ifname, &got) != 0 ||
        !ifname[0]) {
        device->last_errno = errno;
        close(fd);
        return UTUN_DEVICE_ERR_NAME;
    }
    ifname[sizeof ifname - 1] = '\0';

    utun_device_status_t adopted = utun_device_adopt(device, fd, ifname);
    if (adopted != UTUN_DEVICE_OK) {
        close(fd);
        return adopted;
    }
    device->unit = claimed;
    return UTUN_DEVICE_OK;
}

int utun_device_set_delegate(utun_device_t *device, const char *physical_ifname) {
    if (!device || device->fd < 0) {
        errno = EBADF;
        return -1;
    }
    size_t len = physical_ifname ? strlen(physical_ifname) : 0;
    if (len >= IFNAMSIZ) {
        errno = EINVAL;
        return -1;
    }
    return setsockopt(device->fd, SYSPROTO_CONTROL, UTUN_OPT_SET_DELEGATE_INTERFACE,
                      physical_ifname ? physical_ifname : "", (socklen_t)len);
}

int utun_device_live_physical(char *out, size_t cap) {
    if (!out || cap == 0) return -1;
    out[0] = '\0';
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0) return -1;
    char cell[IFNAMSIZ] = "";
    int wifi = 0;
    for (const struct ifaddrs *it = list; it && !wifi; it = it->ifa_next) {
        if (!it->ifa_name || !it->ifa_addr) continue;
        if ((it->ifa_flags & (IFF_UP | IFF_RUNNING)) != (IFF_UP | IFF_RUNNING)) continue;
        if (!utun_device_address_usable(it->ifa_addr)) continue;
        if (strcmp(it->ifa_name, "en0") == 0) wifi = 1;
        else if (!cell[0] && strncmp(it->ifa_name, "pdp_ip", 6) == 0)
            snprintf(cell, sizeof cell, "%s", it->ifa_name);
    }
    freeifaddrs(list);
    snprintf(out, cap, "%s", wifi ? "en0" : cell);
    return 0;
}

#else

utun_device_status_t utun_device_open(utun_device_t *device, unsigned first_unit) {
    (void)first_unit;
    if (!device) return UTUN_DEVICE_ERR_ARG;
    device->last_errno = ENOTSUP;
    return UTUN_DEVICE_ERR_UNSUPPORTED;
}

int utun_device_set_delegate(utun_device_t *device, const char *physical_ifname) {
    (void)device;
    (void)physical_ifname;
    errno = ENOTSUP;
    return -1;
}

int utun_device_live_physical(char *out, size_t cap) {
    if (out && cap) out[0] = '\0';
    errno = ENOTSUP;
    return -1;
}

#endif
