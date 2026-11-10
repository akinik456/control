#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <string.h>
static int ok=0,total=0;
#define CHECK(x) do {++total;if(x)++ok;else printf("FAIL line %d: %s\n",__LINE__,#x);}while(0)
static LynraRule base(void){
 LynraRule r={0}; r.condition_count=4; r.action_count=1;
 for(int i=0;i<4;i++){r.conditions[i].input_index=i+1;r.conditions[i].trigger=LYNRA_TRIGGER_HIGH;}
 r.actions[0].type=LYNRA_CMD_SET;r.actions[0].output_index=1;return r;
}
static void expr(LynraRule *r,const LynraExprToken *x,int n){r->expression_count=n;memcpy(r->expression,x,n*sizeof(*x));}
#define C(i) {LYNRA_EXPR_CONDITION,i}
#define OP(x) {LYNRA_EXPR_##x,0}
int main(void){
 LynraPlcEngine *e=lynra_plc_create();CHECK(e!=NULL);
 /* (I1 AND I2) OR (I3 AND NOT I4) */
 LynraRule r=base(); LynraExprToken x[]={C(0),C(1),OP(AND),C(2),C(3),OP(NOT),OP(AND),OP(OR)};
 expr(&r,x,8);CHECK(lynra_plc_load_rules(e,&r,1));
 for(unsigned in=0;in<16;in++){
  lynra_plc_reset(e);CHECK(lynra_plc_scan(e,in,in));
  int expected=((in&3)==3)||((in&4)&&!(in&8));
  CHECK(!!(lynra_plc_get_outputs(e)&1)==!!expected);
 }
 /* XOR */
 LynraExprToken xor[]={C(0),C(1),OP(XOR)};expr(&r,xor,3);CHECK(lynra_plc_load_rules(e,&r,1));
 for(unsigned in=0;in<4;in++){lynra_plc_reset(e);CHECK(lynra_plc_scan(e,in,in));CHECK(!!(lynra_plc_get_outputs(e)&1)==!!((!!(in&1))!=(!!(in&2))));}
 /* Nested NOT: NOT (I1 OR (I2 AND I3)) */
 LynraExprToken nested[]={C(0),C(1),C(2),OP(AND),OP(OR),OP(NOT)};
 expr(&r,nested,6);CHECK(lynra_plc_load_rules(e,&r,1));
 for(unsigned in=0;in<8;in++){lynra_plc_reset(e);CHECK(lynra_plc_scan(e,in,in));CHECK(!!(lynra_plc_get_outputs(e)&1)==!((!!(in&1))||((in&2)&&(in&4))));}
 /* malformed RPN rejected, previous valid program retained */
 LynraExprToken bad1[]={OP(AND),C(0)};expr(&r,bad1,2);CHECK(!lynra_plc_load_rules(e,&r,1));
 LynraExprToken bad2[]={C(0),C(1)};expr(&r,bad2,2);CHECK(!lynra_plc_load_rules(e,&r,1));
 LynraExprToken bad3[]={C(7)};expr(&r,bad3,1);CHECK(!lynra_plc_load_rules(e,&r,1));
 LynraExprToken bad4[]={ { (LynraExprOp)99,0 } };expr(&r,bad4,1);CHECK(!lynra_plc_load_rules(e,&r,1));
 /* Legacy mode */
 r=base();r.condition_count=2;r.logic_operator=LYNRA_LOGIC_AND;
 CHECK(lynra_plc_load_rules(e,&r,1));
 for(unsigned in=0;in<4;in++){lynra_plc_reset(e);CHECK(lynra_plc_scan(e,in,in));CHECK(!!(lynra_plc_get_outputs(e)&1)==(in==3));}
 /* edge operand */
 r=base();r.condition_count=1;r.conditions[0].trigger=LYNRA_TRIGGER_RISING;
 LynraExprToken edge[]={C(0)};expr(&r,edge,1);CHECK(lynra_plc_load_rules(e,&r,1));
 CHECK(lynra_plc_scan(e,0,0));CHECK(!(lynra_plc_get_outputs(e)&1));
 CHECK(lynra_plc_scan(e,1,1));CHECK(!!(lynra_plc_get_outputs(e)&1));
 printf("RESULT: %s (%d/%d)\n",ok==total?"PASS":"FAIL",ok,total);
 lynra_plc_destroy(e);return ok==total?0:1;
}
