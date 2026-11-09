#ifndef LYNRA_PLC_ENGINE_H
#define LYNRA_PLC_ENGINE_H
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
#define LYNRA_PLC_MAX_INPUTS 32
#define LYNRA_PLC_MAX_OUTPUTS 32
#define LYNRA_PLC_MAX_RULES 64
#define LYNRA_PLC_MAX_CONDITIONS 8
#define LYNRA_PLC_MAX_ACTIONS 16

typedef enum { LYNRA_LOGIC_AND, LYNRA_LOGIC_OR, LYNRA_LOGIC_XOR, LYNRA_LOGIC_AND_EDGE, LYNRA_LOGIC_NAND, LYNRA_LOGIC_NAND_EDGE, LYNRA_LOGIC_NOR, LYNRA_LOGIC_NOT } LynraLogicOperator;
typedef enum { LYNRA_TRIGGER_HIGH, LYNRA_TRIGGER_LOW, LYNRA_TRIGGER_RISING, LYNRA_TRIGGER_FALLING } LynraConditionTrigger;
typedef enum {
 LYNRA_TIMER_ON_DELAY, LYNRA_TIMER_OFF_DELAY, LYNRA_TIMER_ON_OFF_DELAY,
 LYNRA_TIMER_RETENTIVE_ON_DELAY, LYNRA_TIMER_WIPING_RELAY,
 LYNRA_TIMER_EDGE_WIPING_RELAY, LYNRA_TIMER_ASYNC_PULSE,
 LYNRA_TIMER_RANDOM_GENERATOR, LYNRA_TIMER_STAIRWAY,
 LYNRA_TIMER_MULTI_FUNCTION, LYNRA_TIMER_STOPWATCH,
 LYNRA_COUNTER_UP_DOWN,
 LYNRA_COUNTER_HOURS,
 LYNRA_THRESHOLD_TRIGGER
} LynraActionType;
typedef enum { LYNRA_RUN_ONCE, LYNRA_RUN_REPEAT } LynraRunPolicy;
typedef enum { LYNRA_EXEC_IDLE, LYNRA_EXEC_RUNNING, LYNRA_EXEC_COMPLETED } LynraExecutionState;
typedef struct { uint8_t input_index; LynraConditionTrigger trigger; } LynraCondition;
typedef struct {
 LynraActionType type;
 uint8_t output_index;
 uint32_t t_ms, th_ms, tl_ms;
 uint32_t warning_before_ms, warning_off_ms;
 uint8_t n;
 uint8_t stopwatch_time_base; /* 0=ms, 1=seconds, 2=minutes */
 uint8_t reset_input_index; /* Retentive timer R input; 0 = no external reset */
 uint8_t repeat; /* 0=single cycle, 1=repeat until RESET */
 uint8_t retrigger; /* 0=ignore new trigger, 1=restart from beginning */
 uint8_t counter_input_index;   /* Cnt */
 uint8_t direction_input_index; /* Dir: 0=UP, 1=DOWN */
 int32_t counter_start_value;
 int32_t counter_on;
 int32_t counter_off;
 uint8_t hours_enable_input_index;  /* EN */
 uint8_t hours_reset_all_input_index; /* Ral */
 uint64_t hours_target_ms;          /* Target */
 uint8_t threshold_input_index;   /* Fre */
 uint32_t threshold_gate_ms;      /* G_T: 0-100000 ms */
 uint32_t threshold_on;           /* On: pulse count */
 uint32_t threshold_off;          /* Off: pulse count */
} LynraAction;
typedef struct {
 uint32_t id;
 LynraLogicOperator logic_operator;
 LynraRunPolicy run_policy;
 uint8_t condition_count;
 LynraCondition conditions[LYNRA_PLC_MAX_CONDITIONS];
 uint8_t action_count;
 LynraAction actions[LYNRA_PLC_MAX_ACTIONS];
} LynraRule;
typedef struct LynraPlcEngine LynraPlcEngine;
LynraPlcEngine *lynra_plc_create(void);
void lynra_plc_destroy(LynraPlcEngine *engine);
void lynra_plc_reset(LynraPlcEngine *engine);
bool lynra_plc_load_rules(LynraPlcEngine *engine, const LynraRule *rules, size_t count);
bool lynra_plc_scan(LynraPlcEngine *engine, uint64_t now_ms, uint32_t inputs);
uint32_t lynra_plc_get_outputs(const LynraPlcEngine *engine);
bool lynra_plc_get_action_state(const LynraPlcEngine *engine, size_t rule_index,
                                size_t action_index, LynraExecutionState *state);
bool lynra_plc_get_rule_state(const LynraPlcEngine *engine, size_t rule_index,
                              LynraExecutionState *state);
bool lynra_plc_get_stopwatch(const LynraPlcEngine *engine, size_t rule_index,
                            size_t action_index, uint64_t *value);
bool lynra_plc_get_counter(
    const LynraPlcEngine *engine,
    size_t rule_index,
    size_t action_index,
    int32_t *value);
bool lynra_plc_get_hours(
    const LynraPlcEngine *engine,
    size_t rule_index,
    size_t action_index,
    uint64_t *elapsed_ms,
    uint64_t *total_ms);
bool lynra_plc_get_threshold(
    const LynraPlcEngine *engine,
    size_t rule_index,
    size_t action_index,
    uint32_t *pulse_count);
#ifdef __cplusplus
}
#endif
#endif
