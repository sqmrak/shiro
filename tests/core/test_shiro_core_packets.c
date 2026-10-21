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

TEST_UNUSED static void on_state(void *context, shiro_state state, shiro_status reason) {
    watch *w = (watch *)context;
    pthread_mutex_lock(&w->lock);
    w->state = state;
    w->reason = reason;
    pthread_mutex_unlock(&w->lock);
}

TEST_UNUSED static shiro_state watched(watch *w) {
    shiro_state s;
    pthread_mutex_lock(&w->lock);
    s = w->state;
    pthread_mutex_unlock(&w->lock);
    return s;
}

TEST_UNUSED static void nonblocking(int fd) {
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
}

TEST_UNUSED static void server_start(server *s, const uint8_t priv[32], const uint8_t client_pub[32]) {
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
TEST_UNUSED static long server_step(server *s, int wait_ms, uint8_t *plain, size_t cap) {
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

TEST_UNUSED static void server_send_udp(server *s, uint32_t src_ip, uint16_t src_port, uint16_t dst_port, const char *text) {
    uint8_t packet[SHIRO_UDP_PACKET_MAX], sealed[SHIRO_WG_MAX_DATAGRAM];
    size_t packet_len = 0, sealed_len = 0;
    CHECK_EQ_INT(shiro_udp_build(src_ip, src_port, CLIENT_ADDRESS, dst_port, 9, (const uint8_t *)text, strlen(text), packet, sizeof(packet), &packet_len), SHIRO_OK);
    CHECK_EQ_INT(shiro_wg_seal(&s->session, packet, packet_len, sealed, sizeof(sealed), &sealed_len), SHIRO_OK);
    sendto(s->fd, sealed, sealed_len, 0, (struct sockaddr *)&s->client, s->client_len);
}

/* the next UDP packet the client sent through the tunnel, within wait_ms; keepalives and other messages are skipped */
TEST_UNUSED static int server_expect_udp(server *s, int wait_ms, shiro_udp_datagram *d, uint8_t *keep, size_t keep_cap) {
    uint64_t end = shiro_system_clock.monotonic_ms(NULL) + (uint64_t)wait_ms;
    while (shiro_system_clock.monotonic_ms(NULL) < end) {
        long n = server_step(s, 50, keep, keep_cap);
        if (n > 0 && shiro_udp_parse(keep, (size_t)n, d) == SHIRO_OK) return 1;
    }
    return 0;
}

TEST_UNUSED static int wait_readable(int fd, int ms) {
    struct pollfd p;
    p.fd = fd;
    p.events = POLLIN;
    p.revents = 0;
    return poll(&p, 1, ms) > 0 && (p.revents & POLLIN);
}

int main(void) {
    uint8_t client_priv[32], client_pub[32], server_priv[32], server_pub[32];
    uint8_t plain[SHIRO_WG_MAX_DATAGRAM], frame[1400];
    shiro_warp_identity identity;
    shiro_routing rules;
    shiro_core *core = NULL;
    watch w;
    server s;
    int pair[2];
    shiro_random(client_priv, 32); shiro_random(server_priv, 32);
    shiro_x25519_public(client_priv, client_pub); shiro_x25519_public(server_priv, server_pub);
    server_start(&s, server_priv, client_pub);
    memset(&identity, 0, sizeof(identity));
    memcpy(identity.private_key, client_priv, 32); memcpy(identity.peer_public, server_pub, 32);
    identity.address = CLIENT_ADDRESS; identity.endpoint_ip = 0x7f000001; identity.ports[0] = s.port; identity.port_count = 1;
    pthread_mutex_init(&w.lock, NULL); w.state = SHIRO_HANDSHAKING; w.reason = SHIRO_OK;
    shiro_events events = {&w, on_state, NULL};
    CHECK_EQ_INT(socketpair(AF_UNIX, SOCK_DGRAM, 0, pair), 0);
    nonblocking(pair[0]); nonblocking(pair[1]);
    CHECK_EQ_INT(shiro_routing_parse("", "203.0.113.0/24", &rules), 0);
    CHECK_EQ_INT(shiro_core_start_packets(&core, &identity, identity.endpoint_ip, s.port, &events, pair[0], &rules), SHIRO_OK);
    if (!core) return 1;
    uint64_t end = shiro_system_clock.monotonic_ms(NULL) + 3000;
    while (watched(&w) != SHIRO_UP && shiro_system_clock.monotonic_ms(NULL) < end) server_step(&s, 20, plain, sizeof(plain));
    CHECK_EQ_INT(watched(&w), SHIRO_UP);
    memset(frame, 0, 4); frame[3] = AF_INET;
    size_t length = 0;
    shiro_udp_datagram datagram;
    CHECK_EQ_INT(shiro_udp_build(CLIENT_ADDRESS, 1200, PEER_ADDRESS, 53, 1, (const uint8_t *)"query", 5, frame + 4, sizeof(frame) - 4, &length), SHIRO_OK);
    CHECK_EQ_INT(write(pair[1], frame, length + 4), (ssize_t)length + 4);
    CHECK(server_expect_udp(&s, 1000, &datagram, plain, sizeof(plain)));
    CHECK_EQ_INT(datagram.src_ip, CLIENT_ADDRESS); CHECK_EQ_INT(datagram.dst_ip, PEER_ADDRESS);
    CHECK_MEM(datagram.payload, "query", 5);
    server_send_udp(&s, PEER_ADDRESS, 53, 1200, "answer");
    CHECK(wait_readable(pair[1], 1000));
    ssize_t n = read(pair[1], frame, sizeof(frame));
    CHECK(n > 4); CHECK_EQ_INT(frame[3], AF_INET);
    CHECK_EQ_INT(shiro_udp_parse(frame + 4, (size_t)(n > 4 ? n - 4 : 0), &datagram), SHIRO_OK);
    CHECK_EQ_INT(datagram.payload_len, 6); CHECK_MEM(datagram.payload, "answer", 6);
    CHECK_EQ_INT(shiro_udp_build(CLIENT_ADDRESS, 1200, 0xcb007101, 53, 1, (const uint8_t *)"blocked", 7, frame + 4, sizeof(frame) - 4, &length), SHIRO_OK);
    CHECK_EQ_INT(write(pair[1], frame, length + 4), (ssize_t)length + 4);
    CHECK(!server_expect_udp(&s, 200, &datagram, plain, sizeof(plain)));
    frame[3] = AF_INET6;
    CHECK_EQ_INT(write(pair[1], frame, length + 4), (ssize_t)length + 4);
    CHECK(!server_expect_udp(&s, 200, &datagram, plain, sizeof(plain)));
    frame[3] = AF_INET; frame[4] = 0x44;
    CHECK_EQ_INT(write(pair[1], frame, length + 4), (ssize_t)length + 4);
    CHECK(!server_expect_udp(&s, 200, &datagram, plain, sizeof(plain)));
    shiro_core_stop(core);
    CHECK(fcntl(pair[0], F_GETFD) >= 0);
    close(pair[0]); close(pair[1]); close(s.fd); pthread_mutex_destroy(&w.lock);
    return test_finish("shiro_core_packets");
}
