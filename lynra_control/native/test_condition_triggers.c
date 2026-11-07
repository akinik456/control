#include "lynra_PLC_engine.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static void check(LynraPlcEngine *e, uint64_t t, uint32_t inputs, unsigned expected) {
 assert(lynra_plc_scan(e,t,inputs));
 unsigned got=lynra_plc_get_outputs(e);
 if(got!=expected){fprintf(stderr,"FAIL t=%llu inputs=%u expected=%u got=%u\n",(unsigned long long)t,inputs,expected,got);assert(0);}
}
static void run(LynraLogicOperator op, LynraConditionTrigger a, LynraConditionTrigger b,
                const uint32_t *inputs, const unsigned *expected, unsigned n){
 LynraPlcEngine *e=lynra_plc_create(); assert(e);
 LynraRule r; memset(&r,0,sizeof r);
 r.logic_operator=op; r.condition_count=2;
 r.conditions[0].input_index=1; r.conditions[0].trigger=a;
 r.conditions[1].input_index=2; r.conditions[1].trigger=b;
 r.action_count=1; r.actions[0].type=LYNRA_TIMER_ON_DELAY;
 r.actions[0].output_index=1; r.actions[0].t_ms=0;
 assert(lynra_plc_load_rules(e,&r,1));
 for(unsigned i=0;i<n;i++)check(e,i,inputs[i],expected[i]);
 lynra_plc_destroy(e);
}
int main(void){
 {const uint32_t in[]={0,1,1,0,2,2,3,3,1,0};
  const unsigned rising[]={0,1,0,0,0,0,0,0,0,0};
  const unsigned falling[]={0,0,0,1,0,0,0,0,0,1};
  const unsigned low[]={1,0,0,1,1,1,0,0,0,1};
  const unsigned high[]={0,1,1,0,0,0,1,1,1,0};
  // Second condition is LOW on I2 at the start; AND with it filters edges.
  run(LYNRA_LOGIC_AND,LYNRA_TRIGGER_RISING,LYNRA_TRIGGER_LOW,in,rising,10);
  run(LYNRA_LOGIC_AND,LYNRA_TRIGGER_FALLING,LYNRA_TRIGGER_LOW,in,falling,10);
  // OR with I2 HIGH includes all scans where I2 is set.
  const unsigned or_rise[]={0,1,0,0,1,1,1,1,0,0};
  run(LYNRA_LOGIC_OR,LYNRA_TRIGGER_RISING,LYNRA_TRIGGER_HIGH,in,or_rise,10);
  // XOR with I2 LOW: rising edge on I1 flips parity for one scan.
  const unsigned xor_rise[]={1,0,1,1,0,0,1,0,1,1};
  run(LYNRA_LOGIC_XOR,LYNRA_TRIGGER_RISING,LYNRA_TRIGGER_LOW,in,xor_rise,10);
  (void)low; (void)high;
 }
 puts("CONDITION TRIGGERS TEST: PASS (HIGH LOW RISING FALLING)");
 return 0;
}
