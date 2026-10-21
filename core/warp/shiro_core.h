#ifndef SHIRO_CORE_H
#define SHIRO_CORE_H

#include <stddef.h>
#include <stdint.h>

#include "shiro_status.h"
#include "shiro_warp.h"
#include "shiro_routing.h"

/* a WireGuard tunnel that lives in the process: one UDP socket to the server, a TCP stack behind it, and streams that other parts of the program open to
   addresses on the far side. Nothing is routed: no interface is made and no other program on the phone sees or can use the tunnel, because the streams
   are socket pairs handed to the caller and never listening ports. One thread does everything; the calls below may come from any thread */

typedef enum shiro_state {
    SHIRO_HANDSHAKING = 0,
    SHIRO_UP,
    SHIRO_DOWN
} shiro_state;

typedef struct shiro_events {
    void *context;
    /* on the core's thread; keep it short. DOWN comes with the reason: SHIRO_E_TIMEOUT for a server that does not answer, SHIRO_E_SECURITY for a reply that does
       not authenticate, SHIRO_E_IO for a socket that failed */
    void (*state)(void *context, shiro_state state, shiro_status reason);
    /* one line of what the tunnel does, never with a key or with payload */
    void (*trace)(void *context, const char *line);
} shiro_events;

typedef struct shiro_stats {
    uint64_t bytes_in, bytes_out;           /* UDP payload bytes to and from the server */
    uint32_t handshakes;
    uint64_t session_age_ms;
    unsigned streams;
} shiro_stats;

typedef struct shiro_core shiro_core;

/* starts the thread and the first handshake with the server at endpoint_ip:endpoint_port. The identity is copied */
shiro_status shiro_core_start(shiro_core **out, const shiro_warp_identity *identity, uint32_t endpoint_ip, uint16_t endpoint_port,
                                          const shiro_events *events);

/* ends everything: the streams are closed, the keys wiped, the thread joined */
void shiro_core_stop(shiro_core *core);

/* a stream to ip:port (host order) on the far side, as a connected non blocking socket for the caller to use like any TCP socket: reading, writing and closing it
   behave as for a connection. Waits until the far side has answered or timeout_ms has passed. SHIRO_E_STATE while the tunnel is not up,
   SHIRO_E_IO when the far side refused or reset, SHIRO_E_TIMEOUT, SHIRO_E_LIMIT when the streams are used up */
shiro_status shiro_core_open(shiro_core *core, uint32_t ip, uint16_t port, int timeout_ms, int *fd);

/* a datagram socket for UDP through the tunnel, as a non blocking local socket for the caller to use with send and recv. Every datagram it writes is a frame:
   the IPv4 address of the peer (big endian), its port (big endian) and the payload of up to SHIRO_UDP_MAX_PAYLOAD bytes (see shiro_udp.h). Every datagram
   it reads is a frame with the address and port the datagram came from, except that an empty datagram is only the tunnel checking that the socket is still
   open and is to be ignored. The tunnel gives the socket a local port of its own and passes whatever arrives on it
   from any peer, as an unconnected UDP socket does. A frame that is not valid is dropped. Closing the descriptor ends the socket (the tunnel notices within a few seconds), and one that sees no
   traffic for five minutes is closed by the tunnel. SHIRO_E_STATE while the tunnel is not up, SHIRO_E_LIMIT when the sockets are used up */
shiro_status shiro_core_open_udp(shiro_core *core, int *fd);

shiro_state shiro_core_state(shiro_core *core);
void shiro_core_stats(shiro_core *core, shiro_stats *stats);

/* packet_fd is a borrowed nonblocking utun descriptor, valid until stop returns */
shiro_status shiro_core_start_packets(shiro_core **out, const shiro_warp_identity *identity, uint32_t ip, uint16_t port,
                                      const shiro_events *events, int packet_fd, const shiro_routing *routing);
#endif
