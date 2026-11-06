
#ifndef LYNRA_PLC_ENGINE_H
#define LYNRA_PLC_ENGINE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LYNRA_PLC_MAX_INPUTS       32
#define LYNRA_PLC_MAX_OUTPUTS      32
#define LYNRA_PLC_MAX_RULES        64
#define LYNRA_PLC_MAX_CONDITIONS    8
#define LYNRA_PLC_MAX_ACTIONS      16

typedef enum {
    LYNRA_LOGIC_AND,
    LYNRA_LOGIC_OR,
    LYNRA_LOGIC_XOR,
    LYNRA_LOGIC_AND_EDGE,
    LYNRA_LOGIC_NAND,
    LYNRA_LOGIC_NAND_EDGE,
    LYNRA_LOGIC_NOR,
    LYNRA_LOGIC_NOT
} LynraLogicOperator;

typedef enum {
    LYNRA_TRIGGER_HIGH,
    LYNRA_TRIGGER_LOW,
    LYNRA_TRIGGER_RISING,
    LYNRA_TRIGGER_FALLING
} LynraConditionTrigger;

typedef enum {
    LYNRA_ACTION_OUTPUT,
    LYNRA_ACTION_DELAY,
    LYNRA_ACTION_SET,
    LYNRA_ACTION_RESET,
    LYNRA_ACTION_TOGGLE,
    LYNRA_ACTION_BLINK,
    LYNRA_ACTION_STAIRWAY
} LynraActionType;

typedef enum {
    LYNRA_RUN_ONCE,
    LYNRA_RUN_REPEAT
} LynraRunPolicy;

typedef enum {
    LYNRA_OUTPUT_FOLLOW,
    LYNRA_OUTPUT_LATCH
} LynraOutputBehavior;

typedef struct {
    uint8_t input_index;
    LynraConditionTrigger trigger;
} LynraCondition;

typedef struct {
    LynraActionType type;
    uint8_t output_index;
    bool output_state;
    uint32_t duration_ms;
    uint32_t off_duration_ms;
    uint32_t on_delay_ms;
    uint32_t off_delay_ms;
    uint32_t onr_delay_ms; /* Retentive ON delay; overrides on_delay_ms when nonzero */
    uint32_t blink_start_delay_ms; /* BLINK: initial pause, 0 = immediate */
    uint32_t blink_count; /* BLINK: 0 = continuous, >0 = finite pulses */
    uint32_t blink_on_min_ms; /* 0/0 means fixed duration_ms */
    uint32_t blink_on_max_ms;
    uint32_t blink_off_min_ms; /* 0/0 means fixed off_duration_ms */
    uint32_t blink_off_max_ms;
    uint32_t stair_warning_before_ms; /* 0 = no warning */
    uint32_t stair_warning_off_ms;
    bool stair_retrigger; /* true: new press restarts countdown */
} LynraAction;

typedef struct {
    uint32_t id;
    LynraLogicOperator logic_operator;
    LynraOutputBehavior output_behavior;
    LynraRunPolicy run_policy;

    uint32_t on_delay_ms;
    uint32_t off_delay_ms;

    uint8_t condition_count;
    LynraCondition conditions[LYNRA_PLC_MAX_CONDITIONS];

    uint8_t action_count;
    LynraAction actions[LYNRA_PLC_MAX_ACTIONS];
} LynraRule;

/* Opaque PLC engine instance */
typedef struct LynraPlcEngine LynraPlcEngine;

/* Lifecycle */
LynraPlcEngine* lynra_plc_create(void);
void lynra_plc_destroy(LynraPlcEngine* engine);
void lynra_plc_reset(LynraPlcEngine* engine);

/* Program */
bool lynra_plc_load_rules(
    LynraPlcEngine* engine,
    const LynraRule* rules,
    size_t rule_count
);

/* Execution */
bool lynra_plc_scan(
    LynraPlcEngine* engine,
    uint64_t now_ms,
    uint32_t input_mask
);

/* Outputs */
uint32_t lynra_plc_get_outputs(
    const LynraPlcEngine* engine
);

#ifdef __cplusplus
}
#endif

#endif
