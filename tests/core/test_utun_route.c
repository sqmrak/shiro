#include "utun_route.h"
#include "test_util.h"
#include <errno.h>

typedef struct {
    int adds, deletes;
    int fail_add;
    int fail_delete;
    int wrong_path;
    int deleted[8];
} table;

static int apply(void *context, const tun_plan_op_entry_t *op, const char *ifname, utun_route_error_t *error) {
    table *t = context;
    (void)ifname;
    memset(error, 0, sizeof(*error));
    if (op->op == TUN_PLAN_OP_ADD) {
        int index = t->adds++;
        if (index == t->fail_add) { error->code = EEXIST; return -1; }
        return 0;
    }
    ++t->deletes;
    if (op->address[3] == t->fail_delete) { error->code = EIO; return -1; }
    ++t->deleted[op->address[3]];
    return 0;
}

static int lookup(void *context, const uint8_t *address, uint8_t len, char *out, size_t cap, utun_route_error_t *error) {
    table *t = context;
    (void)address; (void)len; (void)error;
    snprintf(out, cap, "%s", t->wrong_path ? "utun1" : "en0");
    return 0;
}

static void setup(tun_plan_t *plan, table *t) {
    memset(plan, 0, sizeof(*plan));
    memset(t, 0, sizeof(*t));
    t->fail_add = t->fail_delete = -1;
    snprintf(plan->ifname, sizeof(plan->ifname), "utun1");
    plan->count = 4;
    for (size_t i = 0; i < plan->count; ++i) {
        plan->ops[i].address_len = 4;
        plan->ops[i].address[0] = 8;
        plan->ops[i].address[3] = (uint8_t)i;
        plan->ops[i].prefix = 32;
        snprintf(plan->ops[i].label, sizeof(plan->ops[i].label), "endpoint[%zu]", i);
        plan->ops[i].kind = TUN_PLAN_KIND_ENDPOINT_PIN;
        plan->ops[i].via = TUN_PLAN_VIA_PHYSICAL;
        snprintf(plan->ops[i].ifname, sizeof(plan->ops[i].ifname), "en0");
    }
}

int main(void) {
    tun_plan_t plan, recovery;
    table t;
    utun_route_result_t result;
    utun_route_executor_t executor = {apply, lookup, &t};
    char journal[4096];
    setup(&plan, &t);
    t.fail_add = 2;
    t.fail_delete = 0;
    CHECK_EQ_INT(utun_route_apply(&plan, &executor, &result), UTUN_ROUTE_ERR_APPLY);
    CHECK_EQ_INT(result.rollback_failures, 1);
    CHECK(!plan.ops[0].preexisting);
    CHECK(plan.ops[1].preexisting);
    CHECK(plan.ops[2].preexisting);
    CHECK(plan.ops[3].preexisting);
    int n = tun_plan_save_leftovers(&plan, journal, sizeof(journal));
    CHECK(n > 0);
    CHECK_EQ_INT(tun_plan_load_leftovers(journal, (size_t)n, &recovery), TUN_PLAN_OK);
    CHECK_EQ_INT(recovery.count, 1);
    CHECK_EQ_INT(recovery.ops[0].address[3], 0);
    t.fail_delete = -1;
    CHECK_EQ_INT(utun_route_revert(&recovery, &executor, &result), UTUN_ROUTE_OK);
    CHECK_EQ_INT(t.deleted[0], 1);
    CHECK_EQ_INT(t.deleted[1], 1);
    CHECK_EQ_INT(t.deleted[2], 0);
    CHECK_EQ_INT(t.deleted[3], 0);

    setup(&plan, &t);
    t.wrong_path = 1;
    t.fail_delete = 1;
    CHECK_EQ_INT(utun_route_apply_verified(&plan, &executor, &result), UTUN_ROUTE_ERR_RECURSION);
    CHECK_EQ_INT(result.rollback_failures, 1);
    CHECK(plan.ops[0].preexisting);
    CHECK(!plan.ops[1].preexisting);
    CHECK(plan.ops[2].preexisting);
    CHECK(plan.ops[3].preexisting);
    n = tun_plan_save_leftovers(&plan, journal, sizeof(journal));
    CHECK_EQ_INT(tun_plan_load_leftovers(journal, (size_t)n, &recovery), TUN_PLAN_OK);
    CHECK_EQ_INT(recovery.count, 1);
    CHECK_EQ_INT(recovery.ops[0].address[3], 1);
    setup(&plan, &t);
    CHECK_EQ_INT(utun_route_apply_verified(&plan, &executor, &result), UTUN_ROUTE_OK);
    CHECK_EQ_INT(utun_route_revert(&plan, &executor, &result), UTUN_ROUTE_OK);
    CHECK_EQ_INT(t.deletes, 4);
    return test_finish("utun_route");
}
