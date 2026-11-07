#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>
static void scan(LynraPlcEngine *e, uint64_t ms, uint32_t in, int expected) {
 assert(lynra_plc_scan(e,ms,in));
 if ((int)(lynra_plc_get_outputs(e)&1u)!=expected) {fprintf(stderr,"FAIL at %llu expected %d\n",(unsigned long long)ms,expected);assert(0);}
}
int main(void) {
 LynraPlcEngine *e=lynra_plc_create(); assert(e);
 LynraRule r; memset(&r,0,sizeof(r));
 r.condition_count=1; r.conditions[0].input_index=1; r.conditions[0].trigger=LYNRA_TRIGGER_HIGH;
 r.action_count=1; r.actions[0].type=LYNRA_TIMER_STAIRWAY; r.actions[0].output_index=1;
 r.actions[0].t_ms=1000; r.actions[0].warning_before_ms=300; r.actions[0].warning_off_ms=100;
 assert(lynra_plc_load_rules(e,&r,1));
 scan(e,0,0,0);scan(e,100,1,1);scan(e,300,1,1);scan(e,400,0,1);
 scan(e,1099,0,1);scan(e,1100,0,0);scan(e,1199,0,0);scan(e,1200,0,1);
 scan(e,1399,0,1);scan(e,1400,0,0);
 // Retrigger during countdown, then release starts a fresh T.
 scan(e,1500,1,1);scan(e,1600,0,1);scan(e,2200,1,1);scan(e,2300,0,1);
 scan(e,2999,0,1);scan(e,3000,0,0);scan(e,3100,0,1);scan(e,3300,0,0);
 lynra_plc_reset(e);scan(e,0,0,0);
 r.actions[0].warning_before_ms=1001;assert(!lynra_plc_load_rules(e,&r,1));
 r.actions[0].warning_before_ms=300;r.actions[0].warning_off_ms=301;assert(!lynra_plc_load_rules(e,&r,1));
 r.actions[0].warning_off_ms=100;r.actions[0].t_ms=0;assert(!lynra_plc_load_rules(e,&r,1));
 puts("STAIRWAY TEST: PASS");lynra_plc_destroy(e);return 0;
}
