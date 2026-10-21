CC = cc
BUILD ?= ../build/host
SRC := $(wildcard ../core/*/*.c) ../daemon/route_socket.c ../daemon/utun_route.c ../daemon/legacy_ios.c ../daemon/utun_device.c
INC := $(addprefix -I,$(wildcard ../core/*)) -Icore -I../daemon
CFLAGS := -std=c99 -D_POSIX_C_SOURCE=200809L -D_DEFAULT_SOURCE -O2 -g -Wall -Wextra -Werror -Wshadow -Wstrict-prototypes -Wmissing-prototypes -Wconversion -Wno-sign-conversion $(INC) $(OPT)
OBJ := $(patsubst ../%.c,$(BUILD)/%.o,$(SRC))
TESTS := $(patsubst core/%.c,$(BUILD)/%,$(wildcard core/test_*.c))
.PHONY: test sanitize
test: $(TESTS)
	@set -e; for t in $(TESTS); do $$t; done
	python3 test_status_install.py
sanitize:
	$(MAKE) BUILD=../build/asan OPT='-O1 -fsanitize=address,undefined -fno-omit-frame-pointer' test
$(BUILD)/%.o: ../%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -MMD -MP -c $< -o $@
$(BUILD)/test_socket_resolution: LDFLAGS += -Wl,--wrap=getaddrinfo
$(BUILD)/test_%: core/test_%.c $(OBJ) core/fake_tcp_server.c
	$(CC) $(CFLAGS) $< core/fake_tcp_server.c $(OBJ) -lpthread -lssl -lcrypto $(LDFLAGS) -o $@
-include $(OBJ:.o=.d)
.SECONDARY: $(OBJ)
