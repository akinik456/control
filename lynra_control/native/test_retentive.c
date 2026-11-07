#include "lynra_PLC_engine.h"
#include <assert.h>
#include <stdio.h>
static void check(LynraPlcEngine *e, uint64_t t, uint32_t in, uint32_t expected) {
 assert(lynra_plc_scan(e,t,in));
 uint32_t got=lynra_plc_get_outputs(e);
 if(got!=expected) fprintf(stderr,"FAIL t=%llu in=%u got=%u expected=%u\n",(unsigned long long)t,in,got,expected);
 assert(got==expected);
}
int main(void) {
 LynraPlcEngine *e=lynra_plc_create(); assert(e);
 LynraRule r={0}; r.condition_count=1; r.conditions[0].input_index=1;
 r.conditions[0].trigger=LYNRA_TRIGGER_HIGH; r.action_count=1;
 r.actions[0].type=LYNRA_TIMER_RETENTIVE_ON_DELAY;
 r.actions[0].output_index=1; r.actions[0].reset_input_index=2;
 r.actions[0].t_ms=2500;
 assert(lynra_plc_load_rules(e,&r,1));
 check(e,0,0,0); check(e,100,1,0); check(e,1100,1,0);
 check(e,1200,0,0); // 1100ms accumulated
 check(e,3000,0,0); check(e,4000,1,0);
 check(e,5399,1,0); check(e,5400,1,1); // remaining 1400ms
 check(e,6000,0,1); check(e,7000,1,1); // latched
 check(e,7100,3,0); // reset priority even if trigger ON
 check(e,7200,1,0); check(e,9699,1,0); check(e,9700,1,1);
 lynra_plc_reset(e); check(e,10000,0,0);
 r.actions[0].t_ms=0;
 assert(lynra_plc_load_rules(e,&r,1));
 check(e,11000,0,0); check(e,11100,1,1);
 check(e,11200,2,0); check(e,11300,0,0);
 assert(!lynra_plc_scan(e,11299,0));
 lynra_plc_destroy(e); puts("RETENTIVE ON DELAY TEST: PASS");
 return 0;
}
