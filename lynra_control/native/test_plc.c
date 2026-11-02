
#include <stdio.h>
#include <string.h>
#include "lynra_PLC_engine.h"


static int test_failures = 0;

static void check_output(
    const char* test_name,
    LynraPlcEngine* engine,
    unsigned expected)
{
       unsigned actual =
           (unsigned)(lynra_plc_get_outputs(engine) & 1u);

       if (actual == expected) {
              printf("[PASS] %s\n", test_name);
       } else {
              printf("[FAIL] %s expected=%u actual=%u\n",
                     test_name, expected, actual);
              test_failures++;
       }
}


int main(void)
{
    LynraPlcEngine* engine = lynra_plc_create();

    if (engine == NULL) {
        printf("Engine create FAILED\n");
        return 1;
    }

    LynraRule rule = {0};

    rule.logic_operator = LYNRA_LOGIC_AND;
    rule.output_behavior = LYNRA_OUTPUT_LATCH;
    rule.run_policy = LYNRA_RUN_ONCE;

    rule.condition_count = 1;
    rule.conditions[0].input_index = 1;
    rule.conditions[0].trigger = LYNRA_TRIGGER_HIGH;

    rule.action_count = 1;
    rule.actions[0].type = LYNRA_ACTION_SET;
    rule.actions[0].output_index = 1;

    if (!lynra_plc_load_rules(engine, &rule, 1)) {
        printf("Load rules FAILED\n");
        return 1;
    }


       lynra_plc_scan(engine, 0, 0);
       check_output("I1 OFF -> Q1 OFF", engine, 0);

       lynra_plc_scan(engine, 100, 1);
       check_output("SET: I1 ON -> Q1 ON", engine, 1);

       lynra_plc_scan(engine, 200, 0);
    check_output("SET LATCH: I1 OFF", engine, 1);


    LynraRule reset_rule = {0};

    reset_rule.logic_operator = LYNRA_LOGIC_AND;
    reset_rule.output_behavior = LYNRA_OUTPUT_LATCH;
    reset_rule.run_policy = LYNRA_RUN_ONCE;

    reset_rule.condition_count = 1;
    reset_rule.conditions[0].input_index = 2;
    reset_rule.conditions[0].trigger = LYNRA_TRIGGER_HIGH;

    reset_rule.action_count = 1;
    reset_rule.actions[0].type = LYNRA_ACTION_RESET;
    reset_rule.actions[0].output_index = 1;

    LynraRule rules[2] = {reset_rule, rule};

    lynra_plc_load_rules(engine, rules, 2);

    lynra_plc_scan(engine, 300, 0);
    lynra_plc_scan(engine, 400, 3);
    check_output("RESET priority: 400ms", engine, 0);

    lynra_plc_scan(engine, 500, 0);
    lynra_plc_scan(engine, 600, 1);



       check_output("SET after RESET: 600ms", engine, 1);


    LynraRule delay_rule = {0};

    delay_rule.logic_operator = LYNRA_LOGIC_AND;
    delay_rule.output_behavior = LYNRA_OUTPUT_LATCH;
    delay_rule.run_policy = LYNRA_RUN_ONCE;

    delay_rule.condition_count = 1;
    delay_rule.conditions[0].input_index = 1;
    delay_rule.conditions[0].trigger = LYNRA_TRIGGER_RISING;

    delay_rule.action_count = 2;

    delay_rule.actions[0].type = LYNRA_ACTION_DELAY;
    delay_rule.actions[0].duration_ms = 500;

    delay_rule.actions[1].type = LYNRA_ACTION_SET;
    delay_rule.actions[1].output_index = 1;

    lynra_plc_load_rules(engine, &delay_rule, 1);

    lynra_plc_scan(engine, 0, 1);
    check_output("DELAY: 0ms", engine, 0);

    lynra_plc_scan(engine, 400, 0);
    check_output("DELAY: 400ms", engine, 0);

    lynra_plc_scan(engine, 500, 1);
    check_output("DELAY: 500ms", engine, 1);


       LynraRule toggle_rule = {0};

       toggle_rule.logic_operator = LYNRA_LOGIC_AND;
       toggle_rule.run_policy = LYNRA_RUN_ONCE;
       toggle_rule.output_behavior = LYNRA_OUTPUT_LATCH;

       toggle_rule.condition_count = 1;
       toggle_rule.conditions[0].input_index = 1;
       toggle_rule.conditions[0].trigger = LYNRA_TRIGGER_RISING;

       toggle_rule.action_count = 1;
       toggle_rule.actions[0].on_delay_ms = 300;
       toggle_rule.actions[0].type = LYNRA_ACTION_TOGGLE;
       toggle_rule.actions[0].output_index = 1;

       lynra_plc_load_rules(engine, &toggle_rule, 1);

       lynra_plc_scan(engine, 0, 0);
       lynra_plc_scan(engine, 100, 1);
       check_output("TOGGLE ON DELAY: 100ms", engine, 0);

       lynra_plc_scan(engine, 399, 1);
       check_output("TOGGLE ON DELAY: 399ms", engine, 0);

       lynra_plc_scan(engine, 400, 1);
       check_output("TOGGLE ON DELAY: 400ms", engine, 1);

       LynraRule delayed_set = {0};
       delayed_set.logic_operator = LYNRA_LOGIC_AND;
       delayed_set.run_policy = LYNRA_RUN_ONCE;
       delayed_set.output_behavior = LYNRA_OUTPUT_LATCH;
       delayed_set.condition_count = 1;
       delayed_set.conditions[0].input_index = 1;
       delayed_set.conditions[0].trigger = LYNRA_TRIGGER_RISING;
       delayed_set.action_count = 1;
       delayed_set.actions[0].type = LYNRA_ACTION_SET;
       delayed_set.actions[0].output_index = 1;
       delayed_set.actions[0].on_delay_ms = 300;

       LynraRule immediate_reset = {0};
       immediate_reset.logic_operator = LYNRA_LOGIC_AND;
       immediate_reset.run_policy = LYNRA_RUN_ONCE;
       immediate_reset.output_behavior = LYNRA_OUTPUT_LATCH;
       immediate_reset.condition_count = 1;
       immediate_reset.conditions[0].input_index = 2;
       immediate_reset.conditions[0].trigger = LYNRA_TRIGGER_RISING;
       immediate_reset.action_count = 1;
       immediate_reset.actions[0].type = LYNRA_ACTION_RESET;
       immediate_reset.actions[0].output_index = 1;


       LynraRule initial_set = {0};

       initial_set.logic_operator = LYNRA_LOGIC_AND;
       initial_set.run_policy = LYNRA_RUN_ONCE;
       initial_set.output_behavior = LYNRA_OUTPUT_LATCH;

       initial_set.condition_count = 1;
       initial_set.conditions[0].input_index = 3;
       initial_set.conditions[0].trigger = LYNRA_TRIGGER_RISING;

       initial_set.action_count = 1;
       initial_set.actions[0].type = LYNRA_ACTION_SET;
       initial_set.actions[0].output_index = 1;

       LynraRule safety_rules[3] = {
              initial_set, delayed_set, immediate_reset
          };

       lynra_plc_load_rules(engine, safety_rules, 3);


       lynra_plc_scan(engine, 0, 0);

       // I3 ile Q1'i başlangıçta aç.
       lynra_plc_scan(engine, 10, 4);
       check_output("INITIAL SET: 10ms", engine, 1);

       // I3 kapanıyor, I1 gecikmeli SET başlatıyor.
       lynra_plc_scan(engine, 100, 1);
       check_output("INITIAL SET: 100ms", engine, 1);

       // I2 RESET komutu veriyor.
       lynra_plc_scan(engine, 200, 3);
       check_output("RESET: 200ms", engine, 0);

       // Gecikmeli SET'in süresi doluyor.
       lynra_plc_scan(engine, 400, 3);
       check_output("RESET: 400ms", engine, 0);

    lynra_plc_destroy(engine);
    printf("\nRESULT: %s (%d failures)\n",
           test_failures ? "FAIL" : "PASS", test_failures);
    return test_failures ? 1 : 0;
}
