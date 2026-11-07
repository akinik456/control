#include "lynra_PLC_engine.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static LynraPlcEngine *e;
static void run(LynraLogicOperator op, unsigned count, unsigned mask, int expected) {
 LynraRule r; memset(&r, 0, sizeof r);
 r.logic_operator=op; r.condition_count=(uint8_t)count;
 for (unsigned i=0;i<count;i++) {
  r.conditions[i].input_index=(uint8_t)(i+1);
  r.conditions[i].trigger=LYNRA_TRIGGER_HIGH;
 }
 r.action_count=1; r.actions[0].type=LYNRA_TIMER_ON_DELAY;
 r.actions[0].output_index=1; r.actions[0].t_ms=0;
 assert(lynra_plc_load_rules(e,&r,1));
 assert(lynra_plc_scan(e,0,mask));
 unsigned actual=(lynra_plc_get_outputs(e)&1u)!=0;
 if (actual!=(unsigned)expected) {
  fprintf(stderr,"FAIL op=%d mask=%u expected=%d actual=%u\n",op,mask,expected,actual);
  assert(0);
 }
}
int main(void) {
 e=lynra_plc_create(); assert(e);
 for(unsigned m=0;m<4;m++) {
  unsigned n=((m&1u)!=0)+((m&2u)!=0);
  run(LYNRA_LOGIC_AND,2,m,n==2);
  run(LYNRA_LOGIC_OR,2,m,n!=0);
  run(LYNRA_LOGIC_XOR,2,m,n==1);
  run(LYNRA_LOGIC_NAND,2,m,n!=2);
  run(LYNRA_LOGIC_NOR,2,m,n==0);
 }
 for(unsigned m=0;m<2;m++) run(LYNRA_LOGIC_NOT,1,m,m==0);
 puts("BASIC LOGIC TEST: PASS (AND OR XOR NAND NOR NOT)");
 lynra_plc_destroy(e); return 0;
}
