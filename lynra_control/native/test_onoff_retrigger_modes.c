#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <string.h>
static int checks=0,fail=0;
static void ck(LynraPlcEngine*e,unsigned t,unsigned in,int want,const char *label){
 if(!lynra_plc_scan(e,t,in)){printf("SCAN FAIL %s\n",label);fail++;return;}
 int got=lynra_plc_get_outputs(e)&1; checks++;
 if(got!=want){printf("FAIL %s t=%u in=%u got=%d expected=%d\n",label,t,in,got,want);fail++;}
}
static void run(int retrigger){
 LynraPlcEngine*e=lynra_plc_create(); LynraRule r={0};
 r.condition_count=1;r.conditions[0].input_index=1;r.conditions[0].trigger=LYNRA_TRIGGER_RISING;
 r.action_count=1;r.actions[0].type=LYNRA_TIMER_ON_OFF_DELAY;r.actions[0].output_index=1;
 r.actions[0].th_ms=500;r.actions[0].tl_ms=300;r.actions[0].retrigger=retrigger;r.actions[0].reset_input_index=2;
 if(!e||!lynra_plc_load_rules(e,&r,1)){puts("LOAD FAIL");fail++;return;}
 ck(e,0,0,0,"init");ck(e,100,1,0,"first trigger");ck(e,200,0,0,"release");
 ck(e,300,1,0,"second during TH");ck(e,400,0,0,"release 2");
 ck(e,599,0,0,"before original TH");
 ck(e,600,0,retrigger?0:1,"original TH boundary");
 ck(e,799,0,retrigger?0:1,"before restarted TH boundary");
 ck(e,800,0,1,"restarted TH boundary");
 ck(e,810,1,retrigger?1:0,"trigger while Q ON");
 ck(e,820,0,retrigger?1:0,"release after Q ON");
 ck(e,1110,0,retrigger?0:0,"after TA or waiting TH");
 ck(e,1310,0,retrigger?0:1,"after restarted TH");
 ck(e,1320,2,0,"reset high");ck(e,1330,2,0,"reset held");ck(e,1340,0,0,"reset released");
 ck(e,1350,1,0,"physical after reset");ck(e,1850,1,1,"physical TH done");
 lynra_plc_destroy(e);
}
int main(void){run(0);run(1);printf("RESULT: %s (%d errors / %d checks)\n",fail?"FAIL":"PASS",fail,checks);return !!fail;}
