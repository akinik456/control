#include "lynra_PLC_engine.h"
#include <stdio.h>
#include <string.h>

static int failures = 0, checks = 0;
static LynraPlcEngine *engine;
static const char *current;

static void begin(const char *name, LynraActionType type, int virtual_start) {
    LynraRule rule;
    memset(&rule, 0, sizeof rule);
    current = name;
    engine = lynra_plc_create();
    if (!engine) { fprintf(stderr, "FAIL create: %s\n", name); ++failures; return; }
    rule.condition_count = 1;
    rule.conditions[0].input_index = 1;
    rule.conditions[0].trigger = LYNRA_TRIGGER_HIGH;
    rule.action_count = 1;
    rule.actions[0].type = type;
    rule.actions[0].output_index = 1;
    rule.actions[0].virtual_start = (uint8_t)virtual_start;
    rule.actions[0].t_ms = 1000;
    rule.actions[0].th_ms = 1000;
    rule.actions[0].tl_ms = 1000;
    rule.actions[0].n = 1;
    if (!lynra_plc_load_rules(engine, &rule, 1)) {
        fprintf(stderr, "FAIL load: %s\n", name); ++failures;
        lynra_plc_destroy(engine); engine = NULL;
    }
}
static void end(void) { if (engine) lynra_plc_destroy(engine); engine = NULL; }
static void check(uint64_t ms, int i1, int expected, const char *label) {
    if (!engine) return;
    ++checks;
    if (!lynra_plc_scan(engine, ms, i1 ? 1u : 0u)) {
        printf("FAIL %-22s t=%5llu scan | %s\n", current, (unsigned long long)ms, label);
        ++failures; return;
    }
    int actual = (lynra_plc_get_outputs(engine) & 1u) != 0;
    printf("%s %-22s t=%5llu I1=%d Q1=%d expected=%d | %s\n",
           actual == expected ? "PASS" : "FAIL", current,
           (unsigned long long)ms, i1, actual, expected, label);
    if (actual != expected) ++failures;
}

int main(void) {
    begin("TON virtual", LYNRA_TIMER_ON_DELAY, 1);
    check(0,0,0,"RUN"); check(999,0,0,"before T"); check(1000,0,1,"virtual T");
    check(1200,1,0,"physical takeover"); check(2200,1,1,"physical T");
    check(2300,0,0,"physical OFF"); end();

    begin("OFF DELAY virtual", LYNRA_TIMER_OFF_DELAY, 1);
    check(0,0,1,"RUN starts ON countdown"); check(999,0,1,"before T");
    check(1000,0,0,"virtual timeout"); check(1200,1,1,"physical ON");
    check(1300,0,1,"physical release"); check(2299,0,1,"before release T");
    check(2300,0,0,"release timeout"); end();

    begin("RETENTIVE virtual", LYNRA_TIMER_RETENTIVE_ON_DELAY, 1);
    check(0,0,0,"RUN"); check(999,0,0,"before T"); check(1000,0,1,"virtual T");
    check(1200,1,0,"physical takeover resets"); check(2200,1,1,"physical T"); end();

    begin("WIPING virtual", LYNRA_TIMER_WIPING_RELAY, 1);
    check(0,0,1,"virtual pulse ON"); check(999,0,1,"pulse running");
    check(1000,0,0,"pulse expired"); check(1200,1,1,"physical pulse restart");
    check(2200,1,0,"physical pulse expired"); check(2300,0,0,"physical release");
    check(2400,1,1,"second physical pulse"); end();

    begin("EDGE WIPING virtual", LYNRA_TIMER_EDGE_WIPING_RELAY, 1);
    check(0,0,0,"virtual TL"); check(999,0,0,"before TL");
    check(1000,0,1,"virtual TH"); check(2000,0,0,"cycle complete");
    check(2200,1,0,"physical takeover TL"); check(3200,1,1,"physical TH");
    check(4200,1,0,"physical cycle complete"); end();

    begin("ASYNC PULSE virtual", LYNRA_TIMER_ASYNC_PULSE, 1);
    check(0,0,1,"virtual TH ON"); check(1000,0,0,"virtual TL OFF");
    check(2000,0,1,"virtual TH again"); check(2500,1,1,"physical takeover TH");
    check(3500,1,0,"physical TL"); check(3600,0,0,"physical OFF");
    check(3700,1,1,"physical restart TH"); end();

    /* Random delay upper bounds = 1000 ms, so use a deterministic long wait.
       Its exact draw is deliberately NOT asserted. */
    begin("RANDOM virtual", LYNRA_TIMER_RANDOM_GENERATOR, 1);
    check(0,0,0,"RUN random pending"); check(1000,0,1,"virtual ON by upper bound");
    check(1200,1,0,"physical takeover resets"); check(2200,1,1,"physical ON by upper bound");
    check(2300,0,1,"physical release pending"); check(3300,0,0,"physical OFF by upper bound"); end();

    begin("TON normal", LYNRA_TIMER_ON_DELAY, 0);
    check(0,0,0,"no virtual start"); check(1000,0,0,"still OFF");
    check(1100,1,0,"physical ON"); check(2100,1,1,"physical timeout"); end();

    begin("OFF DELAY normal", LYNRA_TIMER_OFF_DELAY, 0);
    check(0,0,0,"no virtual start"); check(1000,0,0,"still OFF");
    check(1100,1,1,"physical ON"); check(1200,0,1,"physical release");
    check(2200,0,0,"physical timeout"); end();

    printf("\nRESULT: %s (%d failures / %d checks)\n", failures ? "FAIL" : "PASS", failures, checks);
    return failures ? 1 : 0;
}
