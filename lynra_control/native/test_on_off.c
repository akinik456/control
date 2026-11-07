#include "lynra_PLC_engine.h"
#include <assert.h>
#include <stdio.h>
static void check(LynraPlcEngine *e, uint64_t t, uint32_t in, uint32_t out) {
 assert(lynra_plc_scan(e,t,in));
 if (lynra_plc_get_outputs(e)!=out)
  fprintf(stderr,"FAIL t=%llu in=%u expected=%u got=%u\n",(unsigned long long)t,in,out,lynra_plc_get_outputs(e));
 assert(lynra_plc_get_outputs(e)==out);
}
int main(void) {
 LynraPlcEngine *e=lynra_plc_create(); assert(e);
 LynraRule r={0}; r.condition_count=1; r.conditions[0].input_index=1;
 r.conditions[0].trigger=LYNRA_TRIGGER_HIGH; r.action_count=1;
 r.actions[0].type=LYNRA_TIMER_ON_OFF_DELAY; r.actions[0].output_index=1;
 r.actions[0].th_ms=2500; r.actions[0].tl_ms=3500;
 assert(lynra_plc_load_rules(e,&r,1));
 check(e,0,0,0); check(e,100,1,0); check(e,2599,1,0); check(e,2600,1,1);
 check(e,2700,0,1); check(e,6199,0,1); check(e,6200,0,0);
 // Rising edge aborted before TH expires, then full TH restarts.
 check(e,7000,1,0); check(e,8000,0,0); check(e,9000,1,0);
 check(e,11499,1,0); check(e,11500,1,1);
 // Falling edge aborted before TL expires.
 check(e,12000,0,1); check(e,13000,1,1); check(e,14000,0,1);
 check(e,17499,0,1); check(e,17500,0,0);
 lynra_plc_reset(e); check(e,18000,0,0);
 r.actions[0].th_ms=0; r.actions[0].tl_ms=0;
 assert(lynra_plc_load_rules(e,&r,1));
 check(e,19000,0,0); check(e,19100,1,1); check(e,19200,0,0);
 assert(!lynra_plc_scan(e,19199,0));
 lynra_plc_destroy(e); puts("ON/OFF DELAY TEST: PASS"); return 0;
}
