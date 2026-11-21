#include "lynra_PLC_engine.h"
#include <stdio.h>
static int total, pass;
#define CHECK(x) do { ++total; if (x) ++pass; else printf("FAIL %d: %s\n",__LINE__,#x); } while(0)
static LynraRule rule(int n,int tr,int tl) {
 LynraRule r={0}; r.condition_count=1; r.conditions[0].input_index=1; r.conditions[0].trigger=LYNRA_TRIGGER_HIGH;
 r.action_count=1; r.actions[0].type=LYNRA_TIMER_EDGE_WIPING_RELAY; r.actions[0].output_index=1;
 r.actions[0].th_ms=10; r.actions[0].tl_ms=20; r.actions[0].n=n;
 r.actions[0].th_random=tr; r.actions[0].tl_random=tl; r.actions[0].reset_input_index=2; return r;
}
static int scan(LynraPlcEngine* e,int t,int mask) { if(!lynra_plc_scan(e,t,(uint32_t)mask)) return -1; return !!(lynra_plc_get_outputs(e)&1); }
int main(void) {
 LynraPlcEngine* e=lynra_plc_create(); CHECK(e!=NULL); if(!e)return 1;
 for(int tr=0;tr<2;tr++) for(int tl=0;tl<2;tl++) {
  LynraRule r=rule(2,tr,tl); CHECK(lynra_plc_load_rules(e,&r,1));
  CHECK(scan(e,0,0)==0); CHECK(scan(e,1,1)>=0);
  int last=scan(e,1,1), rises=last==1, falls=0;
  for(int t=2;t<=150;t++) {int v=scan(e,t,0);CHECK(v>=0);if(v && !last)rises++;if(!v && last)falls++;last=v;}
  CHECK(tr || tl ? rises<=2 : rises==2); CHECK(tr || tl ? falls<=2 : falls==2); CHECK(last==0);
 }
 { LynraRule r=rule(0,0,0);CHECK(lynra_plc_load_rules(e,&r,1)); CHECK(scan(e,0,0)==0);CHECK(scan(e,1,1)==0);
   CHECK(scan(e,21,0)==1); CHECK(scan(e,31,0)==0); CHECK(scan(e,51,0)==1);
   CHECK(scan(e,301,0)>=0); CHECK(scan(e,302,2)==0); CHECK(scan(e,303,0)==0); }
 { LynraRule r=rule(1,0,0);CHECK(lynra_plc_load_rules(e,&r,1));CHECK(scan(e,0,0)==0);CHECK(scan(e,1,1)==0);CHECK(scan(e,21,0)==1);CHECK(scan(e,31,0)==0);CHECK(scan(e,100,0)==0); }
 { LynraRule r=rule(2,0,0);r.actions[0].retrigger=1;CHECK(lynra_plc_load_rules(e,&r,1));CHECK(scan(e,0,0)==0);CHECK(scan(e,1,1)==0);CHECK(scan(e,21,0)==1);CHECK(scan(e,22,0)==1);CHECK(scan(e,23,1)==0);CHECK(scan(e,42,0)==0);CHECK(scan(e,43,0)==1); }
 printf("RESULT: %s (%d/%d)\n",total==pass?"PASS":"FAIL",pass,total);lynra_plc_destroy(e);return total==pass?0:1;
}
