#include "lynra_PLC_engine.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
int main(void) {
 LynraPlcEngine *e = lynra_plc_create(); assert(e);
 assert(lynra_plc_create() == NULL);
 assert(!lynra_plc_scan(NULL,0,0));
 assert(!lynra_plc_load_rules(NULL,NULL,0));
 assert(!lynra_plc_load_rules(e,NULL,1));
 assert(!lynra_plc_load_rules(e,NULL,LYNRA_PLC_MAX_RULES+1));
 assert(lynra_plc_get_outputs(NULL)==0);
 LynraExecutionState state;
 uint64_t value;
 assert(!lynra_plc_get_action_state(e,0,0,&state));
 assert(!lynra_plc_get_rule_state(e,0,&state));
 assert(!lynra_plc_get_stopwatch(e,0,0,&value));
 LynraRule r; memset(&r,0,sizeof r);
 r.condition_count=1; r.conditions[0].input_index=1;
 r.action_count=1; r.actions[0].type=LYNRA_TIMER_ON_DELAY;
 r.actions[0].output_index=1; r.actions[0].t_ms=10;
 assert(lynra_plc_load_rules(e,&r,1));
 assert(!lynra_plc_get_action_state(e,0,0,NULL));
 assert(!lynra_plc_get_rule_state(e,0,NULL));
 assert(!lynra_plc_get_stopwatch(e,0,0,&value));
 assert(lynra_plc_scan(e,0,0));
 assert(lynra_plc_scan(e,1,1));
 assert(lynra_plc_scan(e,11,1));
 assert(lynra_plc_get_outputs(e)==1);
 assert(!lynra_plc_scan(e,10,1));
 assert(lynra_plc_get_outputs(e)==1);
 lynra_plc_reset(e); assert(lynra_plc_get_outputs(e)==0);
 lynra_plc_destroy(e); assert(!lynra_plc_scan(e,0,0));
 assert(lynra_plc_create()==e);
 lynra_plc_destroy(e);
 puts("API LIFECYCLE TEST: PASS");
 return 0;
}
