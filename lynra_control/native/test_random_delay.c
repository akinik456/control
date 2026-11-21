#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <stdint.h>

static int passed = 0, total = 0;
#define CHECK(x) do { ++total; if (x) ++passed; else printf("FAIL line %d: %s\n", __LINE__, #x); } while (0)

static int scan_q(LynraPlcEngine *e, uint64_t ms, int input_on) {
    if (!lynra_plc_scan(e, ms, input_on ? 1u : 0u)) return -1;
    return (lynra_plc_get_outputs(e) & 1u) != 0;
}

static LynraRule make_rule(unsigned th_random, unsigned tl_random) {
    LynraRule r = {0};
    r.condition_count = 1;
    r.conditions[0].input_index = 1;
    r.conditions[0].trigger = LYNRA_TRIGGER_HIGH;
    r.action_count = 1;
    r.actions[0].type = LYNRA_TIMER_ON_OFF_DELAY;
    r.actions[0].output_index = 1;
    r.actions[0].th_ms = 100;
    r.actions[0].tl_ms = 120;
    r.actions[0].th_random = (uint8_t)th_random;
    r.actions[0].tl_random = (uint8_t)tl_random;
    return r;
}

/* Find the first millisecond when Q reaches the requested level. */
static int transition(LynraPlcEngine *e, uint64_t start, int input, int target, int max_ms) {
    for (int dt = 0; dt <= max_ms; ++dt) {
        int q = scan_q(e, start + (uint64_t)dt, input);
        if (q < 0) return -1;
        if (q == target) return dt;
    }
    return -1;
}

static void test_modes(LynraPlcEngine *e, int th_rand, int tl_rand) {
    LynraRule r = make_rule(th_rand, tl_rand);
    CHECK(lynra_plc_load_rules(e, &r, 1));
    int ton = transition(e, 1000, 1, 1, 101);
    int toff = transition(e, 1200, 0, 0, 121);
    CHECK(th_rand ? (ton >= 0 && ton <= 100) : ton == 100);
    CHECK(tl_rand ? (toff >= 0 && toff <= 120) : toff == 120);
    printf("TH_RANDOM=%d TL_RANDOM=%d: ON=%d ms OFF=%d ms\n", th_rand, tl_rand, ton, toff);
}

static void test_cancellation(LynraPlcEngine *e) {
    LynraRule r = make_rule(0, 0);
    CHECK(lynra_plc_load_rules(e, &r, 1));
    CHECK(scan_q(e, 1000, 1) == 0);
    CHECK(scan_q(e, 1050, 0) == 0); /* ON pending cancelled */
    CHECK(scan_q(e, 1100, 1) == 0);
    CHECK(scan_q(e, 1199, 1) == 0);
    CHECK(scan_q(e, 1200, 1) == 1);
    CHECK(scan_q(e, 1250, 0) == 1);
    CHECK(scan_q(e, 1300, 1) == 1); /* OFF pending cancelled */
    CHECK(scan_q(e, 1450, 1) == 1);
    CHECK(scan_q(e, 1500, 0) == 1);
    CHECK(scan_q(e, 1619, 0) == 1);
    CHECK(scan_q(e, 1620, 0) == 0);
}

static void test_random_retrigger(LynraPlcEngine *e) {
    LynraRule r = make_rule(1, 1);
    CHECK(lynra_plc_load_rules(e, &r, 1));
    /* Every fresh activation must eventually turn ON by its TH upper bound. */
    for (int i = 0; i < 12; ++i) {
        uint64_t t = 1000 + (uint64_t)i * 650;
        CHECK(scan_q(e, t, 0) == 0);
        CHECK(scan_q(e, t + 150, 1) >= 0);
        CHECK(scan_q(e, t + 250, 1) == 1);
        CHECK(scan_q(e, t + 400, 0) >= 0);
        CHECK(scan_q(e, t + 521, 0) == 0);
    }
}

int main(void) {
    LynraPlcEngine *e = lynra_plc_create();
    CHECK(e != NULL);
    if (!e) return 1;
    for (int th = 0; th <= 1; ++th)
        for (int tl = 0; tl <= 1; ++tl)
            test_modes(e, th, tl);
    test_cancellation(e);
    test_random_retrigger(e);
    printf("RESULT: %s (%d/%d)\n", passed == total ? "PASS" : "FAIL", passed, total);
    lynra_plc_destroy(e);
    return passed == total ? 0 : 1;
}
