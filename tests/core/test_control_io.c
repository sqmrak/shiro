#include "shiro_control_io.h"
#include "shiro_clock.h"
#include "test_util.h"
#include <sys/socket.h>
#include <unistd.h>
#include <pthread.h>
#include <poll.h>
#include <signal.h>

static void *trickle(void *context) {
    int fd = *(int *)context;
    static const uint8_t bytes[] = {0, 0, 0, 4, 's', 'l', 'o', 'w'};
    for (size_t i = 0; i < sizeof(bytes); ++i) {
        if (send(fd, bytes + i, 1, 0) != 1) break;
        /* the test peer deliberately drips bytes past the whole-frame deadline */
        poll(NULL, 0, 25);
    }
    return NULL;
}

int main(void) {
    int pair[2];
    uint8_t data[32];
    size_t length;
    signal(SIGPIPE, SIG_IGN);
    CHECK_EQ_INT(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    CHECK_EQ_INT(shiro_control_write(pair[0], (const uint8_t *)"hello", 5, 100), SHIRO_OK);
    CHECK_EQ_INT(shiro_control_read(pair[1], data, sizeof(data), &length, 100), SHIRO_OK);
    CHECK_EQ_INT(length, 5); CHECK_MEM(data, "hello", 5);
    const uint8_t zero[] = {0, 0, 0, 0};
    CHECK_EQ_INT(write(pair[0], zero, 4), 4);
    CHECK_EQ_INT(shiro_control_read(pair[1], data, sizeof(data), &length, 100), SHIRO_E_MALFORMED);
    CHECK_EQ_INT(length, 0);
    const uint8_t huge[] = {0, 1, 0, 1};
    CHECK_EQ_INT(write(pair[0], huge, 4), 4);
    CHECK_EQ_INT(shiro_control_read(pair[1], data, sizeof(data), &length, 100), SHIRO_E_LIMIT);
    CHECK_EQ_INT(shiro_control_read(pair[1], data, sizeof(data), &length, 20), SHIRO_E_TIMEOUT);
    pthread_t thread;
    CHECK_EQ_INT(pthread_create(&thread, NULL, trickle, &pair[0]), 0);
    uint64_t before = shiro_system_clock.monotonic_ms(NULL);
    CHECK_EQ_INT(shiro_control_read(pair[1], data, sizeof(data), &length, 80), SHIRO_E_TIMEOUT);
    CHECK(shiro_system_clock.monotonic_ms(NULL) - before < 180);
    close(pair[1]);
    CHECK_EQ_INT(pthread_join(thread, NULL), 0);
    close(pair[0]);
    CHECK_EQ_INT(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    const uint8_t partial[] = {0, 0, 0, 5, 'a'};
    CHECK_EQ_INT(write(pair[0], partial, sizeof(partial)), (ssize_t)sizeof(partial));
    close(pair[0]);
    CHECK_EQ_INT(shiro_control_read(pair[1], data, sizeof(data), &length, 100), SHIRO_E_EOF);
    CHECK_EQ_INT(length, 0);
    close(pair[1]);
    return test_finish("control_io");
}
