
#include "lynra_PLC_engine.h"
#include <string.h>
static bool lynra_has_edge_condition(const LynraRule *rule);
static void lynra_process_pending_outputs(
    LynraPlcEngine *engine,
    uint64_t now_ms);
#define LYNRA_PLC_MAX_INSTANCES 1 // ?*? 2

typedef struct
{
    bool previous_match;
    bool match_initialized;
    bool completed_once;

    bool raw_on_active;
    bool raw_off_active;
    uint64_t raw_on_since_ms;
    uint64_t raw_off_since_ms;

    bool timed_match;
    bool running;

    uint8_t action_index;
    bool wait_active;
    uint64_t wait_until_ms;

    uint32_t output_versions[LYNRA_PLC_MAX_OUTPUTS];
    uint32_t blink_activation_serial;
    bool blink_active;
    uint64_t blink_started_ms;
    bool priority_rearm;
    uint64_t onr_elapsed_ms[LYNRA_PLC_MAX_ACTIONS];
    uint64_t onr_last_ms[LYNRA_PLC_MAX_ACTIONS];
    bool onr_counting[LYNRA_PLC_MAX_ACTIONS];
    bool onr_done[LYNRA_PLC_MAX_ACTIONS];
    bool nor_armed;
    bool not_armed;
} LynraRuleState;

typedef struct
{
    bool active;
    bool value;

    uint64_t due_ms;

    uint16_t rule_index;
    uint8_t action_index;
} LynraPendingOutput;

struct LynraPlcEngine
{
    bool in_use;

    LynraRule rules[LYNRA_PLC_MAX_RULES];
    size_t rule_count;

    LynraRuleState states[LYNRA_PLC_MAX_RULES];

    uint32_t outputs;
    LynraPendingOutput pending_outputs[LYNRA_PLC_MAX_OUTPUTS];
    uint32_t output_versions[LYNRA_PLC_MAX_OUTPUTS];
    uint32_t reset_priority_mask;
    uint32_t reset_fired[LYNRA_PLC_MAX_RULES];
    uint32_t blink_suppressed_through[LYNRA_PLC_MAX_OUTPUTS];
    uint32_t blink_activation_serial;

    uint32_t previous_inputs;

    uint64_t last_now_ms;
    bool has_last_scan;

    int16_t blink_owner[LYNRA_PLC_MAX_OUTPUTS];
    uint64_t blink_owner_started_ms[LYNRA_PLC_MAX_OUTPUTS];
    bool blink_owner_valid[LYNRA_PLC_MAX_OUTPUTS];
    uint64_t blink_phase_started_ms[LYNRA_PLC_MAX_OUTPUTS];
    uint32_t blink_phase_duration_ms[LYNRA_PLC_MAX_OUTPUTS];
    uint32_t blink_completed_pulses[LYNRA_PLC_MAX_OUTPUTS];
    bool blink_phase_on[LYNRA_PLC_MAX_OUTPUTS];
    uint32_t blink_rng;
};

static uint32_t lynra_blink_random(LynraPlcEngine *engine, uint32_t min_ms, uint32_t max_ms, uint32_t fixed_ms)
{
    if (min_ms == 0 && max_ms == 0) return fixed_ms;
    if (max_ms < min_ms) return fixed_ms;
    if (min_ms == max_ms) return min_ms;
    // xorshift32; deterministic per-engine PRNG, not cryptographic.
    uint32_t x = engine->blink_rng;
    if (!x) x = 0x9E3779B9u;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    engine->blink_rng = x;
    uint64_t span = (uint64_t)max_ms - min_ms + 1u;
    return (uint32_t)(min_ms + (uint64_t)x % span);
}

static LynraPlcEngine engine_pool[LYNRA_PLC_MAX_INSTANCES];
static void lynra_write_output(
    LynraPlcEngine *engine,
    uint8_t output_index,
    bool value,
    bool from_blink);

LynraPlcEngine *lynra_plc_create(void)
{
    for (size_t i = 0; i < LYNRA_PLC_MAX_INSTANCES; i++)
    {
        if (!engine_pool[i].in_use)
        {
            memset(&engine_pool[i], 0, sizeof(engine_pool[i]));
            engine_pool[i].in_use = true;
            return &engine_pool[i];
        }
    }
    return NULL;
}

