#include "lynra_PLC_engine.h"
#include <assert.h>
#include <stdio.h>
static void scan(LynraPlcEngine *e, uint64_t t, uint32_t in, uint32_t out) {
 assert(lynra_plc_scan(e,t,in));
 if (lynra_plc_get_outputs(e)!=out) fprintf(stderr,"FAIL t=%llu in=%u expected=%u got=%u\n",(unsigned long long)t,in,out,lynra_plc_get_outputs(e));
 assert(lynra_plc_get_outputs(e)==out);
}
int main(void) {
 LynraPlcEngine *e=lynra_plc_create(); assert(e);
 LynraRule r={0}; r.condition_count=1; r.conditions[0].input_index=1;
 r.conditions[0].trigger=LYNRA_TRIGGER_HIGH; r.action_count=1;
 r.actions[0].type=LYNRA_TIMER_OFF_DELAY; r.actions[0].output_index=1; r.actions[0].t_ms=3500;
 assert(lynra_plc_load_rules(e,&r,1));
 scan(e,0,0,0); scan(e,100,1,1); scan(e,200,0,1);
 scan(e,3699,0,1); scan(e,3700,0,0);
 scan(e,4000,1,1); scan(e,4100,0,1); scan(e,5000,1,1);
 scan(e,5100,0,1); scan(e,8599,0,1); scan(e,8600,0,0);
 scan(e,9000,0,0); scan(e,9100,1,1);
 lynra_plc_reset(e); scan(e,9200,0,0);
 assert(!lynra_plc_scan(e,9199,0));
 r.actions[0].t_ms=0; assert(lynra_plc_load_rules(e,&r,1));
 scan(e,10000,0,0); scan(e,10100,1,1); scan(e,10200,0,0);
 lynra_plc_destroy(e); puts("TOF TEST: PASS"); return 0;
}
