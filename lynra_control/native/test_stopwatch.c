#include "lynra_PLC_engine.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static void scan(LynraPlcEngine *e, uint64_t t, uint32_t in, int out) {
 assert(lynra_plc_scan(e,t,in));
 assert((lynra_plc_get_outputs(e)&1u)==(unsigned)out);
}
int main(void){
 LynraPlcEngine *e=lynra_plc_create(); assert(e);
 LynraRule r; memset(&r,0,sizeof r);
 r.logic_operator=LYNRA_LOGIC_AND; r.run_policy=LYNRA_RUN_REPEAT;
 r.condition_count=2; r.conditions[0].input_index=1; r.conditions[0].trigger=LYNRA_TRIGGER_HIGH;
 r.conditions[1].input_index=2; r.conditions[1].trigger=LYNRA_TRIGGER_HIGH;
 r.action_count=1; r.actions[0].type=LYNRA_ACTION_STOPWATCH;
 r.actions[0].output_index=1; r.actions[0].duration_ms=30000;
 assert(lynra_plc_load_rules(e,&r,1));
 scan(e,0,0,0); scan(e,1000,1,0); scan(e,11000,1,0); // 10s
 scan(e,16000,0,0); scan(e,21000,0,0); // paused
 scan(e,22000,1,0); scan(e,41999,1,0); scan(e,42000,1,1); // 30s
 scan(e,43000,0,1); scan(e,50000,0,1); // latch
 scan(e,51000,2,0); scan(e,52000,3,0); // reset wins even with EN high
 scan(e,53000,1,0); scan(e,82999,1,0); scan(e,83000,1,1);
 scan(e,84000,2,0); scan(e,85000,0,0);
 lynra_plc_destroy(e);
 puts("STOPWATCH PASS"); return 0;
}
