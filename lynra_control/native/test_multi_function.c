#include "lynra_PLC_engine.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static void step(LynraPlcEngine *e, uint64_t t, uint32_t in, int expected) {
 assert(lynra_plc_scan(e,t,in));
 if (!!(lynra_plc_get_outputs(e)&1u) != expected) {
  fprintf(stderr,"FAIL t=%llu input=%u expected=%d\n",(unsigned long long)t,in,expected);
  assert(0);
 }
}
int main(void) {
 LynraPlcEngine *e=lynra_plc_create(); assert(e);
 LynraRule r; memset(&r,0,sizeof r);
 r.logic_operator=LYNRA_LOGIC_AND;
 r.condition_count=1; r.conditions[0].input_index=1; r.conditions[0].trigger=LYNRA_TRIGGER_HIGH;
 r.action_count=1; r.actions[0].type=LYNRA_TIMER_MULTI_FUNCTION;
 r.actions[0].output_index=1; r.actions[0].t_ms=1000; r.actions[0].tl_ms=500;
 r.actions[0].warning_before_ms=300; r.actions[0].warning_off_ms=100;
 assert(lynra_plc_load_rules(e,&r,1));
 step(e,0,0,0); step(e,100,1,1); step(e,200,0,1); // short press
 step(e,899,0,1); step(e,900,0,0); step(e,1000,0,1); // warning
 step(e,1199,0,1); step(e,1200,0,0); // T expired
 step(e,1300,1,1); step(e,1800,1,1); // long press -> permanent
 step(e,1900,0,1); step(e,5000,0,1);
 step(e,5100,1,0); step(e,5200,0,0); // next press OFF
 step(e,5300,1,1); step(e,5400,0,1);
 step(e,5500,1,0); step(e,5600,0,0); // cancel timed
 lynra_plc_reset(e); step(e,0,0,0);
 r.actions[0].tl_ms=0; assert(!lynra_plc_load_rules(e,&r,1));
 r.actions[0].tl_ms=500; r.actions[0].warning_before_ms=1100;
 assert(!lynra_plc_load_rules(e,&r,1));
 lynra_plc_destroy(e);
 puts("MULTI FUNCTION TEST: PASS");
 return 0;
}
