
#include "plc_adapter.h"

bool plcConvertProgram(
    const ControlProgram &program,
    std::vector<LynraRule> &rules,
    String &error)
{
    rules.clear();
    error = "";

    if (!program.validate(error))
        return false;

    for (const auto &block : program.controlBlocks)
    {
        for (const auto &group : block.groups)
        {
            if (rules.size() >= LYNRA_PLC_MAX_RULES)
            {
                error = "Too many PLC rules";
                return false;
            }

            if (group.conditions.size() > LYNRA_PLC_MAX_CONDITIONS ||
                group.actions.size() > LYNRA_PLC_MAX_ACTIONS)
            {
                error = "Rule capacity exceeded: " + group.id;
                return false;
            }

            // Unsupported behavior must not be silently changed.
            if (group.executionMode != RuleExecutionMode::Continuous ||
                group.retriggerBehavior != RetriggerBehavior::Ignore ||
                group.conditionLostBehavior != ConditionLostBehavior::ContinueRunning)
            {
                error = "Unsupported execution behavior: " + group.id;
                return false;
            }

            LynraRule rule = {};
            rule.id = static_cast<uint32_t>(rules.size() + 1);

            switch (group.logicOperator)
            {
            case LogicOperator::And:
                rule.logic_operator = LYNRA_LOGIC_AND;
                break;
            case LogicOperator::Or:
                rule.logic_operator = LYNRA_LOGIC_OR;
                break;
            case LogicOperator::Xor:
                rule.logic_operator = LYNRA_LOGIC_XOR;
                break;
            default:
                error = "Unsupported logic operator";
                return false;
            }

            rule.output_behavior =
                group.outputBehavior == OutputBehavior::Latch
                    ? LYNRA_OUTPUT_LATCH
                    : LYNRA_OUTPUT_FOLLOW;

            rule.run_policy =
                group.runPolicy == RuleRunPolicy::Once
                    ? LYNRA_RUN_ONCE
                    : LYNRA_RUN_REPEAT;

            if (group.onDelayMs < 0 || group.offDelayMs < 0)
            {
                error = "Invalid timing";
                return false;
            }

            rule.on_delay_ms = group.onDelayMs;
            rule.off_delay_ms = group.offDelayMs;

            rule.condition_count = group.conditions.size();

            for (size_t i = 0; i < group.conditions.size(); ++i)
            {
                const auto &c = group.conditions[i];

                if (c.inputIndex < 1 || c.inputIndex > LYNRA_PLC_MAX_INPUTS)
                {
                    error = "Invalid input index";
                    return false;
                }

                rule.conditions[i].input_index = c.inputIndex;

                switch (c.trigger)
                {
                case ConditionTrigger::HighLevel:
                    rule.conditions[i].trigger = LYNRA_TRIGGER_HIGH;
                    break;
                case ConditionTrigger::LowLevel:
                    rule.conditions[i].trigger = LYNRA_TRIGGER_LOW;
                    break;
                case ConditionTrigger::RisingEdge:
                    rule.conditions[i].trigger = LYNRA_TRIGGER_RISING;
                    break;
                case ConditionTrigger::FallingEdge:
                    rule.conditions[i].trigger = LYNRA_TRIGGER_FALLING;
                    break;
                default:
                    error = "Unsupported trigger";
                    return false;
                }
            }

            rule.action_count = group.actions.size();

            for (size_t i = 0; i < group.actions.size(); ++i)
            {
                const auto &a = group.actions[i];
                LynraAction &dest = rule.actions[i];

                switch (a.type)
                {
                case ControlActionType::SetOutput:
                    dest.type = LYNRA_ACTION_OUTPUT;
                    break;
                case ControlActionType::Delay:
                    dest.type = LYNRA_ACTION_DELAY;
                    break;
                case ControlActionType::SetLatch:
                    dest.type = LYNRA_ACTION_SET;
                    break;
                case ControlActionType::ResetLatch:
                    dest.type = LYNRA_ACTION_RESET;
                    break;
                case ControlActionType::ToggleOutput:
                    dest.type = LYNRA_ACTION_TOGGLE;
                    break;
                case ControlActionType::BlinkOutput:
                    dest.type = LYNRA_ACTION_BLINK;
                    break;
                default:
                    error = "Unsupported action";
                    return false;
                }

                if (a.durationMs < 0 || a.offDurationMs < 0)
                {
                    error = "Invalid action timing";
                    return false;
                }

                if (a.type != ControlActionType::Delay &&
                    (a.outputIndex < 1 || a.outputIndex > LYNRA_PLC_MAX_OUTPUTS))
                {
                    error = "Invalid output index";
                    return false;
                }

                dest.output_index = a.type == ControlActionType::Delay
                                        ? 0
                                        : a.outputIndex;
                dest.output_state = a.outputState;
                dest.duration_ms = a.durationMs;
                dest.off_duration_ms = a.offDurationMs;
            }

            rules.push_back(rule);
        }
    }

    return true;
}
