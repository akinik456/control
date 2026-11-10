
#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <string.h>

static int failures = 0;

static void check(const char *name, int ok)
{
    printf("%s: %s\n", name, ok ? "PASS" : "FAIL");
    if (!ok) failures++;
}

int main(void)
{
    LynraPlcEngine *e = lynra_plc_create();
    if (!e) {
        printf("Engine create: FAIL\n");
        return 1;
    }

    LynraRule rules[2];
    memset(rules, 0, sizeof(rules));

    // Rule 0: OnDelay + OffDelay
    rules[0].id = 100;
    rules[0].logic_operator = LYNRA_LOGIC_AND;
    rules[0].run_policy = LYNRA_RUN_ONCE;
    rules[0].condition_count = 1;
    rules[0].conditions[0].input_index = 1;
    rules[0].conditions[0].trigger = LYNRA_TRIGGER_HIGH;
    rules[0].action_count = 2;

    rules[0].actions[0].type = LYNRA_TIMER_ON_DELAY;
    rules[0].actions[0].output_index = 1;
    rules[0].actions[0].t_ms = 1000;

    rules[0].actions[1].type = LYNRA_TIMER_OFF_DELAY;
    rules[0].actions[1].output_index = 2;
    rules[0].actions[1].t_ms = 2000;

    // Rule 1: Up/Down Counter
    rules[1].id = 200;
    rules[1].logic_operator = LYNRA_LOGIC_AND;
    rules[1].run_policy = LYNRA_RUN_ONCE;
    rules[1].condition_count = 1;
    rules[1].conditions[0].input_index = 2;
    rules[1].conditions[0].trigger = LYNRA_TRIGGER_HIGH;
    rules[1].action_count = 1;

    rules[1].actions[0].type = LYNRA_COUNTER_UP_DOWN;
    rules[1].actions[0].output_index = 3;
    rules[1].actions[0].counter_input_index = 2;
    rules[1].actions[0].counter_start_value = 0;
    rules[1].actions[0].counter_on = 10;
    rules[1].actions[0].counter_off = 5;

    check("Load 2 rules",
          lynra_plc_load_rules(e, rules, 2));

    check("Rule count = 2",
          lynra_plc_get_rule_count(e) == 2);

    size_t count = 0;
    LynraActionType type;

    check("Rule 0 action count = 2",
          lynra_plc_get_action_info(e, 0, 0, NULL, &count)
          && count == 2);

    check("Rule 0 action 0 = OnDelay",
          lynra_plc_get_action_info(e, 0, 0, &type, NULL)
          && type == LYNRA_TIMER_ON_DELAY);

    check("Rule 0 action 1 = OffDelay",
          lynra_plc_get_action_info(e, 0, 1, &type, NULL)
          && type == LYNRA_TIMER_OFF_DELAY);

    check("Rule 1 action count = 1",
          lynra_plc_get_action_info(e, 1, 0, NULL, &count)
          && count == 1);

    check("Rule 1 action 0 = Counter",
          lynra_plc_get_action_info(e, 1, 0, &type, NULL)
          && type == LYNRA_COUNTER_UP_DOWN);

    check("Invalid rule rejected",
          !lynra_plc_get_action_info(e, 2, 0, &type, NULL));

    check("Invalid action rejected",
          !lynra_plc_get_action_info(e, 1, 1, &type, NULL));

    check("Null engine rejected",
          !lynra_plc_get_action_info(NULL, 0, 0, &type, NULL));

LynraParameters params;

check("OnDelay get_parameters",
      lynra_plc_get_parameters(e, 0, 0, &params));

check("OnDelay parameter count = 1",
      params.count == 1);

check("OnDelay parameter = TON",
      params.items[0].id == LYNRA_FIELD_TON_MS);

check("OnDelay TON = 1000",
      params.items[0].value == 1000);

check("Invalid action parameters rejected",
      !lynra_plc_get_parameters(e, 0, 2, &params));

LynraValues values;

check("OnDelay get_values",
      lynra_plc_get_values(e, 0, 0, &values));

check("OnDelay values count = 3",
      values.count == 3);

check("Elapsed field",
      values.items[0].id == LYNRA_FIELD_ELAPSED_MS);

check("Trigger count field",
      values.items[1].id == LYNRA_FIELD_TRIGGER_COUNT);

check("Completion count field",
      values.items[2].id == LYNRA_FIELD_COMPLETION_COUNT);

check("Initial elapsed = 0",
      values.items[0].value == 0);

check("Initial trigger count = 0",
      values.items[1].value == 0);

check("Initial completion count = 0",
      values.items[2].value == 0);

// OnDelay: TON = 1000 ms
check("Scan start",
      lynra_plc_scan(e, 1000, 0x01));

check("Values at start",
      lynra_plc_get_values(e, 0, 0, &values) &&
      values.items[0].value == 0 &&
      values.items[1].value == 1 &&
      values.items[2].value == 0);

check("Scan at 1500 ms",
      lynra_plc_scan(e, 1500, 0x01));

check("Values at 500 ms",
      lynra_plc_get_values(e, 0, 0, &values) &&
      values.items[0].value == 500 &&
      values.items[1].value == 1 &&
      values.items[2].value == 0);

check("Scan at 2000 ms",
      lynra_plc_scan(e, 2000, 0x01));

check("Values at completion",
      lynra_plc_get_values(e, 0, 0, &values) &&
      values.items[0].value == 1000 &&
      values.items[1].value == 1 &&
      values.items[2].value == 1);

check("Scan after completion",
      lynra_plc_scan(e, 2500, 0x01));

check("Completion not duplicated",
      lynra_plc_get_values(e, 0, 0, &values) &&
      values.items[1].value == 1 &&
      values.items[2].value == 1);
// Önceki test sonunda zaman = 2500 ms, I1 = HIGH

check("Set TON = 2000",
      lynra_plc_set_parameter(
          e, 0, 0, LYNRA_FIELD_TON_MS, 2000));

check("Read updated TON",
      lynra_plc_get_parameters(e, 0, 0, &params) &&
      params.count == 1 &&
      params.items[0].value == 2000);

// Yeni tetikleme
check("Deactivate I1",
      lynra_plc_scan(e, 3000, 0));

check("Reactivate I1",
      lynra_plc_scan(e, 3500, 1));

check("Scan after 1000 ms",
      lynra_plc_scan(e, 4500, 1));

check("TON 2000 not completed",
      lynra_plc_get_values(e, 0, 0, &values) &&
      values.items[0].value == 1000 &&
      values.items[1].value == 2 &&
      values.items[2].value == 1);

check("Scan after 2000 ms",
      lynra_plc_scan(e, 5500, 1));

check("TON 2000 completed",
      lynra_plc_get_values(e, 0, 0, &values) &&
      values.items[0].value == 2000 &&
      values.items[1].value == 2 &&
      values.items[2].value == 2);

// Program bağlantılarını değiştirmeye izin yok
check("Reject input modification",
      !lynra_plc_set_parameter(
          e, 0, 0, LYNRA_FIELD_INPUT, 2));			

    lynra_plc_destroy(e);

    printf("\nRESULT: %s (%d failures)\n",
           failures == 0 ? "PASS" : "FAIL", failures);

    return failures ? 1 : 0;
}
