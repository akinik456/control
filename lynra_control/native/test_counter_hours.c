#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

#define EN  (1u << 0)  // I1
#define R   (1u << 1)  // I2
#define RAL (1u << 2)  // I3

int main(void)
{
    int failures = 0;
    LynraPlcEngine *e = lynra_plc_create();
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
    a->type = LYNRA_COUNTER_HOURS;
    a->output_index = 1;
    a->hours_enable_input_index = 1;
    a->reset_input_index = 2;
    a->hours_reset_all_input_index = 3;
    a->hours_target_ms = 3000;

    if (!lynra_plc_load_rules(e, &rule, 1)) {
        printf("FAIL: load rules\n");
        lynra_plc_destroy(e);
        return 1;
    }

    const struct {
        uint64_t time;
        uint32_t inputs;
        uint64_t cv;
        uint64_t total;
        bool q;
    } tests[] = {
        {   0, 0,  0,    0,    false },
        {1000, EN, 0,    0,    false },
        {2000, EN, 1000, 1000, false },
        {4000, EN, 3000, 3000, true  },
        {5000, 0,  3000, 3000, true  },
        {6000, R,  0,    3000, false },
        {7000, EN, 0,    3000, false },
        {8000, EN, 1000, 4000, false },
        {9000, RAL,0,    0,    false }
    };

    for (size_t i = 0; i < sizeof(tests)/sizeof(tests[0]); i++) {
        uint64_t cv = 0, total = 0;

        bool scan_ok = lynra_plc_scan(
            e, tests[i].time, tests[i].inputs);

        bool read_ok = lynra_plc_get_hours(
            e, 0, 0, &cv, &total);

        bool q = (lynra_plc_get_outputs(e) & 1u) != 0;

        if (!scan_ok || !read_ok ||
            cv != tests[i].cv ||
            total != tests[i].total ||
            q != tests[i].q) {
            printf("FAIL: step %u CV=%llu Total=%llu Q=%d\n",
                   (unsigned)i,
                   (unsigned long long)cv,
                   (unsigned long long)total, q);
            failures++;
        }
    }
// Fresh start
lynra_plc_reset(e);

// EN + R: CV=0, Total birikmeye devam eder
lynra_plc_scan(e, 10000, EN | R);
lynra_plc_scan(e, 11000, EN | R);

uint64_t cv = 0, total = 0;
lynra_plc_get_hours(e, 0, 0, &cv, &total);

if (cv != 0 || total != 1000)
    failures++;

// R bırakılır, EN aktif kalır
lynra_plc_scan(e, 12000, EN);
lynra_plc_get_hours(e, 0, 0, &cv, &total);

if (cv != 1000 || total != 2000)
    failures++;

// EN + Ral: her iki sayaç sıfırlanır
lynra_plc_scan(e, 13000, EN | RAL);
lynra_plc_get_hours(e, 0, 0, &cv, &total);

if (cv != 0 || total != 0 ||
    (lynra_plc_get_outputs(e) & 1u))
    failures++;
    lynra_plc_destroy(e);

    printf("HOURS COUNTER TEST: %s (%d failures)\n",
           failures == 0 ? "PASS" : "FAIL", failures);

    return failures ? 1 : 0;
}