void lynra_plc_destroy(LynraPlcEngine *engine)
{
    if (engine == NULL)
        return;
    memset(engine, 0, sizeof(*engine));
}

void lynra_plc_reset(LynraPlcEngine *engine)
{
    if (engine == NULL)
        return;
    memset(engine->states, 0, sizeof(engine->states));

    engine->outputs = 0;
    engine->previous_inputs = 0;
    engine->last_now_ms = 0;
    engine->has_last_scan = false;

    memset(engine->output_versions, 0, sizeof(engine->output_versions));
    memset(engine->blink_suppressed_through, 0,
           sizeof(engine->blink_suppressed_through));
    memset(engine->pending_outputs, 0,
           sizeof(engine->pending_outputs));

    memset(engine->blink_owner, 0, sizeof(engine->blink_owner));
    memset(engine->blink_owner_started_ms, 0,
           sizeof(engine->blink_owner_started_ms));
    memset(engine->blink_owner_valid, 0,
           sizeof(engine->blink_owner_valid));

    memset(engine->blink_phase_duration_ms, 0, sizeof(engine->blink_phase_duration_ms));
    memset(engine->blink_phase_started_ms, 0, sizeof(engine->blink_phase_started_ms));
    memset(engine->blink_completed_pulses, 0, sizeof(engine->blink_completed_pulses));
    memset(engine->blink_phase_on, 0, sizeof(engine->blink_phase_on));

    engine->reset_priority_mask = 0;
    memset(engine->reset_fired, 0, sizeof(engine->reset_fired));
    engine->blink_activation_serial = 0;
}

bool lynra_plc_load_rules(
    LynraPlcEngine *engine,
    const LynraRule *rules,
    size_t rule_count)
{
    if (engine == NULL || rule_count > LYNRA_PLC_MAX_RULES)
        return false;

    if (rule_count > 0 && rules == NULL)
        return false;

    for (size_t i = 0; i < rule_count; i++)
    {
        if (rules[i].condition_count > LYNRA_PLC_MAX_CONDITIONS ||
            rules[i].action_count > LYNRA_PLC_MAX_ACTIONS)
            return false;
        for (uint8_t a = 0; a < rules[i].action_count; ++a) {
            const LynraAction *act = &rules[i].actions[a];
            if (act->onr_delay_ms != 0 &&
                (act->type != LYNRA_ACTION_OUTPUT || !act->output_state ||
                 act->output_index < 1 || act->output_index > LYNRA_PLC_MAX_OUTPUTS ||
                 lynra_has_edge_condition(&rules[i])))
                return false;
        }
    }

    if (rule_count > 0)
    {
        memcpy(engine->rules, rules, rule_count * sizeof(LynraRule));
    }

    engine->rule_count = rule_count;
    lynra_plc_reset(engine);
    return true;
}

uint32_t lynra_plc_get_outputs(const LynraPlcEngine *engine)
{
    return engine != NULL ? engine->outputs : 0;
}

static bool lynra_matches(
    const LynraRule *rule,
    LynraRuleState *state,
    uint32_t inputs,
    uint32_t previous_inputs)
{
    if (rule->condition_count == 0)
        return false;

    uint8_t true_count = 0;

    for (uint8_t i = 0; i < rule->condition_count; i++)
    {
        const LynraCondition *condition = &rule->conditions[i];

        if (condition->input_index < 1 ||
            condition->input_index > LYNRA_PLC_MAX_INPUTS)
            return false;

        uint32_t bit = 1u << (condition->input_index - 1);

        bool current = (inputs & bit) != 0;
        bool previous = (previous_inputs & bit) != 0;
        bool matched = false;

        switch (condition->trigger)
        {
        case LYNRA_TRIGGER_HIGH:
            matched = current;
            break;

        case LYNRA_TRIGGER_LOW:
            matched = !current;
            break;

        case LYNRA_TRIGGER_RISING:
            matched = !previous && current;
            break;

        case LYNRA_TRIGGER_FALLING:
            matched = previous && !current;
            break;

        default:
            return false;
        }

        if (matched)
            true_count++;
    }

    switch (rule->logic_operator)
    {
    case LYNRA_LOGIC_AND:
        return true_count == rule->condition_count;

    case LYNRA_LOGIC_OR:
        return true_count > 0;

    case LYNRA_LOGIC_XOR:
        return (true_count % 2) != 0;

    case LYNRA_LOGIC_AND_EDGE:
        return true_count == rule->condition_count;
    case LYNRA_LOGIC_NAND:
    case LYNRA_LOGIC_NAND_EDGE:
        return true_count != rule->condition_count;
    case LYNRA_LOGIC_NOR:
        if (true_count > 0)
            state->nor_armed = true;
        return state->nor_armed && true_count == 0;
    case LYNRA_LOGIC_NOT:
        if (true_count > 0)
            state->not_armed = true;
        return state->not_armed && true_count == 0;

    default:
        return false;
    }
}
static bool lynra_has_edge_condition(const LynraRule *rule);
static void lynra_start_rule(LynraPlcEngine *engine, LynraRuleState *state);
static void lynra_advance_rule(
    LynraPlcEngine *engine,
    uint16_t rule_index,
    uint64_t now_ms);
