#include "lynra_PLC_engine.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static void scan(LynraPlcEngine *e, uint64_t t, uint32_t in) { assert(lynra_plc_scan(e,t,in)); }
static int out(LynraPlcEngine *e) { return (lynra_plc_get_outputs(e)&1u)!=0; }
int main(void) {
 LynraPlcEngine *e=lynra_plc_create(); assert(e);
 LynraRule r={0}; r.condition_count=1; r.conditions[0].input_index=1;
 r.conditions[0].trigger=LYNRA_TRIGGER_HIGH; r.action_count=1;
 r.actions[0].type=LYNRA_TIMER_RANDOM_GENERATOR; r.actions[0].output_index=1;
 r.actions[0].th_ms=200; r.actions[0].tl_ms=300;
 assert(lynra_plc_load_rules(e,&r,1));
 scan(e,0,0); assert(!out(e));
 scan(e,10,1); scan(e,211,1); assert(out(e));
 // No oscillation while En stays high.
 scan(e,10000,1); assert(out(e));
 scan(e,10001,0); scan(e,10302,0); assert(!out(e));
 // Opposite transition cancels pending OFF (regardless of random delay).
 scan(e,11000,1); scan(e,11201,1); assert(out(e));
 scan(e,12000,0); scan(e,12000,1); scan(e,12301,1); assert(out(e));
 // Zero bounds are immediate, including at t=0.
 r.actions[0].th_ms=0; r.actions[0].tl_ms=0;
 assert(lynra_plc_load_rules(e,&r,1));
 scan(e,0,1); assert(out(e)); scan(e,1,0); assert(!out(e));
 // Non-monotonic time rejected.
 assert(!lynra_plc_scan(e,0,0));
 lynra_plc_destroy(e);
 puts("RANDOM GENERATOR TEST: PASS");
 return 0;
}
