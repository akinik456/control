#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <string.h>

static int fails = 0;
static void check(LynraPlcEngine *e, uint64_t ms, uint32_t inputs, int expected, const char *label) {
    if (!lynra_plc_scan(e, ms, inputs)) { printf("FAIL scan: %s\n", label); ++fails; return; }
    int q = (lynra_plc_get_outputs(e) & 1u) != 0;
    printf("[%s] %5llu ms | I1=%u Q1=%d expected=%d | %s\n", q == expected ? "PASS" : "FAIL", (unsigned long long)ms, inputs & 1u, q, expected, label);
    if (q != expected) ++fails;
}
int main(void) {
    LynraPlcEngine *e = lynra_plc_create();
    if (!e) return 1;
    LynraRule r;
    memset(&r, 0, sizeof(r));
    r.condition_count = 1;
    r.conditions[0].input_index = 1;
    r.conditions[0].trigger = LYNRA_TRIGGER_HIGH;
    r.action_count = 1;
    r.actions[0].type = LYNRA_TIMER_ON_DELAY;
    r.actions[0].output_index = 1;
    r.actions[0].t_ms = 10000;
    r.actions[0].virtual_start = 1;
    if (!lynra_plc_load_rules(e, &r, 1)) { puts("FAIL load"); return 1; }
    check(e, 0, 0, 0, "virtual start");
    check(e, 9999, 0, 0, "before virtual timeout");
    check(e, 10000, 0, 1, "virtual timeout");
    check(e, 12000, 1, 0, "physical ON: immediate reset");
    check(e, 21999, 1, 0, "before physical timeout");
    check(e, 22000, 1, 1, "physical timeout");
    check(e, 23000, 0, 0, "physical OFF");
    check(e, 24000, 1, 0, "physical ON again");
    check(e, 34000, 1, 1, "second physical timeout");
    lynra_plc_destroy(e);
    printf("\nRESULT: %s (%d failures)\n", fails ? "FAIL" : "PASS", fails);
    return fails ? 1 : 0;
}
