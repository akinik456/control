#pragma once

#include <Arduino.h>
#include <vector>

// Logic operators
enum class LogicOperator
{
    And,
    Or,
    Xor, Nand, Nor, Not
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
    BlinkOutput, OnDelay, OffDelay, OnOffDelay, WipingRelay, EdgeWipingRelay, AsynchronousPulse, RandomGenerator, StairwayTimer, MultipleFunctionTimer, StopwatchTimer, UpDownCounter, HoursCounter, ThresholdTrigger
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
    int64_t timerTMs = 0;
    int64_t timerTHMs = 0;
    int64_t timerTLMs = 0;
    int64_t timerWarningBeforeMs = 0;
    int64_t timerWarningOffMs = 0;
    int64_t timerN = 1;
    int64_t resetInputIndex = 2;
    int64_t counterInputIndex = 1;
    int64_t directionInputIndex = 2;
    int64_t counterStartValue = 0;
    int64_t counterOn = 10;
    int64_t counterOff = 5;
    int64_t hoursEnableInputIndex = 1;
    int64_t hoursResetAllInputIndex = 3;
    int64_t hoursTargetMs = 3600000;
    int64_t thresholdInputIndex = 1;
    int64_t thresholdGateMs = 1000;
    int64_t thresholdOn = 10;
    int64_t thresholdOff = 5;
    bool timerTHRandom = false;
    bool timerTLRandom = false;
    bool timerRepeat = false;
    bool timerRetrigger = false;
    bool virtualStart = false;
    String stopwatchTimeBase = "seconds";
};

struct ConditionSubgroup {
 LogicOperator logicOperator = LogicOperator::And;
 std::vector<InputCondition> conditions;
 std::vector<LogicOperator> conditionOperators;
};
// One EGER-ISE rule
struct ControlConditionGroup
{
    String id;

    LogicOperator logicOperator = LogicOperator::And;

    std::vector<InputCondition> conditions;
    std::vector<ControlAction> actions;
    std::vector<ConditionSubgroup> conditionGroups;
    std::vector<LogicOperator> conditionOperators, groupOperators;
    LogicOperator groupsOperator = LogicOperator::Or;

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