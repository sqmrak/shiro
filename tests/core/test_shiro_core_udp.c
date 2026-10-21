#include "shiro_clock.h"
#include "shiro_core.h"
#include "shiro_udp.h"
#include "shiro_responder.h"
#include "test_util.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <sys/socket.h>
#include <unistd.h>

#define CLIENT_ADDRESS 0xac100002u
#define PEER_ADDRESS 0x08080808u
#define PEER_PORT 3478

/* a WireGuard server that lives in the test: it answers the handshake with the whitepaper responder of shiro_responder.h and then speaks the data messages
   through a session of the same library with the keys turned round */
typedef struct server {
    int fd;
    uint16_t port;
    responder r;
    shiro_wg_session session;
    struct sockaddr_in client;
    socklen_t client_len;
    int have_session;
    int initiations;
} server;

typedef struct watch {
    pthread_mutex_t lock;
    shiro_state state;
    shiro_status reason;
} watch;

static void on_state(void *context, shiro_state state, shiro_status reason) {
    watch *w = (watch *)context;
    pthread_mutex_lock(&w->lock);
    w->state = state;
    w->reason = reason;
    pthread_mutex_unlock(&w->lock);
}

static shiro_state watched(watch *w) {
    shiro_state s;
    pthread_mutex_lock(&w->lock);
    s = w->state;
    pthread_mutex_unlock(&w->lock);
    return s;
}

static void nonblocking(int fd) {
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
}

static void server_start(server *s, const uint8_t priv[32], const uint8_t client_pub[32]) {
    struct sockaddr_in a;
    socklen_t len = sizeof(a);
    memset(s, 0, sizeof(*s));
    s->fd = socket(AF_INET, SOCK_DGRAM, 0);
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    CHECK(bind(s->fd, (struct sockaddr *)&a, sizeof(a)) == 0);
    getsockname(s->fd, (struct sockaddr *)&a, &len);
    s->port = ntohs(a.sin_port);
    nonblocking(s->fd);
    responder_init(&s->r, priv, client_pub);
}

/* one datagram of the client's, or the plain bytes of a data message once the session exists; returns the plain length, 0 for nothing, -1 for a handshake */
static long server_step(server *s, int wait_ms, uint8_t *plain, size_t cap) {
    uint8_t raw[2048], response[SHIRO_WG_RESPONSE_LEN];
    struct pollfd p;
    ssize_t n;
    p.fd = s->fd;
    p.events = POLLIN;
    p.revents = 0;
    if (poll(&p, 1, wait_ms) <= 0) return 0;
    s->client_len = sizeof(s->client);
    n = recvfrom(s->fd, raw, sizeof(raw), 0, (struct sockaddr *)&s->client, &s->client_len);
    if (n <= 0) return 0;
    if (n == 148 && (shiro_get_u32le(raw) & 0xffu) == 1u) {
        if (responder_answer(&s->r, raw, response, 1, 2) != 0) return 0;
        sendto(s->fd, response, sizeof(response), 0, (struct sockaddr *)&s->client, s->client_len);
        memset(&s->session, 0, sizeof(s->session));
        memcpy(s->session.send_key, s->r.send_key, 32);
        memcpy(s->session.recv_key, s->r.recv_key, 32);
        s->session.local_index = s->r.index;
        s->session.remote_index = s->r.peer_index;
        s->session.data_type = 4;
        s->session.active = 1;
        s->have_session = 1;
        ++s->initiations;
        return -1;
    }
    if (!s->have_session) return 0;
    {
        size_t plain_len = 0;
        if (shiro_wg_open(&s->session, raw, (size_t)n, plain, cap, &plain_len) != SHIRO_OK) return 0;
        return (long)plain_len;
    }
}

static void server_send_udp(server *s, uint32_t src_ip, uint16_t src_port, uint16_t dst_port, const char *text) {
    uint8_t packet[SHIRO_UDP_PACKET_MAX], sealed[SHIRO_WG_MAX_DATAGRAM];
    size_t packet_len = 0, sealed_len = 0;
    CHECK_EQ_INT(shiro_udp_build(src_ip, src_port, CLIENT_ADDRESS, dst_port, 9, (const uint8_t *)text, strlen(text), packet, sizeof(packet), &packet_len), SHIRO_OK);
    CHECK_EQ_INT(shiro_wg_seal(&s->session, packet, packet_len, sealed, sizeof(sealed), &sealed_len), SHIRO_OK);
    sendto(s->fd, sealed, sealed_len, 0, (struct sockaddr *)&s->client, s->client_len);
}

