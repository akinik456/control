#include "lynra_PLC_engine.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static void tick(LynraPlcEngine *e, uint64_t t, unsigned in, unsigned q) {
 assert(lynra_plc_scan(e,t,in));
 unsigned got=lynra_plc_get_outputs(e)&1u;
 if(got!=q) fprintf(stderr,"t=%llu in=%u got=%u expected=%u\n",(unsigned long long)t,in,got,q);
 assert(got==q);
}
static void run(LynraRunPolicy policy) {
 LynraPlcEngine *e=lynra_plc_create(); assert(e);
 LynraRule r; memset(&r,0,sizeof r);
 r.logic_operator=LYNRA_LOGIC_AND;
 r.run_policy=policy;
 r.condition_count=1; r.conditions[0].input_index=1;
 r.conditions[0].trigger=LYNRA_TRIGGER_RISING;
 r.action_count=1; r.actions[0].type=LYNRA_TIMER_EDGE_WIPING_RELAY;
 r.actions[0].output_index=1; r.actions[0].th_ms=200;
 r.actions[0].tl_ms=100; r.actions[0].n=2;
 assert(lynra_plc_load_rules(e,&r,1));
 tick(e,0,0,0); tick(e,10,1,1); tick(e,50,0,1);
 tick(e,150,1,1); /* new edge while running */
 tick(e,210,0,policy==LYNRA_RUN_ONCE?0:1);
 tick(e,260,0,policy==LYNRA_RUN_ONCE?0:1);
 tick(e,320,0,1);
 tick(e,400,0,policy==LYNRA_RUN_ONCE?1:0);
 tick(e,520,0,policy==LYNRA_RUN_ONCE?0:1);
 tick(e,700,0,0);
 tick(e,750,1,1); /* new edge after completion */
 tick(e,950,0,0);
 lynra_plc_destroy(e);
}
int main(void) {run(LYNRA_RUN_ONCE);run(LYNRA_RUN_REPEAT);puts("RUN POLICY EDGE TEST: PASS");return 0;}
