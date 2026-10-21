#ifndef SHIRO_TCPIP_H
#define SHIRO_TCPIP_H

#include <stddef.h>
#include <stdint.h>

#include "shiro_status.h"

/* the TCP of one phone inside a tunnel: IPv4 only, client side only, no options but the segment size. The tunnel is a point to point link, so the stack
   has no routing, no fragmentation, no ICMP and no listening sockets. It owns no thread, no socket and no clock: the owner passes packets in, takes
   packets out through a callback, and calls tick often (every 10 to 50 ms). Time is milliseconds of any steady clock; addresses are host order */

#define SHIRO_TCPIP_MAX_CONNECTIONS 32
/* each direction of a connection keeps this many bytes, which is also the largest window without the scaling option */
#define SHIRO_TCPIP_BUFFER 65536
#define SHIRO_TCPIP_MIN_MTU 576
#define SHIRO_TCPIP_MAX_MTU 1500

typedef void (*shiro_tcpip_emit)(void *context, const uint8_t *packet, size_t len);

typedef struct shiro_tcpip shiro_tcpip;

/* local_ip is the address the tunnel gave this phone; mtu from SHIRO_TCPIP_MIN_MTU to SHIRO_TCPIP_MAX_MTU is the size of the largest packet sent */
shiro_status shiro_tcpip_new(shiro_tcpip **out, uint32_t local_ip, uint16_t mtu, shiro_tcpip_emit emit, void *context);
void shiro_tcpip_free(shiro_tcpip *stack);

/* a packet that came out of the tunnel. Anything that is not a whole, valid IPv4 TCP segment for a connection of this stack (or is a fragment) is dropped, and a
   segment for a connection that is gone is answered with a reset */
void shiro_tcpip_input(shiro_tcpip *stack, const uint8_t *packet, size_t len, uint64_t now_ms);

/* timers: retransmission, delayed acknowledgements, giving up */
void shiro_tcpip_tick(shiro_tcpip *stack, uint64_t now_ms);

/* the connection id stays valid until released. SHIRO_E_LIMIT when all slots are taken, SHIRO_E_NOMEM, SHIRO_E_ARG for port 0 or address 0 */
shiro_status shiro_tcpip_connect(shiro_tcpip *stack, uint32_t remote_ip, uint16_t remote_port, uint64_t now_ms, uint32_t *id);

typedef enum shiro_tcpip_state {
    SHIRO_TCPIP_CONNECTING = 0,   /* the SYN is out */
    SHIRO_TCPIP_OPEN,             /* data may flow both ways (maybe one of them already ended) */
    SHIRO_TCPIP_DONE,             /* both directions ended and acknowledged */
    SHIRO_TCPIP_FAILED            /* reset by the peer, or no answer in time */
} shiro_tcpip_state;

typedef struct shiro_tcpip_info {
    shiro_tcpip_state state;
    size_t readable;            /* bytes waiting for shiro_tcpip_recv */
    size_t send_space;          /* bytes shiro_tcpip_send will take now */
    int peer_closed;            /* the peer's FIN arrived and everything before it was received */
    int closed_by_us;           /* shiro_tcpip_close was called */
    shiro_status error;       /* SHIRO_E_TIMEOUT, SHIRO_E_IO (reset) or SHIRO_OK */
} shiro_tcpip_info;

/* SHIRO_E_NOTFOUND for an id that is not a connection of this stack */
shiro_status shiro_tcpip_info_get(const shiro_tcpip *stack, uint32_t id, shiro_tcpip_info *info);

/* queues up to len bytes and sends what the windows allow; *accepted says how many were taken (0 when the buffer is full: retry after the peer acknowledges).
   SHIRO_E_STATE after close or when the connection is not open */
shiro_status shiro_tcpip_send(shiro_tcpip *stack, uint32_t id, const uint8_t *data, size_t len, uint64_t now_ms, size_t *accepted);

/* takes what has arrived, in order. SHIRO_E_RETRY when nothing is there yet, SHIRO_E_EOF when the peer closed and everything was read, SHIRO_E_IO or
   SHIRO_E_TIMEOUT for a failed connection */
shiro_status shiro_tcpip_recv(shiro_tcpip *stack, uint32_t id, uint8_t *buf, size_t cap, uint64_t now_ms, size_t *got);

/* no more data from us: the FIN follows the queued bytes */
shiro_status shiro_tcpip_close(shiro_tcpip *stack, uint32_t id, uint64_t now_ms);

/* frees the slot. A connection that is not finished is reset towards the peer */
void shiro_tcpip_release(shiro_tcpip *stack, uint32_t id, uint64_t now_ms);

typedef struct shiro_tcpip_stats {
    uint32_t segments_in, segments_out, bad_packets, retransmits, fast_retransmits, out_of_order, resets_sent;
} shiro_tcpip_stats;

void shiro_tcpip_stats_get(const shiro_tcpip *stack, shiro_tcpip_stats *stats);

#endif