/* the next UDP packet the client sent through the tunnel, within wait_ms; keepalives and other messages are skipped */
static int server_expect_udp(server *s, int wait_ms, shiro_udp_datagram *d, uint8_t *keep, size_t keep_cap) {
    uint64_t end = shiro_system_clock.monotonic_ms(NULL) + (uint64_t)wait_ms;
    while (shiro_system_clock.monotonic_ms(NULL) < end) {
        long n = server_step(s, 50, keep, keep_cap);
        if (n > 0 && shiro_udp_parse(keep, (size_t)n, d) == SHIRO_OK) return 1;
    }
    return 0;
}

static int wait_readable(int fd, int ms) {
    struct pollfd p;
    p.fd = fd;
    p.events = POLLIN;
    p.revents = 0;
    return poll(&p, 1, ms) > 0 && (p.revents & POLLIN);
}

int main(void) {
    uint8_t client_priv[32], client_pub[32], server_priv[32], server_pub[32];
    uint8_t plain[SHIRO_WG_MAX_DATAGRAM], frame[SHIRO_UDP_FRAME_HEADER + SHIRO_UDP_MAX_PAYLOAD + 8];
    shiro_warp_identity id;
    shiro_events events;
    shiro_core *core = NULL;
    watch w;
    server s;
    shiro_udp_datagram d;
    size_t frame_len = 0;
    int fd = -1, fds[32], i;
    uint64_t end;

    shiro_random(client_priv, 32);
    client_priv[0] &= 248;
    client_priv[31] = (uint8_t)((client_priv[31] & 127) | 64);
    shiro_x25519_public(client_priv, client_pub);
    shiro_random(server_priv, 32);
    server_priv[0] &= 248;
    server_priv[31] = (uint8_t)((server_priv[31] & 127) | 64);
    shiro_x25519_public(server_priv, server_pub);
    server_start(&s, server_priv, client_pub);

    memset(&id, 0, sizeof(id));
    memcpy(id.private_key, client_priv, 32);
    memcpy(id.peer_public, server_pub, 32);
    id.address = CLIENT_ADDRESS;
    id.endpoint_ip = 0x7f000001u;
    id.ports[0] = s.port;
    id.port_count = 1;

    pthread_mutex_init(&w.lock, NULL);
    w.state = SHIRO_HANDSHAKING;
    w.reason = SHIRO_OK;
    events.context = &w;
    events.state = on_state;
    events.trace = NULL;
    CHECK_EQ_INT(shiro_core_start(&core, &id, id.endpoint_ip, id.ports[0], &events), SHIRO_OK);
    if (!core) return 1;

    /* no datagram socket before the tunnel is up */
    CHECK_EQ_INT(shiro_core_open_udp(core, &fd), SHIRO_E_STATE);
    CHECK_EQ_INT(fd, -1);

    end = shiro_system_clock.monotonic_ms(NULL) + 5000;
    while (watched(&w) != SHIRO_UP && shiro_system_clock.monotonic_ms(NULL) < end) server_step(&s, 20, plain, sizeof(plain));
    CHECK_EQ_INT(watched(&w), SHIRO_UP);

    CHECK_EQ_INT(shiro_core_open_udp(core, &fd), SHIRO_OK);
    CHECK(fd >= 0);

    /* out: a framed datagram becomes a UDP packet from the address of the phone and a port of the tunnel's choosing */
    CHECK_EQ_INT(shiro_udp_frame_encode(PEER_ADDRESS, PEER_PORT, (const uint8_t *)"ping", 4, frame, sizeof(frame), &frame_len), SHIRO_OK);
    CHECK_EQ_INT(send(fd, frame, frame_len, 0), (ssize_t)frame_len);
    CHECK(server_expect_udp(&s, 3000, &d, plain, sizeof(plain)));
    CHECK_EQ_INT(d.src_ip, CLIENT_ADDRESS);
    CHECK_EQ_INT(d.dst_ip, PEER_ADDRESS);
    CHECK_EQ_INT(d.dst_port, PEER_PORT);
    CHECK(d.src_port >= 49152);
    CHECK_EQ_INT(d.payload_len, 4);
    CHECK_MEM(d.payload, "ping", 4);
    {
        uint16_t local_port = d.src_port;

        /* in: a reply to that port comes back as a frame that names its sender */
        server_send_udp(&s, PEER_ADDRESS, PEER_PORT, local_port, "pong");
        CHECK(wait_readable(fd, 3000));
        {
            ssize_t n = recv(fd, frame, sizeof(frame), 0);
            uint32_t ip = 0;
            uint16_t port = 0;
            const uint8_t *payload = NULL;
            size_t payload_len = 0;
            CHECK(n > 0);
            CHECK_EQ_INT(shiro_udp_frame_decode(frame, (size_t)(n > 0 ? n : 0), &ip, &port, &payload, &payload_len), SHIRO_OK);
            CHECK_EQ_INT(ip, PEER_ADDRESS);
            CHECK_EQ_INT(port, PEER_PORT);
            CHECK_EQ_INT(payload_len, 4);
            CHECK_MEM(payload, "pong", 4);
        }

        /* a datagram from any other peer reaches the socket too, as for an unconnected UDP socket */
        server_send_udp(&s, 0x01020304u, 9999, local_port, "other");
        CHECK(wait_readable(fd, 3000));
        {
            ssize_t n = recv(fd, frame, sizeof(frame), 0);
            uint32_t ip = 0;
            uint16_t port = 0;
            const uint8_t *payload = NULL;
            size_t payload_len = 0;
            CHECK_EQ_INT(shiro_udp_frame_decode(frame, (size_t)(n > 0 ? n : 0), &ip, &port, &payload, &payload_len), SHIRO_OK);
            CHECK_EQ_INT(ip, 0x01020304u);
            CHECK_EQ_INT(port, 9999);
        }

        /* a port that no socket holds is dropped */
        server_send_udp(&s, PEER_ADDRESS, PEER_PORT, (uint16_t)(local_port + 1), "nobody");
        CHECK(!wait_readable(fd, 400));
    }

    /* bad frames are dropped: too short, no destination, a payload over the limit; nothing of them reaches the server */
    {
        static uint8_t big[SHIRO_UDP_FRAME_HEADER + SHIRO_UDP_MAX_PAYLOAD + 1];
        uint8_t zero_dest[SHIRO_UDP_FRAME_HEADER + 2] = {0, 0, 0, 0, 0, 0, 'h', 'i'};
        memset(big, 'x', sizeof(big));
        memcpy(big, "\x08\x08\x08\x08\x0d\x96", 6);
        CHECK(send(fd, big, 3, 0) == 3);
        CHECK(send(fd, zero_dest, sizeof(zero_dest), 0) == (ssize_t)sizeof(zero_dest));
        CHECK(send(fd, big, sizeof(big), 0) == (ssize_t)sizeof(big));
        CHECK(!server_expect_udp(&s, 400, &d, plain, sizeof(plain)));
    }

    /* the largest payload goes through whole */
    {
        static uint8_t full[SHIRO_UDP_MAX_PAYLOAD];
        memset(full, 0x5a, sizeof(full));
        CHECK_EQ_INT(shiro_udp_frame_encode(PEER_ADDRESS, PEER_PORT, full, sizeof(full), frame, sizeof(frame), &frame_len), SHIRO_OK);
        CHECK(send(fd, frame, frame_len, 0) == (ssize_t)frame_len);
        CHECK(server_expect_udp(&s, 3000, &d, plain, sizeof(plain)));
        CHECK_EQ_INT(d.payload_len, SHIRO_UDP_MAX_PAYLOAD);
        CHECK_MEM(d.payload, full, sizeof(full));
    }

    /* the sockets are limited, and a refused one leaves nothing behind */
    for (i = 0; i < 32; ++i) fds[i] = -1;
    for (i = 0; i < 15; ++i) CHECK_EQ_INT(shiro_core_open_udp(core, &fds[i]), SHIRO_OK);
    {
        int extra = 7;
        CHECK_EQ_INT(shiro_core_open_udp(core, &extra), SHIRO_E_LIMIT);
        CHECK_EQ_INT(extra, -1);
    }
    /* a socket that is closed makes room again, once the tunnel has noticed that its other end is gone */
    close(fd);
    fd = -1;
    for (i = 0; i < 15; ++i) close(fds[i]);
    end = shiro_system_clock.monotonic_ms(NULL) + 3000;
    while (shiro_system_clock.monotonic_ms(NULL) < end) {
        if (shiro_core_open_udp(core, &fd) == SHIRO_OK) break;
        usleep(20000);
    }
    CHECK(fd >= 0);
    if (fd >= 0) close(fd);

    /* a stream whose far side never answers is not a dead path for twenty seconds yet, so the tunnel starts no handshake of its own meanwhile. The slip that
       once did (an unsigned difference of a stamp a millisecond ahead of the pass's clock) depends on timing and does not show on every host */
    {
        int stream = -1;
        uint64_t drain_end;
        CHECK_EQ_INT(s.initiations, 1);
        CHECK_EQ_INT(shiro_core_open(core, PEER_ADDRESS, 443, 700, &stream), SHIRO_E_TIMEOUT);
        drain_end = shiro_system_clock.monotonic_ms(NULL) + 400;
        while (shiro_system_clock.monotonic_ms(NULL) < drain_end) server_step(&s, 20, plain, sizeof(plain));
        CHECK_EQ_INT(s.initiations, 1);
    }

    shiro_core_stop(core);
    close(s.fd);
    pthread_mutex_destroy(&w.lock);
    return test_finish("test_shiro_core_udp");
}
