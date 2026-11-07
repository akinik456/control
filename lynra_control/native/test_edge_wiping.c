#include "lynra_PLC_engine.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static void check(LynraPlcEngine *e, uint64_t ms, unsigned in, unsigned expected) {
 assert(lynra_plc_scan(e, ms, in));
 assert(lynra_plc_get_outputs(e) == expected);
}
int main(void) {
 LynraPlcEngine *e = lynra_plc_create(); assert(e);
 LynraRule r; memset(&r, 0, sizeof(r));
 r.condition_count = 1; r.conditions[0].input_index = 1;
 r.conditions[0].trigger = LYNRA_TRIGGER_HIGH;
 r.action_count = 1; r.actions[0].type = LYNRA_TIMER_EDGE_WIPING_RELAY;
 r.actions[0].output_index = 1; r.actions[0].th_ms = 200; r.actions[0].tl_ms = 100; r.actions[0].n = 3;
 assert(lynra_plc_load_rules(e, &r, 1));
 check(e, 0, 0, 0); check(e, 10, 1, 1); check(e, 209, 1, 1);
 check(e, 210, 1, 0); check(e, 309, 1, 0); check(e, 310, 1, 1);
 check(e, 410, 0, 1); check(e, 510, 0, 0); check(e, 610, 0, 1);
 check(e, 810, 0, 0); check(e, 900, 0, 0);
 // Rising edge retriggers a running train.
 check(e, 1000, 1, 1); check(e, 1100, 0, 1);
 check(e, 1150, 1, 1); check(e, 1349, 1, 1); check(e, 1350, 1, 0);
 // Reset cancels pulse train.
 lynra_plc_reset(e); check(e, 2000, 0, 0);
 // Invalid pulse parameters rejected.
 r.actions[0].n = 0; assert(!lynra_plc_load_rules(e, &r, 1));
 r.actions[0].n = 10; assert(!lynra_plc_load_rules(e, &r, 1));
 r.actions[0].n = 1; r.actions[0].th_ms = 0; assert(!lynra_plc_load_rules(e, &r, 1));
 puts("EDGE WIPING RELAY TEST: PASS");
 lynra_plc_destroy(e); return 0;
}
