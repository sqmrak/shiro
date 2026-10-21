#include "shiro_socket.h"
#include "shiro_clock.h"
#include <netdb.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int __real_getaddrinfo(const char *, const char *, const struct addrinfo *, struct addrinfo **);
int __wrap_getaddrinfo(const char *, const char *, const struct addrinfo *, struct addrinfo **);
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t ready = PTHREAD_COND_INITIALIZER;
static int released, completed, calls;

int __wrap_getaddrinfo(const char *host, const char *service,
                       const struct addrinfo *hints, struct addrinfo **result) {
    if (strcmp(host, "blocked.shiro.invalid") != 0)
        return __real_getaddrinfo(host, service, hints, result);
    pthread_mutex_lock(&lock);
    ++calls;
    while (!released) pthread_cond_wait(&ready, &lock);
    *result = NULL;
    completed = 1;
    pthread_cond_signal(&ready);
    pthread_mutex_unlock(&lock);
    return EAI_NONAME;
}

#define CHECK(value) do { if (!(value)) { fprintf(stderr, "resolution check failed: %s\n", #value); exit(1); } ++checks; } while (0)
int main(void) {
    int checks = 0;
    shiro_socket socket;
    shiro_socket_init(&socket);
    uint64_t begin = shiro_system_clock.monotonic_ms(NULL);
    CHECK(shiro_socket_connect(&socket, "blocked.shiro.invalid", 443, 30) == SHIRO_E_TIMEOUT);
    CHECK(shiro_system_clock.monotonic_ms(NULL) - begin < 1000);
    CHECK(socket.fd == -1);
    CHECK(shiro_socket_connect(&socket, "blocked.shiro.invalid", 443, 30) == SHIRO_E_STATE);
    pthread_mutex_lock(&lock);
    CHECK(calls == 1);
    released = 1;
    pthread_cond_signal(&ready);
    while (!completed) pthread_cond_wait(&ready, &lock);
    pthread_mutex_unlock(&lock);
    CHECK(shiro_socket_connect(&socket, "127.0.0.1", 1, 30) != SHIRO_OK);
    CHECK(socket.fd == -1);
    printf("socket_resolution: %d checks passed\n", checks);
    return 0;
}