static void lynra_command_output(
    LynraPlcEngine *engine,
    const LynraAction *action,
    uint16_t rule_index,
    uint8_t action_index,
    bool value,
    uint64_t now_ms);
bool lynra_plc_scan(
    LynraPlcEngine *engine,
    uint64_t now_ms,
    uint32_t input_mask)
{
    if (engine == NULL)
        return false;

    // Time must be monotonic.
    if (engine->has_last_scan &&
        now_ms < engine->last_now_ms)
        return false;
    memset(engine->blink_phase_duration_ms, 0, sizeof(engine->blink_phase_duration_ms));
    memset(engine->blink_phase_started_ms, 0, sizeof(engine->blink_phase_started_ms));
    memset(engine->blink_completed_pulses, 0, sizeof(engine->blink_completed_pulses));
    memset(engine->blink_phase_on, 0, sizeof(engine->blink_phase_on));

    engine->reset_priority_mask = 0;
    memset(engine->reset_fired, 0, sizeof(engine->reset_fired));
    engine->last_now_ms = now_ms;
    engine->has_last_scan = true;

    for (size_t i = 0; i < engine->rule_count; i++)
    {

        const LynraRule *rule = &engine->rules[i];
        LynraRuleState *state = &engine->states[i];

        bool raw_match = lynra_matches(
            rule,
            state,
            input_mask,
            engine->previous_inputs);

        // TON: condition must remain true.
        if (raw_match)
        {
            state->raw_off_active = false;

            if (!state->raw_on_active)
            {
                state->raw_on_active = true;
                state->raw_on_since_ms = now_ms;
            }

            if (now_ms - state->raw_on_since_ms >=
                rule->on_delay_ms)
            {
                state->timed_match = true;
            }
        }
        // TOF: hold effective condition after falling.
        else
        {
            state->raw_on_active = false;

            if (state->timed_match)
            {
                if (!state->raw_off_active)
                {
                    state->raw_off_active = true;
                    state->raw_off_since_ms = now_ms;
                }

                if (now_ms - state->raw_off_since_ms >=
                    rule->off_delay_ms)
                {
                    state->timed_match = false;
                    state->raw_off_active = false;
                }
            }
        }

        // Effective condition transitions.
        bool matched = state->timed_match;
        bool rising = matched && !state->previous_match;
        if (rule->logic_operator == LYNRA_LOGIC_NAND_EDGE &&
            !state->match_initialized)
        {
            rising = false;
            state->match_initialized = true;
        }

        // Action execution will be added next.

        bool edge_rule = lynra_has_edge_condition(rule);
        bool blink_only = !edge_rule && rule->action_count > 0;

        for (uint8_t a = 0; a < rule->action_count; a++)
        {
            if (rule->actions[a].type != LYNRA_ACTION_BLINK)
            {
                blink_only = false;
                break;
            }
        }

        // BLINK-only rules: N=0 retains the existing LEVEL behavior.
        // N>0 is a one-shot pulse train, started by a new activation.
        if (blink_only)
        {
            bool finite = false;
            for (uint8_t a = 0; a < rule->action_count; ++a)
                if (rule->actions[a].blink_count > 0) finite = true;

            if (!finite)
            {
                if (matched && !state->blink_active)
                {
                    state->blink_active = true;
                    state->blink_started_ms = now_ms;
                    state->blink_activation_serial = ++engine->blink_activation_serial;
                }
                else if (!matched)
                    state->blink_active = false;
            }
            else if (rising)
            {
                // New edge/LEVEL activation retriggers even mid-train.
                state->blink_active = true;
                state->blink_started_ms = now_ms;
                state->blink_activation_serial = ++engine->blink_activation_serial;
            }
        }

        if (edge_rule && rule->action_count > 0)
        {
            bool all_blink = true;
            for (uint8_t a = 0; a < rule->action_count; ++a)
                if (rule->actions[a].type != LYNRA_ACTION_BLINK)
                    all_blink = false;
            bool finite_blink = false;
            for (uint8_t a = 0; a < rule->action_count; ++a)
                if (rule->actions[a].blink_count > 0) finite_blink = true;
            if (all_blink && finite_blink && rising)
            {
                state->blink_active = true;
                state->blink_started_ms = now_ms;
                state->blink_activation_serial = ++engine->blink_activation_serial;
            }
        }

        if (edge_rule)
        {
            if ((rule->logic_operator == LYNRA_LOGIC_AND_EDGE ||
                 rule->logic_operator == LYNRA_LOGIC_NAND_EDGE) &&
                !rising &&
                rule->output_behavior == LYNRA_OUTPUT_FOLLOW)
            {

                for (uint8_t a = 0; a < rule->action_count; a++)
                {
                    const LynraAction *action = &rule->actions[a];

                    if (action->type == LYNRA_ACTION_OUTPUT && action->onr_delay_ms == 0)
                    {
                        lynra_command_output(
                            engine, action, (uint16_t)i, a,
                            !action->output_state, now_ms);
                    }
                }
            }
            // EDGE: RUN_ONCE ignores triggers during an active sequence.
            // RUN_REPEAT retriggers: restart the sequence from its first action.
            if (rising && (!state->running || rule->run_policy == LYNRA_RUN_REPEAT))
            {
                if (state->running)
                {
                    // Cancel delayed output commands belonging to the old run.
                    // Do not interfere with other rules' pending commands.
                    for (uint8_t oi = 0; oi < LYNRA_PLC_MAX_OUTPUTS; ++oi)
                    {
                        LynraPendingOutput *pending = &engine->pending_outputs[oi];
                        if (pending->active && pending->rule_index == i)
                            pending->active = false;
                    }
                }
                lynra_start_rule(engine, state);
            }

            if (state->running)
                lynra_advance_rule(engine, (uint16_t)i, now_ms);

            // For a single rising-edge input, TOFF follows the physical
            // falling edge, not the one-scan rising-edge match.
            if (rule->condition_count == 1 &&
                rule->conditions[0].trigger == LYNRA_TRIGGER_RISING &&
                rule->output_behavior == LYNRA_OUTPUT_FOLLOW)
            {
                uint8_t input_index = rule->conditions[0].input_index;
                if (input_index >= 1 && input_index <= LYNRA_PLC_MAX_INPUTS)
                {
                    uint32_t input_bit = 1u << (input_index - 1);
                    bool falling = (engine->previous_inputs & input_bit) != 0 &&
                                   (input_mask & input_bit) == 0;
                    if (falling)
                    {
                        for (uint8_t a = 0; a < rule->action_count; ++a)
                        {
                            const LynraAction *action = &rule->actions[a];
                            if (action->type == LYNRA_ACTION_OUTPUT &&
                                action->output_state && action->off_delay_ms > 0 &&
                                action->onr_delay_ms == 0)
                            {
                                lynra_command_output(engine, action, (uint16_t)i,
                                                     a, false, now_ms);
                            }
                        }
                    }
                }
            }
        }
        else
        {
            if (!matched)
            {
                state->completed_once = false;
                state->priority_rearm = false;
                state->running = false;
                state->action_index = 0;
                state->wait_active = false;

                if (rule->output_behavior == LYNRA_OUTPUT_FOLLOW)
                {
                    for (uint8_t a = 0; a < rule->action_count; a++)
                    {
                        const LynraAction *action = &rule->actions[a];

                        if (action->type == LYNRA_ACTION_OUTPUT && action->onr_delay_ms == 0)
                        {
                            lynra_command_output(
                                engine, action, (uint16_t)i, a,
                                !action->output_state, now_ms);
                        }
                    }
                }
            }
            else
            {
                bool latch_only = rule->action_count > 0;

                for (uint8_t a = 0; a < rule->action_count; a++)
                {
                    LynraActionType type = rule->actions[a].type;

                    if (type != LYNRA_ACTION_SET &&
                        type != LYNRA_ACTION_RESET)
                    {
                        latch_only = false;
                        break;
                    }
                }

                bool can_start = rule->run_policy == LYNRA_RUN_ONCE
                                     ? (!state->completed_once || state->priority_rearm)
                                     : (!latch_only || rising || state->priority_rearm);

                if (!state->running && can_start)
                {
                    state->priority_rearm = false;
                    lynra_start_rule(engine, state);
                }

                if (state->running)
                {
                    lynra_advance_rule(engine, (uint16_t)i, now_ms);

                    if (!state->running &&
                        rule->run_policy == LYNRA_RUN_ONCE)
                        state->completed_once = true;
                }
            }
        }

        state->previous_match = matched;
    }
    // A level RESET in a lower rule stays authoritative on every scan.
    // Cancel older rules' pending output transitions and running actions.
    // Do not reset the older rule's edge/level history: it must be
    // triggered anew after the RESET condition is released.
    for (size_t ri = 0; ri < engine->rule_count; ++ri)
    {
        const LynraRule *reset_rule = &engine->rules[ri];
        if (lynra_has_edge_condition(reset_rule) ||
            !engine->states[ri].timed_match)
            continue;

        for (uint8_t ai = 0; ai < reset_rule->action_count; ++ai)
        {
            const LynraAction *reset_action = &reset_rule->actions[ai];
            if (reset_action->type != LYNRA_ACTION_RESET ||
                reset_action->off_delay_ms != 0 ||
                reset_action->output_index < 1 ||
                reset_action->output_index > LYNRA_PLC_MAX_OUTPUTS)
                continue;

            uint8_t oi = reset_action->output_index;
            uint32_t bit = 1u << (oi - 1);
            for (size_t upper = 0; upper < ri; ++upper)
            {
                const LynraRule *r = &engine->rules[upper];
                bool targets_output = false;
                for (uint8_t a = 0; a < r->action_count; ++a)
                {
                    if (r->actions[a].output_index == oi &&
                        r->actions[a].type != LYNRA_ACTION_DELAY)
                    {
                        targets_output = true;
                        break;
                    }
                }
                if (!targets_output)
                    continue;

                LynraRuleState *st = &engine->states[upper];
                st->running = false;
                st->wait_active = false;
                st->action_index = 0;
                st->completed_once = true;
                if (!lynra_has_edge_condition(r))
                    st->priority_rearm = true;
                st->blink_active = false;
            }
            LynraPendingOutput *pending = &engine->pending_outputs[oi - 1];
            if (pending->active && pending->rule_index < ri)
                pending->active = false;

            if ((engine->outputs & bit) != 0)
                lynra_write_output(engine, oi, false, false);
            engine->reset_priority_mask |= bit;
        }
    }

    // Retentive ON delay (ONR): elapsed time is stored per rule/action.
    // A lower RESET clears elapsed time even before the output ever turned ON.
    for (size_t ri = 0; ri < engine->rule_count; ++ri) {
        const LynraRule *rule = &engine->rules[ri];
        LynraRuleState *st = &engine->states[ri];
        for (uint8_t ai = 0; ai < rule->action_count; ++ai) {
            const LynraAction *a = &rule->actions[ai];
            if (a->onr_delay_ms == 0) continue;
            const uint32_t bit = 1u << (a->output_index - 1);
            bool reset = false;
            for (size_t lower = ri + 1; lower < engine->rule_count && !reset; ++lower) {
                const LynraRule *lr = &engine->rules[lower];
                bool level_active = !lynra_has_edge_condition(lr) &&
                                    engine->states[lower].timed_match;
                for (uint8_t j = 0; j < lr->action_count; ++j) {
                    const LynraAction *ra = &lr->actions[j];
                    if (ra->type == LYNRA_ACTION_RESET &&
                        ra->off_delay_ms == 0 && ra->output_index == a->output_index &&
                        (level_active || (engine->reset_fired[lower] & bit))) {
                        reset = true;
                        break;
                    }
                }
            }
            if (reset) {
                st->onr_elapsed_ms[ai] = 0;
                st->onr_counting[ai] = false;
                st->onr_done[ai] = false;
                continue;
            }
            if (!st->timed_match || st->onr_done[ai]) {
                st->onr_counting[ai] = false;
                continue;
            }
            if (st->onr_counting[ai]) {
                uint64_t delta = now_ms - st->onr_last_ms[ai];
                uint64_t remaining = a->onr_delay_ms - st->onr_elapsed_ms[ai];
                st->onr_elapsed_ms[ai] += delta < remaining ? delta : remaining;
            }
            st->onr_last_ms[ai] = now_ms;
            st->onr_counting[ai] = true;
            if (st->onr_elapsed_ms[ai] >= a->onr_delay_ms) {
                st->onr_done[ai] = true;
                // ONR is an immediate ON command once its accumulated time expires.
                // The normal on_delay_ms is intentionally ignored.
                lynra_write_output(engine, a->output_index, true, false);
            }
        }
    }

    lynra_process_pending_outputs(engine, now_ms);
    // Resolve FLASH ownership per output.
    for (uint8_t oi = 0; oi < LYNRA_PLC_MAX_OUTPUTS; oi++)
    {
        int16_t winner = -1;
        uint32_t highest_serial = 0;
        const LynraAction *winner_action = NULL;

        for (size_t i = 0; i < engine->rule_count; i++)
        {
            const LynraRule *rule = &engine->rules[i];
            const LynraRuleState *state = &engine->states[i];

            if (!state->blink_active)
                continue;

            if (state->blink_activation_serial <=
                engine->blink_suppressed_through[oi])
                continue;

            for (uint8_t a = 0; a < rule->action_count; a++)
            {
                const LynraAction *action = &rule->actions[a];

                if (action->type != LYNRA_ACTION_BLINK ||
                    action->output_index != oi + 1 ||
                    action->duration_ms == 0 ||
                    action->off_duration_ms == 0)
                    continue;

                if (winner < 0 ||
                    state->blink_activation_serial > highest_serial)
                {
                    winner = (int16_t)i;
                    highest_serial = state->blink_activation_serial;
                    winner_action = action;
                }
            }
        }

        uint32_t bit = 1u << oi;

        if ((engine->reset_priority_mask & bit) != 0)
        {
            engine->blink_owner_valid[oi] = false;
            continue;
        }

        if (winner < 0)
        {
            if (engine->blink_owner_valid[oi])
            {
                engine->blink_owner_valid[oi] = false;
                lynra_write_output(engine, oi + 1, false, true);
            }
            continue;
        }

        if (!engine->blink_owner_valid[oi] ||
            engine->blink_owner[oi] != winner ||
            engine->blink_owner_started_ms[oi] != engine->states[winner].blink_started_ms)
        {
            engine->blink_owner_valid[oi] = true;
            engine->blink_owner[oi] = winner;
            engine->blink_owner_started_ms[oi] = engine->states[winner].blink_started_ms;
            engine->blink_phase_duration_ms[oi] = 0;
            engine->blink_completed_pulses[oi] = 0;
        }

        bool desired = false;
        bool finished = false;
        const bool random_on = winner_action->blink_on_min_ms || winner_action->blink_on_max_ms;
        const bool random_off = winner_action->blink_off_min_ms || winner_action->blink_off_max_ms;
        if (!random_on && !random_off)
        {
            uint64_t elapsed = now_ms - engine->blink_owner_started_ms[oi];
            uint64_t start_delay = winner_action->blink_start_delay_ms;
            uint64_t on_time = winner_action->duration_ms;
            uint64_t off_time = winner_action->off_duration_ms;
            uint64_t period = on_time + off_time;
            uint32_t count = winner_action->blink_count;
            if (elapsed >= start_delay)
            {
                uint64_t active_elapsed = elapsed - start_delay;
                if (count > 0 &&
                    active_elapsed >= (uint64_t)(count - 1) * period + on_time)
                    finished = true;
                else
                    desired = (active_elapsed % period) < on_time;
            }
            if (finished)
            {
                engine->states[winner].blink_active = false;
                engine->blink_owner_valid[oi] = false;
            }
    
        }
        else
        {
            uint64_t start_at = engine->blink_owner_started_ms[oi] + winner_action->blink_start_delay_ms;
            if (now_ms >= start_at)
            {
                // Phase is initialized at the actual activation timestamp, not the first scan.
                // On a delayed scan, advance through elapsed phase boundaries.
                if (engine->blink_phase_duration_ms[oi] == 0)
                {
                    engine->blink_phase_started_ms[oi] = start_at;
                    engine->blink_phase_on[oi] = true;
                    engine->blink_completed_pulses[oi] = 0;
                    engine->blink_phase_duration_ms[oi] = lynra_blink_random(engine,
                        winner_action->blink_on_min_ms, winner_action->blink_on_max_ms,
                        winner_action->duration_ms);
                }
                for (uint32_t guard = 0; guard < 100000 && !finished; guard++)
                {
                    uint64_t boundary = engine->blink_phase_started_ms[oi] + engine->blink_phase_duration_ms[oi];
                    if (now_ms < boundary) break;
                    engine->blink_phase_started_ms[oi] = boundary;
                    if (engine->blink_phase_on[oi])
                    {
                        engine->blink_completed_pulses[oi]++;
                        if (winner_action->blink_count > 0 &&
                            engine->blink_completed_pulses[oi] >= winner_action->blink_count)
                        {
                            finished = true;
                            break;
                        }
                        engine->blink_phase_on[oi] = false;
                        engine->blink_phase_duration_ms[oi] = lynra_blink_random(engine,
                            winner_action->blink_off_min_ms, winner_action->blink_off_max_ms,
                            winner_action->off_duration_ms);
                    }
                    else
                    {
                        engine->blink_phase_on[oi] = true;
                        engine->blink_phase_duration_ms[oi] = lynra_blink_random(engine,
                            winner_action->blink_on_min_ms, winner_action->blink_on_max_ms,
                            winner_action->duration_ms);
                    }
                }
                desired = !finished && engine->blink_phase_on[oi];
            }
            if (finished)
            {
                engine->states[winner].blink_active = false;
                engine->blink_owner_valid[oi] = false;
            }
        }

        if (((engine->outputs & bit) != 0) != desired)
        {
            lynra_write_output(engine, oi + 1, desired, true);
        }
    }

    engine->previous_inputs = input_mask;

    return true;
}

