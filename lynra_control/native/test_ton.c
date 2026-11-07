#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <assert.h>
static void scan(LynraPlcEngine *e, uint64_t t, uint32_t in, uint32_t out) {
 assert(lynra_plc_scan(e,t,in)); assert(lynra_plc_get_outputs(e)==out);
}
int main(void) {
 LynraPlcEngine *e=lynra_plc_create(); assert(e);
 LynraRule r={0}; r.condition_count=1; r.conditions[0].input_index=1;
 r.conditions[0].trigger=LYNRA_TRIGGER_HIGH; r.action_count=1;
 r.actions[0].type=LYNRA_TIMER_ON_DELAY; r.actions[0].output_index=1; r.actions[0].t_ms=2500;
 assert(lynra_plc_load_rules(e,&r,1));
 scan(e,0,0,0); scan(e,100,1,0); scan(e,2599,1,0); scan(e,2600,1,1);
 scan(e,2700,0,0); scan(e,3000,1,0); scan(e,5499,1,0); scan(e,5500,1,1);
 lynra_plc_reset(e); scan(e,5600,0,0);
 assert(!lynra_plc_scan(e,5599,0));
 r.actions[0].t_ms=0; assert(lynra_plc_load_rules(e,&r,1)); scan(e,6000,1,1); scan(e,6001,0,0);
 r.actions[0].type=LYNRA_TIMER_OFF_DELAY; assert(!lynra_plc_load_rules(e,&r,1));
 lynra_plc_destroy(e); puts("TON TEST: PASS"); return 0;
}
