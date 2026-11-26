#include "utun_device.h"
#include "test_util.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <sys/socket.h>

static int v4(const char *text) {
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    CHECK(inet_pton(AF_INET, text, &sa.sin_addr) == 1);
    return utun_device_address_usable((const struct sockaddr *)&sa);
}

static int v6(const char *text) {
    struct sockaddr_in6 sa;
    memset(&sa, 0, sizeof sa);
    sa.sin6_family = AF_INET6;
    CHECK(inet_pton(AF_INET6, text, &sa.sin6_addr) == 1);
    return utun_device_address_usable((const struct sockaddr *)&sa);
}

int main(void) {
    /* the live link is chosen by these: a link-local address alone is not a link that carries traffic */
    CHECK(v4("192.168.0.122") && v4("10.20.30.40") && v4("100.64.1.2"));
    CHECK(!v4("0.0.0.0") && !v4("127.0.0.1") && !v4("169.254.7.9"));
    CHECK(v6("2001:db8::1") && v6("fd00::5"));
    CHECK(!v6("::") && !v6("::1") && !v6("fe80::1") && !v6("febf::1"));
    CHECK(v6("fec0::1"));
    CHECK(!utun_device_address_usable(NULL));
    struct sockaddr sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_family = AF_UNIX;
    CHECK(!utun_device_address_usable(&sa));

    utun_device_t closed;
    utun_device_init(&closed);
    errno = 0;
    CHECK(utun_device_set_delegate(&closed, "en0") == -1 && errno != 0);
    CHECK(utun_device_set_delegate(NULL, "en0") == -1);

    char name[16] = "x";
    int rc = utun_device_live_physical(name, sizeof name);
    /* a host without darwin interface names has no live link to report */
    CHECK(rc == 0 || rc == -1);
    CHECK(rc != -1 || name[0] == '\0');
    CHECK(utun_device_live_physical(NULL, 0) == -1);
    if (g_failures) return 1;
    puts("test_utun_device ok");
    return 0;
}
