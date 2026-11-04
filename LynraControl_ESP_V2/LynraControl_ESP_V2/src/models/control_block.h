#pragma once

#include <Arduino.h>
#include <vector>

// Logic operators
enum class LogicOperator
{
    And,
    Or,
    Xor
};

// Output behavior
enum class OutputBehavior
{
    FollowCondition,
    Latch
};

// Action types
enum class ControlActionType
{
    SetOutput,
    Delay,
    SetLatch,
    ResetLatch,
    ToggleOutput,
    BlinkOutput
};

// Rule execution policies
enum class RuleRunPolicy
{
    Once,
    Repeat
};

enum class RuleExecutionMode
{
    Continuous,
    Triggered
};

enum class RetriggerBehavior
{
    Ignore,
    Restart
};

enum class ConditionLostBehavior
{
    ContinueRunning,
    Cancel
};

// Input triggers
enum class ConditionTrigger
{
    HighLevel,
    LowLevel,
    RisingEdge,
    FallingEdge
};

// Input condition
struct InputCondition
{
    int inputIndex = 1;
    bool expectedState = true;
    ConditionTrigger trigger = ConditionTrigger::HighLevel;
};

// Output action
struct ControlAction
{
    ControlActionType type = ControlActionType::SetOutput;
    int outputIndex = 1;
    bool outputState = true;
    int durationMs = 0;
    int offDurationMs = 0;
};

// One EGER-ISE rule
struct ControlConditionGroup
{
    String id;

    LogicOperator logicOperator = LogicOperator::And;

    std::vector<InputCondition> conditions;
    std::vector<ControlAction> actions;

    OutputBehavior outputBehavior = OutputBehavior::FollowCondition;

    int onDelayMs = 0;
    int offDelayMs = 0;

    RuleRunPolicy runPolicy = RuleRunPolicy::Repeat;
    RuleExecutionMode executionMode = RuleExecutionMode::Continuous;

    RetriggerBehavior retriggerBehavior = RetriggerBehavior::Ignore;
    ConditionLostBehavior conditionLostBehavior =
        ConditionLostBehavior::ContinueRunning;
};

// Control block
struct ControlBlock
{
    String id;
    std::vector<ControlConditionGroup> groups;
};