#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <string.h>
static int failures, checks;
#define CHECK(label, expr) do { ++checks; if (!(expr)) { ++failures; printf("FAIL: %s\n", label); } } while (0)
static int find(const LynraParameter *p, size_t n, LynraFieldId id, LynraFieldValue *v) {
    for (size_t i=0; i<n; ++i) if (p[i].id == id) { *v=p[i].value; return 1; }
    return 0;
}
int main(void) {
    LynraPlcEngine *e=lynra_plc_create();
    CHECK("create", e != NULL);
    LynraRule r[14]; memset(r,0,sizeof(r));
    for (int i=0;i<14;i++) {
        r[i].id=(uint32_t)(i+1); r[i].logic_operator=LYNRA_LOGIC_AND;
        r[i].run_policy=LYNRA_RUN_ONCE; r[i].condition_count=1;
        r[i].conditions[0].input_index=1; r[i].conditions[0].trigger=LYNRA_TRIGGER_HIGH;
        r[i].action_count=1; r[i].actions[0].type=(LynraActionType)i;
        r[i].actions[0].output_index=(uint8_t)(i+1);
        r[i].actions[0].t_ms=2000; r[i].actions[0].th_ms=1000;
        r[i].actions[0].tl_ms=1000; r[i].actions[0].n=2;
        r[i].actions[0].counter_input_index=2;
        r[i].actions[0].counter_on=10; r[i].actions[0].counter_off=5;
        r[i].actions[0].hours_enable_input_index=3;
        r[i].actions[0].hours_target_ms=10000;
        r[i].actions[0].threshold_input_index=4;
        r[i].actions[0].threshold_gate_ms=1000;
        r[i].actions[0].threshold_on=5; r[i].actions[0].threshold_off=2;
    }
    CHECK("load 14", lynra_plc_load_rules(e,r,14));
    for (int i=0;i<14;i++) {
        LynraParameters p; LynraValues v; LynraActionType t;
        CHECK("discover", lynra_plc_get_action_info(e,i,0,&t,NULL) && t==(LynraActionType)i);
        CHECK("params", lynra_plc_get_parameters(e,i,0,&p) && p.count>0);
        CHECK("values", lynra_plc_get_values(e,i,0,&v) && v.count>0);
        CHECK("immutable input", !lynra_plc_set_parameter(e,i,0,LYNRA_FIELD_INPUT,2));
        CHECK("immutable output", !lynra_plc_set_parameter(e,i,0,LYNRA_FIELD_OUTPUT,1));
        CHECK("invalid action", !lynra_plc_get_values(e,i,1,&v));
        for (size_t j=0;j<p.count;j++) {
            LynraFieldValue before=p.items[j].value, after=-999;
            /* Writing an unchanged setting must succeed for editable fields, fail for pin wiring. */
            int ok=lynra_plc_set_parameter(e,i,0,p.items[j].id,before);
            switch(p.items[j].id) {
                case LYNRA_FIELD_RESET_INPUT_INDEX: case LYNRA_FIELD_COUNTER_INPUT_INDEX:
                case LYNRA_FIELD_DIRECTION_INPUT_INDEX: case LYNRA_FIELD_HOURS_ENABLE_INPUT_INDEX:
                case LYNRA_FIELD_HOURS_RESET_ALL_INPUT_INDEX: case LYNRA_FIELD_THRESHOLD_INPUT_INDEX:
                    CHECK("wiring read-only", !ok); break;
                default: CHECK("writable setting",ok); break;
            }
            LynraParameters updated;
            CHECK("readback",lynra_plc_get_parameters(e,i,0,&updated) &&
                  find(updated.items,updated.count,p.items[j].id,&after) && after==before);
        }
    }
    CHECK("invalid stairway warning", !lynra_plc_set_parameter(e,8,0,LYNRA_FIELD_WARNING_BEFORE_MS,3000));
    CHECK("invalid async TH", !lynra_plc_set_parameter(e,6,0,LYNRA_FIELD_TH_MS,0));
    CHECK("invalid threshold gate", !lynra_plc_set_parameter(e,13,0,LYNRA_FIELD_THRESHOLD_GATE_MS,999));
    CHECK("invalid edge pulse", !lynra_plc_set_parameter(e,5,0,LYNRA_FIELD_PULSE_COUNT,0));
    CHECK("invalid stopwatch base", !lynra_plc_set_parameter(e,10,0,LYNRA_FIELD_STOPWATCH_TIME_BASE,3));
    CHECK("valid counter ON", lynra_plc_set_parameter(e,11,0,LYNRA_FIELD_COUNTER_ON,20));
    CHECK("valid hours target", lynra_plc_set_parameter(e,12,0,LYNRA_FIELD_HOURS_TARGET_MS,20000));
    CHECK("valid threshold ON", lynra_plc_set_parameter(e,13,0,LYNRA_FIELD_THRESHOLD_ON,7));
    CHECK("scan 0", lynra_plc_scan(e,0,0));
    CHECK("scan 1000", lynra_plc_scan(e,1000,0x0f));
    CHECK("scan 2000", lynra_plc_scan(e,2000,0x0f));
    CHECK("scan 3000", lynra_plc_scan(e,3000,0));
    for (int i=0;i<14;i++) { LynraValues v; CHECK("live after scan",lynra_plc_get_values(e,i,0,&v) && v.count>0); }
    lynra_plc_destroy(e);
    printf("RESULT: %s (%d/%d checks, %d failures)\n", failures?"FAIL":"PASS",checks-failures,checks,failures);
    return failures!=0;
}
