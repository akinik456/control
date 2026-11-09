
#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

#define CNT (1u << 0)  // I1
#define DIR (1u << 1)  // I2
#define RST (1u << 2)  // I3

static LynraPlcEngine *e;
static uint64_t now_ms = 0;
static int failures = 0;

static void check(int32_t expected_cv, bool expected_q)
{
    int32_t cv = 0;
    bool read_ok = lynra_plc_get_counter(e, 0, 0, &cv);
    bool q = (lynra_plc_get_outputs(e) & 1u) != 0;

    if (!read_ok || cv != expected_cv || q != expected_q) {
        printf("FAIL: CV=%ld expected=%ld Q=%d expected=%d\n",
               (long)cv, (long)expected_cv, q, expected_q);
        failures++;
    }
}

static void scan(uint32_t inputs)
{
    now_ms += 100;
    if (!lynra_plc_scan(e, now_ms, inputs)) {
        printf("FAIL: scan\n");
        failures++;
    }
}

int main(void)
{
    e = lynra_plc_create();
    if (!e) return 1;

    LynraRule rule = {0};
    rule.id = 1;
    rule.logic_operator = LYNRA_LOGIC_AND;
    rule.run_policy = LYNRA_RUN_REPEAT;
    rule.condition_count = 1;
    rule.conditions[0].input_index = 1;
    rule.conditions[0].trigger = LYNRA_TRIGGER_HIGH;
    rule.action_count = 1;

    LynraAction *a = &rule.actions[0];
    a->type = LYNRA_COUNTER_UP_DOWN;
    a->output_index = 1;
    a->counter_input_index = 1;
    a->direction_input_index = 2;
    a->reset_input_index = 3;
    a->counter_start_value = 0;
    a->counter_on = 3;
    a->counter_off = 2;

    if (!lynra_plc_load_rules(e, &rule, 1)) {
        printf("FAIL: load rules\n");
        return 1;
    }

    check(0, false);

    // Count UP: 0 -> 1 -> 2 -> 3
    for (int i = 1; i <= 3; i++) {
        scan(CNT);
        check(i, i >= 3);
        scan(0);
        check(i, i >= 3);
    }

    // Count DOWN: 3 -> 2 (Q stays ON)
    scan(DIR | CNT);
    check(2, true);
    scan(DIR);
    check(2, true);

    // Count DOWN: 2 -> 1 (Q turns OFF)
    scan(DIR | CNT);
    check(1, false);
    scan(DIR);

    // RESET returns to StartVal
    scan(RST);
    check(0, false);
    scan(RST | CNT);
    check(0, false);
    scan(0);

    // New count after RESET
    scan(CNT);
    check(1, false);

    // Engine reset
    lynra_plc_reset(e);
    check(0, false);
		
		// Reverse thresholds: On=1, Off=3
a->counter_on = 1;
a->counter_off = 3;
a->counter_start_value = 4;

if (!lynra_plc_load_rules(e, &rule, 1)) {
    printf("FAIL: reverse threshold load\n");
    return 1;
}

check(4, false);

// DOWN: 4 -> 3 -> 2 -> 1
scan(DIR | CNT);
check(3, false);
scan(DIR);

scan(DIR | CNT);
check(2, false);
scan(DIR);

scan(DIR | CNT);
check(1, true);
scan(DIR);

// UP: 1 -> 2 -> 3 -> 4
scan(CNT);
check(2, true);
scan(0);

scan(CNT);
check(3, true);
scan(0);

scan(CNT);
check(4, false);

// Upper boundary: INT32_MAX
a->counter_start_value = INT32_MAX;

if (!lynra_plc_load_rules(e, &rule, 1))
    return 1;

check(INT32_MAX, false);

scan(CNT);
check(INT32_MAX, false);
scan(0);

// Lower boundary: INT32_MIN
a->counter_start_value = INT32_MIN;

if (!lynra_plc_load_rules(e, &rule, 1))
    return 1;

check(INT32_MIN, false);

scan(DIR | CNT);
check(INT32_MIN, true);
scan(DIR);

    lynra_plc_destroy(e);

    printf("\nUP/DOWN COUNTER TEST: %s (%d failures)\n",
           failures == 0 ? "PASS" : "FAIL", failures);

    return failures == 0 ? 0 : 1;
}