static void lynra_write_output(
    LynraPlcEngine *engine,
    uint8_t output_index,
    bool value,
    bool from_blink)
{
    if (output_index < 1 ||
        output_index > LYNRA_PLC_MAX_OUTPUTS)
        return;

    uint32_t index = output_index - 1;
    uint32_t bit = 1u << index;

    // Any output write cancels a pending transition.
    engine->pending_outputs[index].active = false;

    if (value)
        engine->outputs |= bit;
    else
        engine->outputs &= ~bit;

    engine->output_versions[index]++;

    // Explicit commands suppress existing FLASH activations.
    if (!from_blink)
    {
        engine->blink_suppressed_through[index] =
            engine->blink_activation_serial;
    }
}

static void lynra_command_output(
    LynraPlcEngine *engine,
    const LynraAction *action,
    uint16_t rule_index,
    uint8_t action_index,
    bool value,
    uint64_t now_ms)
{
    uint8_t output_index = action->output_index;

    if (output_index < 1 ||
        output_index > LYNRA_PLC_MAX_OUTPUTS)
        return;

    uint32_t index = output_index - 1;
    uint32_t bit = 1u << index;

    uint32_t delay = value
                         ? action->on_delay_ms
                         : action->off_delay_ms;

    LynraPendingOutput *pending =
        &engine->pending_outputs[index];

    // Immediate command.
    if (delay == 0)
    {
        pending->active = false;
        lynra_write_output(engine, output_index, value, false);
        return;
    }

    // Same pending command: do not restart timer.
    if (pending->active &&
        pending->rule_index == rule_index &&
        pending->action_index == action_index &&
        pending->value == value)
        return;

    // Output already has the requested state.
    if (((engine->outputs & bit) != 0) == value)
    {
        pending->active = false;
        return;
    }

    // New command supersedes previous pending command.
    pending->active = true;
    pending->value = value;
    pending->due_ms = now_ms + delay;
    pending->rule_index = rule_index;
    pending->action_index = action_index;

    engine->output_versions[index]++;
    engine->blink_suppressed_through[index] =
        engine->blink_activation_serial;
}

