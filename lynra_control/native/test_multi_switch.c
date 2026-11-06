#include "lynra_PLC_engine.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static void tick(LynraPlcEngine *e,uint64_t t,int input,int out){assert(lynra_plc_scan(e,t,input));int got=(lynra_plc_get_outputs(e)&1)!=0;if(got!=out){printf("FAIL t=%llu in=%d expected=%d got=%d\n",(unsigned long long)t,input,out,got);assert(got==out);}}
int main(void){
 LynraPlcEngine *e=lynra_plc_create();assert(e);
 LynraRule r={0};r.condition_count=1;r.conditions[0].input_index=1;r.conditions[0].trigger=LYNRA_TRIGGER_HIGH;r.action_count=1;r.actions[0].type=LYNRA_ACTION_MULTI_SWITCH;r.actions[0].output_index=1;r.actions[0].duration_ms=6000;r.actions[0].multi_long_press_ms=2000;r.actions[0].stair_warning_before_ms=1000;r.actions[0].stair_warning_off_ms=500;
 assert(lynra_plc_load_rules(e,&r,1));
 tick(e,0,0,0);tick(e,100,1,1);tick(e,500,0,1);tick(e,5499,0,1);tick(e,5500,0,0);tick(e,6000,0,1);tick(e,6500,0,0);
 // long press latches; release does not start countdown
 tick(e,7000,1,1);tick(e,9000,1,1);tick(e,9100,0,1);tick(e,30000,0,1);tick(e,30100,1,0);tick(e,30200,0,0);
 // second press cancels an active short timer
 tick(e,31000,1,1);tick(e,31100,0,1);tick(e,31200,1,0);tick(e,31300,0,0);tick(e,50000,0,0);
 // short release at/after threshold must be recognized even if no scan at threshold
 tick(e,51000,1,1);tick(e,54000,0,1);tick(e,90000,0,1);tick(e,90100,1,0);tick(e,90200,0,0);
 lynra_plc_destroy(e);puts("MULTI SWITCH PASS");return 0;
}
