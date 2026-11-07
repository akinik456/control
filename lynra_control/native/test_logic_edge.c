#include "lynra_PLC_engine.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static void scan(LynraPlcEngine *e, uint64_t t, uint32_t in, int out) {
 assert(lynra_plc_scan(e,t,in));
 if ((int)lynra_plc_get_outputs(e)!=out) {
  fprintf(stderr,"FAIL t=%llu in=%u expected=%d actual=%u\n",(unsigned long long)t,in,out,lynra_plc_get_outputs(e));
  assert(0);
 }
}
int main(void) {
 LynraPlcEngine *e=lynra_plc_create(); assert(e);
 LynraRule r; memset(&r,0,sizeof r);
 r.condition_count=2; r.conditions[0].input_index=1;
 r.conditions[1].input_index=2;
 r.conditions[0].trigger=LYNRA_TRIGGER_HIGH;
 r.conditions[1].trigger=LYNRA_TRIGGER_HIGH;
 r.action_count=1; r.actions[0].type=LYNRA_TIMER_ON_DELAY;
 r.actions[0].output_index=1; r.actions[0].t_ms=0;
 r.logic_operator=LYNRA_LOGIC_AND_EDGE;
 assert(lynra_plc_load_rules(e,&r,1));
 scan(e,0,0,0); scan(e,1,1,0); scan(e,2,3,1); scan(e,3,3,0);
 scan(e,4,3,0); scan(e,5,1,0); scan(e,6,3,1); scan(e,7,3,0);
 r.logic_operator=LYNRA_LOGIC_NAND_EDGE;
 assert(lynra_plc_load_rules(e,&r,1));
 scan(e,0,3,0); scan(e,1,3,0); scan(e,2,1,1); scan(e,3,1,0);
 scan(e,4,0,0); scan(e,5,3,0); scan(e,6,2,1); scan(e,7,2,0);
 lynra_plc_destroy(e);
 puts("EDGE LOGIC TEST: PASS (AND_EDGE NAND_EDGE)");
 return 0;
}
