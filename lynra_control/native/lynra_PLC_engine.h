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
 LYNRA_TIMER_MULTI_FUNCTION, LYNRA_TIMER_STOPWATCH
} LynraActionType;
typedef enum { LYNRA_RUN_ONCE, LYNRA_RUN_REPEAT } LynraRunPolicy;
typedef enum { LYNRA_OUTPUT_FOLLOW, LYNRA_OUTPUT_LATCH } LynraOutputBehavior;
typedef struct { uint8_t input_index; LynraConditionTrigger trigger; } LynraCondition;
typedef struct {
 LynraActionType type;
 uint8_t output_index;
 uint32_t t_ms, th_ms, tl_ms;
 uint32_t warning_before_ms, warning_off_ms;
 uint8_t n;
 uint8_t stopwatch_time_base; /* 0=ms, 1=seconds, 2=minutes */
 uint8_t reset_input_index; /* Retentive timer R input; 0 = no external reset */
} LynraAction;
typedef struct {
 uint32_t id;
 LynraLogicOperator logic_operator;
 LynraOutputBehavior output_behavior;
 LynraRunPolicy run_policy;
 uint32_t on_delay_ms, off_delay_ms;
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
bool lynra_plc_get_stopwatch(const LynraPlcEngine *engine, size_t rule_index,
                            size_t action_index, uint64_t *value);
#ifdef __cplusplus
}
#endif
#endif
