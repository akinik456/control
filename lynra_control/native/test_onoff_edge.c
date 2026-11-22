#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <string.h>
static int errors=0, checks=0;
static void ck(LynraPlcEngine *e,unsigned long long t,int in,int expected){
  lynra_plc_scan(e,t,in); int got=lynra_plc_get_outputs(e)&1;
  ++checks;if(got!=expected){++errors;printf("FAIL t=%llu in=%d got=%d expected=%d\n",t,in,got,expected);}
}
static void run(int falling,int ta){
 LynraPlcEngine *e=lynra_plc_create(); LynraRule r={0};
 r.condition_count=1;r.conditions[0].input_index=1;
 r.conditions[0].trigger=falling?LYNRA_TRIGGER_FALLING:LYNRA_TRIGGER_RISING;
 r.action_count=1;r.actions[0].type=LYNRA_TIMER_ON_OFF_DELAY;
 r.actions[0].output_index=1;r.actions[0].th_ms=500;r.actions[0].tl_ms=ta;
 if(!lynra_plc_load_rules(e,&r,1)){puts("LOAD FAIL");errors++;return;}
 ck(e,0,falling?1:0,0);ck(e,100,falling?0:1,0);
 ck(e,300,falling?1:0,0);ck(e,599,falling?1:0,0);
 ck(e,600,falling?1:0,1);
 ck(e,700,falling?1:0,1);
 ck(e,899,falling?1:0,1);
 ck(e,900,falling?1:0,ta==0?1:0);
 ck(e,1500,falling?1:0,ta==0?1:0);
 lynra_plc_destroy(e);
}
int main(void){run(0,300);run(1,300);run(0,0);run(1,0);printf("RESULT: %s (%d/%d)\n",errors?"FAIL":"PASS",errors,checks);return !!errors;}
