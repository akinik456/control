
#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <string.h>

static int failures = 0;

static void check(const char *name, int64_t actual, int64_t expected)
{
    int pass = actual == expected;
    printf("%s: %s\n", name, pass ? "PASS" : "FAIL");
    if (!pass) failures++;
}

static void check_field(
    LynraPlcEngine *e,
    const char *name,
    LynraFieldId field,
    int64_t expected)
{
    LynraFieldValue value = -1;
    bool ok = lynra_plc_get_field(e, 0, 0, field, &value);

    check(name, ok ? value : -1, expected);
}

int main(void)
{
    LynraPlcEngine *e = lynra_plc_create();
    if (!e) return 1;

    LynraRule rule;
    memset(&rule, 0, sizeof(rule));

    rule.logic_operator = LYNRA_LOGIC_AND;
    rule.run_policy = LYNRA_RUN_ONCE;
    rule.condition_count = 1;
    rule.conditions[0].input_index = 1;
    rule.conditions[0].trigger = LYNRA_TRIGGER_HIGH;

    rule.action_count = 1;
    rule.actions[0].type = LYNRA_TIMER_ON_DELAY;
    rule.actions[0].output_index = 1;
    rule.actions[0].t_ms = 1000;

    if (!lynra_plc_load_rules(e, &rule, 1)) {
        printf("LOAD FAILED\n");
        lynra_plc_destroy(e);
        return 1;
    }

    check_field(e, "Ton = 1000",
                LYNRA_FIELD_TON_MS, 1000);

    lynra_plc_scan(e, 0, 0);
    lynra_plc_scan(e, 100, 1);

    check_field(e, "Trigger #1",
                LYNRA_FIELD_TRIGGER_COUNT, 1);

    lynra_plc_scan(e, 1099, 1);
    check_field(e, "Before Ton -> Q OFF",
                LYNRA_FIELD_OUTPUT, 0);

    lynra_plc_scan(e, 1100, 1);
    check_field(e, "Completion #1",
                LYNRA_FIELD_COMPLETION_COUNT, 1);
    check_field(e, "After Ton -> Q ON",
                LYNRA_FIELD_OUTPUT, 1);

    lynra_plc_scan(e, 1500, 1);
    check_field(e, "No duplicate completion",
                LYNRA_FIELD_COMPLETION_COUNT, 1);

    lynra_plc_scan(e, 1600, 0);
    lynra_plc_scan(e, 1700, 1);

    check_field(e, "Trigger #2",
                LYNRA_FIELD_TRIGGER_COUNT, 2);

    lynra_plc_scan(e, 2700, 1);
    check_field(e, "Completion #2",
                LYNRA_FIELD_COMPLETION_COUNT, 2);
								
		check("Set Ton = 2000",
      lynra_plc_set_field(e, 0, 0,
          LYNRA_FIELD_TON_MS, 2000), 1);

check_field(e, "Read Ton = 2000",
            LYNRA_FIELD_TON_MS, 2000);

lynra_plc_scan(e, 2800, 0);
lynra_plc_scan(e, 3000, 1);

check_field(e, "Trigger #3",
            LYNRA_FIELD_TRIGGER_COUNT, 3);

lynra_plc_scan(e, 4000, 1);
check_field(e, "New Ton: Q still OFF",
            LYNRA_FIELD_OUTPUT, 0);

lynra_plc_scan(e, 5000, 1);
check_field(e, "New Ton: Q ON",
            LYNRA_FIELD_OUTPUT, 1);

check_field(e, "Completion #3",
            LYNRA_FIELD_COMPLETION_COUNT, 3);
						
check_field(e, "Input = I1",
            LYNRA_FIELD_INPUT, 1);

check_field(e, "Trigger = HIGH",
            LYNRA_FIELD_TRIGGER_MODE,
            LYNRA_TRIGGER_HIGH);
// Yeni çevrim: Ton = 2000 ms
lynra_plc_scan(e, 5100, 0);
lynra_plc_scan(e, 5200, 1);

check_field(e, "Elapsed = 0",
            LYNRA_FIELD_ELAPSED_MS, 0);

lynra_plc_scan(e, 5700, 1);
check_field(e, "Elapsed = 500",
            LYNRA_FIELD_ELAPSED_MS, 500);

lynra_plc_scan(e, 6200, 1);
check_field(e, "Elapsed = 1000",
            LYNRA_FIELD_ELAPSED_MS, 1000);

lynra_plc_scan(e, 7200, 1);
check_field(e, "Elapsed = 2000",
            LYNRA_FIELD_ELAPSED_MS, 2000);

lynra_plc_scan(e, 7500, 1);
check_field(e, "Elapsed capped at Ton",
            LYNRA_FIELD_ELAPSED_MS, 2000);

lynra_plc_scan(e, 7600, 0);
check_field(e, "Elapsed reset = 0",
            LYNRA_FIELD_ELAPSED_MS, 0);
lynra_plc_scan(e, 7700, 0x00000005);

check("Inputs I1+I3",
      lynra_plc_get_inputs(e), 0x00000005);

check("Outputs Q1",
      lynra_plc_get_outputs(e) & 1u, 0);						
    lynra_plc_destroy(e);

    printf("RESULT: %s (%d failures)\n",
           failures ? "FAIL" : "PASS", failures);

    return failures ? 1 : 0;
}
