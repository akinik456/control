#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <string.h>
static int fails=0;
static void ck(int ok,const char *msg){printf("%s %s\n",ok?"PASS":"FAIL",msg);if(!ok)fails++;}
static void run(int trig,int virt,int ta){
 LynraPlcEngine *e=lynra_plc_create(); LynraRule r={0};r.condition_count=1;r.conditions[0].input_index=1;r.conditions[0].trigger=trig;r.action_count=1;r.actions[0].type=LYNRA_TIMER_ON_OFF_DELAY;r.actions[0].output_index=1;r.actions[0].virtual_start=virt;r.actions[0].th_ms=100;r.actions[0].tl_ms=ta;
 ck(lynra_plc_load_rules(e,&r,1),"load");
 lynra_plc_scan(e,0,0);ck(!(lynra_plc_get_outputs(e)&1),"initial OFF");
 lynra_plc_scan(e,100,0);ck(!!(lynra_plc_get_outputs(e)&1),"virtual ON at TH");
 if(trig==LYNRA_TRIGGER_RISING){lynra_plc_scan(e,100+ta+1,0);ck((!!(lynra_plc_get_outputs(e)&1))==(ta==0),"edge TA timeout/hold");}
 if(trig==LYNRA_TRIGGER_HIGH){lynra_plc_scan(e,150,1);ck(!(lynra_plc_get_outputs(e)&1),"physical takeover restarts TH");lynra_plc_scan(e,250,1);ck(!!(lynra_plc_get_outputs(e)&1),"physical TH ON");lynra_plc_scan(e,251,0);lynra_plc_scan(e,251+ta,0);ck(!(lynra_plc_get_outputs(e)&1),"physical low TL off");}
 lynra_plc_destroy(e);
}
int main(){run(LYNRA_TRIGGER_HIGH,1,50);run(LYNRA_TRIGGER_RISING,1,50);run(LYNRA_TRIGGER_RISING,1,0);printf("failures=%d\n",fails);return !!fails;}
