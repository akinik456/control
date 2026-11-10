#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <string.h>
static int checks, failures;
#define T(name,expr) do { checks++; if (!(expr)) { failures++; printf("FAIL: %s\n",name); } } while(0)
static LynraRule base(void) { LynraRule r={0}; r.logic_operator=LYNRA_LOGIC_AND; r.run_policy=LYNRA_RUN_ONCE; r.condition_count=1; r.conditions[0].input_index=1; r.conditions[0].trigger=LYNRA_TRIGGER_HIGH; return r; }
int main(void) {
 LynraPlcEngine *e=lynra_plc_create(); T("create",e!=NULL);
 LynraRule r[3]={0}; r[0]=base(); r[0].action_count=4;
 r[0].actions[0]=(LynraAction){.type=LYNRA_CMD_SET,.output_index=3};
 r[0].actions[1]=(LynraAction){.type=LYNRA_CMD_WAIT,.t_ms=2000};
 r[0].actions[2]=(LynraAction){.type=LYNRA_CMD_RESET,.output_index=1};
 r[0].actions[3]=(LynraAction){.type=LYNRA_CMD_SET,.output_index=2};
 T("load",lynra_plc_load_rules(e,r,1));
 T("initial",lynra_plc_scan(e,0,0) && lynra_plc_get_outputs(e)==0);
 T("set Q3",lynra_plc_scan(e,100,1) && lynra_plc_get_outputs(e)==4);
 T("wait 1999",lynra_plc_scan(e,2099,1) && lynra_plc_get_outputs(e)==4);
 T("wait 2000",lynra_plc_scan(e,2100,1) && lynra_plc_get_outputs(e)==6);
 T("latch persists",lynra_plc_scan(e,3000,0) && lynra_plc_get_outputs(e)==6);
 r[1]=base();r[1].condition_count=1;r[1].conditions[0].input_index=2;r[1].action_count=1;
 r[1].actions[0]=(LynraAction){.type=LYNRA_CMD_RESET,.output_index=3};
 T("load 2",lynra_plc_load_rules(e,r,2));
 T("first rule",lynra_plc_scan(e,0,1) && lynra_plc_get_outputs(e)==4);
 T("later rule priority",lynra_plc_scan(e,100,3) && lynra_plc_get_outputs(e)==0);
 T("later latch",lynra_plc_scan(e,200,0) && lynra_plc_get_outputs(e)==0);
 r[0]=base();r[0].action_count=2;
 r[0].actions[0]=(LynraAction){.type=LYNRA_CMD_SET,.output_index=1};
 r[0].actions[1]=(LynraAction){.type=LYNRA_CMD_RESET,.output_index=1};
 T("duplicate reject",!lynra_plc_load_rules(e,r,1));
 r[0].action_count=1;r[0].actions[0]=(LynraAction){.type=LYNRA_CMD_FOLLOW,.output_index=2,.follow_input_index=2};
 T("follow load",lynra_plc_load_rules(e,r,1));
 T("follow low",lynra_plc_scan(e,0,1) && lynra_plc_get_outputs(e)==0);
 T("follow high",lynra_plc_scan(e,100,3) && lynra_plc_get_outputs(e)==2);
 T("follow low again",lynra_plc_scan(e,200,1) && lynra_plc_get_outputs(e)==0);
 lynra_plc_destroy(e);
 printf("RESULT: %s (%d/%d)\n", failures?"FAIL":"PASS",checks-failures,checks);
 return failures?1:0;
}
