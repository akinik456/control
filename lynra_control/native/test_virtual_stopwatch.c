#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <string.h>
static int failures, checks;
static LynraPlcEngine *e;
static void expect(uint64_t t, uint32_t inputs, int q, uint64_t elapsed, const char *label) {
    ++checks;
    if (!lynra_plc_scan(e,t,inputs)) { printf("FAIL scan %s\n",label); ++failures; return; }
    uint64_t actual=UINT64_MAX;
    int output=(lynra_plc_get_outputs(e)&1)!=0;
    if (!lynra_plc_get_stopwatch(e,0,0,&actual) || output!=q || actual!=elapsed) {
        printf("FAIL %-30s t=%llu in=%u Q=%d/%d elapsed=%llu/%llu\n",label,
          (unsigned long long)t,inputs,output,q,(unsigned long long)actual,(unsigned long long)elapsed);
        ++failures;
    } else printf("PASS %s\n",label);
}
static void setup(int virt) {
    LynraRule r; memset(&r,0,sizeof r);
    e=lynra_plc_create();
    r.condition_count=1;r.conditions[0].input_index=1;r.conditions[0].trigger=LYNRA_TRIGGER_HIGH;
    r.action_count=1;r.actions[0].type=LYNRA_TIMER_STOPWATCH;
    r.actions[0].output_index=1;r.actions[0].reset_input_index=2;
    r.actions[0].t_ms=1000;r.actions[0].virtual_start=virt;
    ++checks;if(!e||!lynra_plc_load_rules(e,&r,1)){puts("FAIL load");++failures;}
}
int main(void){
 setup(1);
 expect(0,0,0,0,"virtual RUN");expect(999,0,0,999,"virtual counting");
 expect(1000,0,1,1000,"virtual threshold");
 expect(1200,1,0,0,"physical takeover resets");
 expect(1700,1,0,500,"physical counting");
 expect(1800,0,0,600,"physical pause");
 expect(2200,0,0,600,"stays paused");
 expect(2300,1,0,600,"physical resume");
 expect(2700,1,1,1000,"physical threshold");
 expect(2800,3,0,0,"reset while EN high");
 expect(2900,1,0,0,"restart after reset");
 expect(3900,1,1,1000,"threshold after reset");
 lynra_plc_destroy(e);
 setup(0);
 expect(0,0,0,0,"normal OFF");expect(1000,0,0,0,"normal still OFF");
 expect(1100,1,0,0,"normal EN");expect(2100,1,1,1000,"normal threshold");
 lynra_plc_destroy(e);
 printf("RESULT: %s (%d failures / %d checks)\n",failures?"FAIL":"PASS",failures,checks);
 return failures?1:0;
}
