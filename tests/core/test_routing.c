#include "test_util.h"
#include "shiro_routing.h"
int main(void) {
    shiro_routing rules;
    CHECK_EQ_INT(shiro_routing_parse("", "", &rules), 0);
    CHECK_EQ_INT(shiro_routing_parse("192.168.0.0/16\n10.0.0.0/8", "203.0.113.0/24", &rules), 0);
    CHECK_EQ_INT(rules.direct_count, 2);
    CHECK(shiro_routing_blocked(&rules, 0xcb007101));
    CHECK(!shiro_routing_blocked(&rules, 0xcb007201));
    const char *bad[] = {"0.0.0.0/0", "128.0.0.0/1", "10.0.0.1/8", "256.0.0.0/8", "10.0.0.0/33", "10.0.0.0/8;bad", "10.0.0.0/-1", "127.0.0.0/8", "224.0.0.0/4", "10.0.0.0/8\n10.1.0.0/16"};
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); ++i)
        CHECK(shiro_routing_parse(bad[i], "", &rules) != 0);
    CHECK(shiro_routing_parse("10.0.0.0/8", "10.1.0.0/16", &rules) != 0);
    CHECK_EQ_INT(rules.direct_count, 0);
    CHECK_EQ_INT(shiro_routing_parse("", "203.0.113.255/32", &rules), 0);
    return test_finish("routing");
}
