
#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <string.h>

static int failures = 0;

static void check(const char *name, int actual, int expected)
{
    printf("%s: %s\n", name,
           actual == expected ? "PASS" : "FAIL");

    if (actual != expected)
        failures++;
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
    rule.conditions[0].input_index = 2;
    rule.conditions[0].trigger = LYNRA_TRIGGER_HIGH;

    rule.action_count = 1;
    LynraAction *a = &rule.actions[0];
    a->type = LYNRA_THRESHOLD_TRIGGER;
    a->output_index = 1;
    a->threshold_input_index = 1;
    a->threshold_gate_ms = 1000;
    a->threshold_on = 5;
    a->threshold_off = 2;

    if (!lynra_plc_load_rules(e, &rule, 1)) {
        printf("LOAD FAILED\n");
        return 1;
    }

    // I2 sürekli HIGH, I1 darbe girişi.
    lynra_plc_scan(e, 0, 2);

    // 1 saniyede 6 darbe.
    for (int i = 0; i < 6; i++) {
        uint64_t t = 100 + (uint64_t)i * 120;
        lynra_plc_scan(e, t, 3);
        lynra_plc_scan(e, t + 20, 2);
    }

    lynra_plc_scan(e, 1000, 2);
    check("6 pulses -> Q ON",
          lynra_plc_get_outputs(e) & 1, 1);

    uint32_t count = 0;
    lynra_plc_get_threshold(e, 0, 0, &count);
    check("Measured pulses", (int)count, 6);

    // Sonraki pencerede 2 darbe.
    lynra_plc_scan(e, 1200, 3);
    lynra_plc_scan(e, 1220, 2);
    lynra_plc_scan(e, 1500, 3);
    lynra_plc_scan(e, 1520, 2);

    lynra_plc_scan(e, 2000, 2);
    check("2 pulses -> Q OFF",
          lynra_plc_get_outputs(e) & 1, 0);
					
		// Aralık kontrolü: 3 <= fa < 7
a->threshold_on = 3;
a->threshold_off = 7;

check("Range reload",
      lynra_plc_load_rules(e, &rule, 1), 1);

// İlk pencere: 5 darbe -> Q ON
lynra_plc_scan(e, 0, 2);

for (int i = 0; i < 5; i++) {
    uint64_t t = 100 + (uint64_t)i * 150;
    lynra_plc_scan(e, t, 3);
    lynra_plc_scan(e, t + 20, 2);
}

lynra_plc_scan(e, 1000, 2);
check("5 pulses in range -> Q ON",
      lynra_plc_get_outputs(e) & 1, 1);

// İkinci pencere: 8 darbe -> Q OFF
for (int i = 0; i < 8; i++) {
    uint64_t t = 1100 + (uint64_t)i * 100;
    lynra_plc_scan(e, t, 3);
    lynra_plc_scan(e, t + 20, 2);
}

lynra_plc_scan(e, 2000, 2);
check("8 pulses above range -> Q OFF",
      lynra_plc_get_outputs(e) & 1, 0);
			
// Histerezis testi
a->threshold_on = 5;
a->threshold_off = 2;

check("Hysteresis reload",
      lynra_plc_load_rules(e, &rule, 1), 1);

lynra_plc_scan(e, 0, 2);

// İlk pencere: 6 darbe
for (int i = 0; i < 6; i++) {
    uint64_t t = 100 + (uint64_t)i * 120;
    lynra_plc_scan(e, t, 3);
    lynra_plc_scan(e, t + 20, 2);
}
lynra_plc_scan(e, 1000, 2);
check("Hysteresis 6 -> ON",
      lynra_plc_get_outputs(e) & 1, 1);

// İkinci pencere: 4 darbe
for (int i = 0; i < 4; i++) {
    uint64_t t = 1100 + (uint64_t)i * 200;
    lynra_plc_scan(e, t, 3);
    lynra_plc_scan(e, t + 20, 2);
}
lynra_plc_scan(e, 2000, 2);
check("Hysteresis 4 -> HOLD ON",
      lynra_plc_get_outputs(e) & 1, 1);

// Üçüncü pencere: 2 darbe
for (int i = 0; i < 2; i++) {
    uint64_t t = 2200 + (uint64_t)i * 300;
    lynra_plc_scan(e, t, 3);
    lynra_plc_scan(e, t + 20, 2);
}
lynra_plc_scan(e, 3000, 2);
check("Hysteresis 2 -> OFF",
      lynra_plc_get_outputs(e) & 1, 0);

    lynra_plc_destroy(e);

    printf("RESULT: %s (%d failures)\n",
           failures ? "FAIL" : "PASS", failures);

    return failures ? 1 : 0;
}
