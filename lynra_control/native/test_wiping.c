#include "lynra_PLC_engine.h"
#include <assert.h>
#include <stdio.h>

static void scan_expect(LynraPlcEngine *e, uint64_t ms, uint32_t in, bool on) {
    assert(lynra_plc_scan(e, ms, in));
    assert(((lynra_plc_get_outputs(e) & 1u) != 0) == on);
}
int main(void) {
    LynraPlcEngine *e = lynra_plc_create();
    assert(e);
    LynraRule r = {0};
    r.condition_count = 1;
    r.conditions[0].input_index = 1;
    r.conditions[0].trigger = LYNRA_TRIGGER_HIGH;
    r.action_count = 1;
    r.actions[0].type = LYNRA_TIMER_WIPING_RELAY;
    r.actions[0].output_index = 1;
    r.actions[0].t_ms = 2500;
    assert(lynra_plc_load_rules(e, &r, 1));
    scan_expect(e, 0, 0, false);
    scan_expect(e, 100, 1, true);
    scan_expect(e, 2599, 1, true);
    scan_expect(e, 2600, 1, false);
    scan_expect(e, 4000, 1, false); // HIGH must not retrigger
    scan_expect(e, 4100, 0, false);
    scan_expect(e, 4200, 1, true); // new rising edge
    scan_expect(e, 4500, 0, false); // early release
    scan_expect(e, 4600, 1, true); // rearm after release
    scan_expect(e, 7100, 1, false);
    lynra_plc_reset(e);
    scan_expect(e, 8000, 1, true); // reset re-arms timer
    lynra_plc_destroy(e);
    e = lynra_plc_create(); assert(e);
    r.actions[0].t_ms = 0;
    assert(lynra_plc_load_rules(e, &r, 1));
    scan_expect(e, 0, 1, false); // zero-duration pulse
    scan_expect(e, 1, 1, false);
    lynra_plc_destroy(e);
    puts("WIPING RELAY TEST: PASS");
    return 0;
}