static void lynra_process_pending_outputs(
    LynraPlcEngine *engine,
    uint64_t now_ms)
{
    for (uint8_t i = 0; i < LYNRA_PLC_MAX_OUTPUTS; i++)
    {

        LynraPendingOutput *pending =
            &engine->pending_outputs[i];

        if (!pending->active)
            continue;

        if (now_ms < pending->due_ms)
            continue;

        bool value = pending->value;

        pending->active = false;

        lynra_write_output(engine, i + 1, value, false);
    }
}

static void lynra_start_rule(
    LynraPlcEngine *engine,
    LynraRuleState *state)
{
    state->running = true;
    state->action_index = 0;
    state->wait_active = false;
    state->wait_until_ms = 0;

    memcpy(
        state->output_versions,
        engine->output_versions,
        sizeof(state->output_versions));
}

static void lynra_advance_rule(
    LynraPlcEngine *engine,
    uint16_t rule_index,
    uint64_t now_ms)
{
    const LynraRule *rule = &engine->rules[rule_index];
    LynraRuleState *state = &engine->states[rule_index];

    while (state->running &&
           state->action_index < rule->action_count)
    {

        uint8_t ai = state->action_index;
        const LynraAction *action = &rule->actions[ai];

        // ONR is evaluated continuously, independently of RUN_ONCE and action sequencing.
        if (action->onr_delay_ms != 0) {
            state->action_index++;
            continue;
        }
        // FLASH is handled separately.
        if (action->type == LYNRA_ACTION_BLINK)
        {
            state->action_index++;
            continue;
        }

        // DELAY does not operate on an output.
        if (action->type == LYNRA_ACTION_DELAY)
        {
            if (!state->wait_active)
            {
                state->wait_active = true;
                state->wait_until_ms =
                    now_ms + action->duration_ms;
            }

            if (now_ms < state->wait_until_ms)
                return;

            state->wait_active = false;
            state->action_index++;
            continue;
        }

        uint8_t oi = action->output_index;

        if (oi < 1 || oi > LYNRA_PLC_MAX_OUTPUTS)
        {
            state->action_index++;
            continue;
        }

        uint32_t index = oi - 1;

        // A newer output command supersedes this action.
        if (action->type != LYNRA_ACTION_RESET &&
            engine->output_versions[index] !=
                state->output_versions[index])
        {
            state->action_index++;
            continue;
        }

        bool value;

        switch (action->type)
        {
        case LYNRA_ACTION_OUTPUT:
            value = action->output_state;
            break;

        case LYNRA_ACTION_SET:
            value = true;
            break;

        case LYNRA_ACTION_RESET:
            value = false;
            break;

        case LYNRA_ACTION_TOGGLE:
            value =
                (engine->outputs & (1u << index)) == 0;
            break;

        default:
            state->action_index++;
            continue;
        }
        // RESET has priority over SET in the same scan.
        if (value &&
            (engine->reset_priority_mask & (1u << index)) != 0)
        {
            state->action_index++;
            continue;
        }
        lynra_command_output(
            engine, action, rule_index, ai, value, now_ms);

        state->output_versions[index] =
            engine->output_versions[index];

        if (action->type == LYNRA_ACTION_RESET &&
            action->off_delay_ms == 0)
        {
            engine->reset_fired[rule_index] |= (1u << index);
            engine->reset_priority_mask |= (1u << index);
        }

        state->action_index++;
    }

    if (state->action_index >= rule->action_count)
        state->running = false;
}

static bool lynra_has_edge_condition(const LynraRule *rule)
{
    if (rule->logic_operator == LYNRA_LOGIC_AND_EDGE ||
        rule->logic_operator == LYNRA_LOGIC_NAND_EDGE)
        return true;
    if (rule->logic_operator == LYNRA_LOGIC_AND_EDGE)
        return true;
    for (uint8_t i = 0; i < rule->condition_count; i++)
    {
        LynraConditionTrigger trigger = rule->conditions[i].trigger;

        if (trigger == LYNRA_TRIGGER_RISING ||
            trigger == LYNRA_TRIGGER_FALLING)
            return true;
    }

    return false;
}
