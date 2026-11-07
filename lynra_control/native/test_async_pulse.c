#include "lynra_PLC_engine.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static void check(LynraPlcEngine *e, uint64_t t, uint32_t input, uint32_t output) {
 assert(lynra_plc_scan(e, t, input));
 assert(lynra_plc_get_outputs(e) == output);
}
int main(void) {
 LynraPlcEngine *e = lynra_plc_create(); assert(e);
 LynraRule r; memset(&r, 0, sizeof(r));
 r.condition_count = 1; r.conditions[0].input_index = 1;
 r.conditions[0].trigger = LYNRA_TRIGGER_HIGH;
 r.action_count = 1; r.actions[0].type = LYNRA_TIMER_ASYNC_PULSE;
 r.actions[0].output_index = 1; r.actions[0].th_ms = 200; r.actions[0].tl_ms = 100;
 assert(lynra_plc_load_rules(e, &r, 1));
 check(e, 0, 0, 0); check(e, 100, 1, 1);
 check(e, 299, 1, 1); check(e, 300, 1, 0);
 check(e, 399, 1, 0); check(e, 400, 1, 1);
 check(e, 600, 1, 0); check(e, 700, 1, 1);
 check(e, 750, 0, 0); check(e, 800, 1, 1);
 check(e, 999, 1, 1); check(e, 1000, 1, 0);
 lynra_plc_reset(e); check(e, 0, 1, 1); check(e, 200, 1, 0);
 r.actions[0].th_ms = 0; assert(!lynra_plc_load_rules(e, &r, 1));
 r.actions[0].th_ms = 200; r.actions[0].tl_ms = 0;
 assert(!lynra_plc_load_rules(e, &r, 1));
 lynra_plc_destroy(e);
 puts("ASYNC PULSE TEST: PASS");
 return 0;
}
