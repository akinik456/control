#include "lynra_PLC_engine.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static void step(LynraPlcEngine *e, uint64_t t, uint32_t inputs, int expected) {
    assert(lynra_plc_scan(e, t, inputs));
    int actual = (lynra_plc_get_outputs(e) & 1u) != 0;
    if (actual != expected) {
        fprintf(stderr, "FAIL t=%llu inputs=%u expected=%d actual=%d\n",
                (unsigned long long)t, inputs, expected, actual);
        assert(actual == expected);
    }
}

static void test_retentive(int retrigger) {
    LynraPlcEngine *e = lynra_plc_create();
    assert(e);
    LynraRule r;
    memset(&r, 0, sizeof(r));
    r.logic_operator = LYNRA_LOGIC_AND;
    r.condition_count = 1;
    r.conditions[0].input_index = 1;
    r.conditions[0].trigger = LYNRA_TRIGGER_RISING;
    r.action_count = 1;
    r.actions[0].type = LYNRA_TIMER_RETENTIVE_ON_DELAY;
    r.actions[0].output_index = 1;
    r.actions[0].t_ms = 1000;
    r.actions[0].reset_input_index = 2;
    r.actions[0].retrigger = (uint8_t)retrigger;
    assert(lynra_plc_load_rules(e, &r, 1));

    step(e,    0, 0, 0);
    step(e,  100, 1, 0); // first rising edge: countdown begins
    step(e,  200, 0, 0);
    step(e,  600, 1, 0); // second rising edge during countdown
    step(e,  700, 0, 0);
    step(e, 1100, 0, retrigger ? 0 : 1); // original deadline
    step(e, 1599, 0, retrigger ? 0 : 1); // just before restarted deadline
    step(e, 1600, 0, 1);
    step(e, 1700, 2, 0); // reset
    step(e, 1800, 0, 0);
    lynra_plc_destroy(e);
}

static void test_edge_wiping(int retrigger) {
    LynraPlcEngine *e = lynra_plc_create();
    assert(e);
    LynraRule r;
    memset(&r, 0, sizeof(r));
    r.logic_operator = LYNRA_LOGIC_AND;
    r.condition_count = 1;
    r.conditions[0].input_index = 1;
    r.conditions[0].trigger = LYNRA_TRIGGER_RISING;
    r.action_count = 1;
    r.actions[0].type = LYNRA_TIMER_EDGE_WIPING_RELAY;
    r.actions[0].output_index = 1;
    r.actions[0].tl_ms = 100;
    r.actions[0].th_ms = 100;
    r.actions[0].n = 3;
    r.actions[0].retrigger = (uint8_t)retrigger;
    assert(lynra_plc_load_rules(e, &r, 1));

    step(e,   0, 0, 0);
    step(e, 100, 1, 0); // first trigger, OFF phase
    step(e, 200, 1, 1); // first ON phase
    step(e, 210, 0, 1);
    step(e, 250, 1, retrigger ? 0 : 1); // second trigger
    step(e, 300, 1, 0);
    step(e, 350, 0, retrigger ? 1 : 0);
    step(e, 450, 0, retrigger ? 0 : 1);
    step(e, 550, 0, retrigger ? 1 : 0);
    step(e, 700, 0, 0);
    step(e, 850, 0, 0);
    lynra_plc_destroy(e);
}

static void test_stairway(int retrigger) {
    LynraPlcEngine *e = lynra_plc_create();
    assert(e);
    LynraRule r;
    memset(&r, 0, sizeof(r));
    r.logic_operator = LYNRA_LOGIC_AND;
    r.condition_count = 1;
    r.conditions[0].input_index = 1;
    r.conditions[0].trigger = LYNRA_TRIGGER_HIGH;
    r.action_count = 1;
    r.actions[0].type = LYNRA_TIMER_STAIRWAY;
    r.actions[0].output_index = 1;
    r.actions[0].t_ms = 1000;
    r.actions[0].retrigger = (uint8_t)retrigger;
    assert(lynra_plc_load_rules(e, &r, 1));

    step(e,    0, 0, 0);
    step(e,  100, 1, 1); // first press: output ON
    step(e,  200, 0, 1); // release: countdown starts (deadline 1200)
    step(e,  600, 1, 1); // second press during countdown
    step(e,  700, 0, 1); // second release: restart only if retrigger ON
    step(e, 1199, 0, 1);
    step(e, 1200, 0, retrigger ? 1 : 0);
    step(e, 1699, 0, retrigger ? 1 : 0);
    step(e, 1700, 0, 0); // restarted deadline
    lynra_plc_destroy(e);
}

int main(void) {
    test_retentive(0);
    test_retentive(1);
    puts("RETENTIVE RETRIGGER TEST: PASS");
    test_edge_wiping(0);
    test_edge_wiping(1);
    puts("EDGE WIPING RETRIGGER TEST: PASS");
    test_stairway(0);
    test_stairway(1);
    puts("STAIRWAY RETRIGGER TEST: PASS");
    return 0;
}
