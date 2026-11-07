#include "lynra_PLC_engine.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static void step(LynraPlcEngine *e, uint64_t t, uint32_t in, uint64_t expected) {
 uint64_t value = UINT64_MAX;
 assert(lynra_plc_scan(e,t,in));
 assert(lynra_plc_get_stopwatch(e,0,0,&value));
 if (value != expected) {
  fprintf(stderr,"FAIL t=%llu expected=%llu actual=%llu\n",
   (unsigned long long)t,(unsigned long long)expected,(unsigned long long)value);
  assert(0);
 }
 assert(lynra_plc_get_outputs(e)==0);
}
int main(void) {
 LynraPlcEngine *e=lynra_plc_create(); assert(e);
 LynraRule r; memset(&r,0,sizeof r);
 r.logic_operator=LYNRA_LOGIC_AND;
 r.condition_count=1; r.conditions[0].input_index=1;
 r.conditions[0].trigger=LYNRA_TRIGGER_HIGH;
 r.action_count=1; r.actions[0].type=LYNRA_TIMER_STOPWATCH;
 r.actions[0].output_index=1; r.actions[0].reset_input_index=2;
 assert(lynra_plc_load_rules(e,&r,1));
 step(e,0,0,0); step(e,100,1,0); step(e,350,1,250);
 step(e,400,0,300); step(e,1000,0,300);
 step(e,1200,1,300); step(e,1700,1,800);
 step(e,1800,3,0); step(e,1900,1,0);
 step(e,2200,1,300); step(e,2300,0,400);
 r.actions[0].stopwatch_time_base=1;
 assert(lynra_plc_load_rules(e,&r,1));
 step(e,0,0,0); step(e,100,1,0); step(e,2099,1,1);
 step(e,2100,1,2);
 r.actions[0].stopwatch_time_base=2;
 assert(lynra_plc_load_rules(e,&r,1));
 step(e,0,0,0); step(e,100,1,0); step(e,60100,1,1);
 r.actions[0].stopwatch_time_base=3;
 assert(!lynra_plc_load_rules(e,&r,1));
 uint64_t v=0;
 assert(!lynra_plc_get_stopwatch(e,0,1,&v));
 assert(!lynra_plc_get_stopwatch(e,0,0,NULL));
 lynra_plc_reset(e);
 v=1; assert(lynra_plc_get_stopwatch(e,0,0,&v) && v==0);
 lynra_plc_destroy(e);
 puts("STOPWATCH TEST: PASS");
 return 0;
}
