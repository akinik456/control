#include "control_program.h"

bool ControlProgram::fromJson(JsonVariantConst json)
{
    // Flutter ControlProgram.fromJson():
    // Yalnızca formatVersion 1 ve 2 kabul edilir.

    if (!json.is<JsonObjectConst>())
    {
        return false;
    }

    int version = json["formatVersion"] | 0;

    if (version != 1 && version != 2)
    {
        return false;
    }

    if (!json["name"].is<const char *>())
    {
        return false;
    }

    String parsedName = json["name"].as<String>();
    std::vector<ControlBlock> parsedBlocks;

    if (version == 2)
    {
        JsonArrayConst blocks = json["controlBlocks"].as<JsonArrayConst>();

        if (blocks.isNull())
        {
            return false;
        }

        for (JsonObjectConst blockJson : blocks)
        {
            if (!blockJson["id"].is<const char *>())
            {
                return false;
            }

            ControlBlock block;
            block.id = blockJson["id"].as<String>();
            JsonArrayConst groups = blockJson["groups"].as<JsonArrayConst>();

            if (groups.isNull())
            {
                return false;
            }

            for (JsonObjectConst groupJson : groups)
            {
                if (!groupJson["id"].is<const char *>())
                {
                    return false;
                }

                ControlConditionGroup group;
                group.id = groupJson["id"].as<String>();
                auto parseEnum = [](JsonVariantConst value,
                                    const char *const *names,
                                    int count,
                                    int &result) -> bool
                {
                    if (!value.is<const char *>())
                        return false;

                    const char *text = value.as<const char *>();

                    for (int i = 0; i < count; ++i)
                    {
                        if (strcmp(text, names[i]) == 0)
                        {
                            result = i;
                            return true;
                        }
                    }
                    return false;
                };

                int parsed = 0;

                const char *logicNames[] = {"and", "or", "xor"};
                if (!parseEnum(groupJson["logicOperator"], logicNames, 3, parsed))
                    return false;
                group.logicOperator = static_cast<LogicOperator>(parsed);

                const char *behaviorNames[] = {"followCondition", "latch"};
                if (!parseEnum(groupJson["outputBehavior"], behaviorNames, 2, parsed))
                    return false;
                group.outputBehavior = static_cast<OutputBehavior>(parsed);

                const char *policyNames[] = {"once", "repeat"};
                if (!parseEnum(groupJson["runPolicy"], policyNames, 2, parsed))
                    return false;
                group.runPolicy = static_cast<RuleRunPolicy>(parsed);

                const char *modeNames[] = {"continuous", "triggered"};
                if (!parseEnum(groupJson["executionMode"], modeNames, 2, parsed))
                    return false;
                group.executionMode = static_cast<RuleExecutionMode>(parsed);

                const char *retriggerNames[] = {"ignore", "restart"};
                if (!parseEnum(groupJson["retriggerBehavior"], retriggerNames, 2, parsed))
                    return false;
                group.retriggerBehavior = static_cast<RetriggerBehavior>(parsed);

                const char *lostNames[] = {"continueRunning", "cancel"};
                if (!parseEnum(groupJson["conditionLostBehavior"], lostNames, 2, parsed))
                    return false;
                group.conditionLostBehavior = static_cast<ConditionLostBehavior>(parsed);

                group.onDelayMs = groupJson["onDelayMs"] | 0;
                group.offDelayMs = groupJson["offDelayMs"] | 0;

                JsonArrayConst conditions =
                    groupJson["conditions"].as<JsonArrayConst>();

                if (conditions.isNull())
                {
                    return false;
                }

                const char *triggerNames[] = {
                    "highLevel",
                    "lowLevel",
                    "risingEdge",
                    "fallingEdge"};

                for (JsonObjectConst conditionJson : conditions)
                {
                    if (!conditionJson["inputIndex"].is<int>())
                    {
                        return false;
                    }

                    InputCondition condition;
                    condition.inputIndex = conditionJson["inputIndex"].as<int>();

                    if (condition.inputIndex < 1)
                    {
                        return false;
                    }

                    condition.expectedState =
                        conditionJson["expectedState"] | true;

                    if (conditionJson["trigger"].isNull())
                    {
                        condition.trigger = condition.expectedState
                                                ? ConditionTrigger::HighLevel
                                                : ConditionTrigger::LowLevel;
                    }
                    else
                    {
                        int triggerIndex = 0;

                        if (!parseEnum(
                                conditionJson["trigger"],
                                triggerNames,
                                4,
                                triggerIndex))
                        {
                            return false;
                        }

                        condition.trigger =
                            static_cast<ConditionTrigger>(triggerIndex);
                    }

                    group.conditions.push_back(condition);
                }

                JsonArrayConst actions = groupJson["actions"].as<JsonArrayConst>();

                if (actions.isNull())
                {
                    return false;
                }

                const char *actionNames[] = {
                    "setOutput",
                    "delay",
                    "setLatch",
                    "resetLatch",
                    "toggleOutput",
                    "blinkOutput"};

                for (JsonObjectConst actionJson : actions)
                {
                    int actionType = 0;

                    if (!parseEnum(
                            actionJson["type"],
                            actionNames,
                            6,
                            actionType))
                    {
                        return false;
                    }

                    ControlAction action;
                    action.type = static_cast<ControlActionType>(actionType);

                    if (action.type == ControlActionType::Delay)
                    {
                        action.durationMs = actionJson["durationMs"] | 1000;
                    }
                    else
                    {
                        action.outputIndex = actionJson["outputIndex"] | 1;

                        if (action.outputIndex < 1)
                        {
                            return false;
                        }

                        action.outputState = actionJson["outputState"] | true;

                        if (action.type == ControlActionType::BlinkOutput)
                        {
                            action.durationMs = actionJson["durationMs"] | 3000;
                            action.offDurationMs = actionJson["offDurationMs"] | 3000;
                        }
                    }

                    group.actions.push_back(action);
                }

                block.groups.push_back(group);
            }

            parsedBlocks.push_back(block);
        }
    }
    // Bu aşamada yalnızca üst seviye alanları doğruluyoruz.
    name = std::move(parsedName);
    controlBlocks = std::move(parsedBlocks);
    return true;
}

bool ControlProgram::validate(String &error) const
{
    error = "";

    std::vector<String> ruleIds;

    for (const auto &block : controlBlocks)
    {
        for (const auto &rule : block.groups)
        {
            if (rule.id.isEmpty())
            {
                error = "Empty rule ID";
                return false;
            }

            for (const auto &id : ruleIds)
            {
                if (id == rule.id)
                {
                    error = "Duplicate rule ID: " + rule.id;
                    return false;
                }
            }

            ruleIds.push_back(rule.id);

            if (rule.conditions.empty() || rule.actions.empty())
            {
                error = "Empty conditions/actions: " + rule.id;
                return false;
            }

            if (rule.onDelayMs < 0 || rule.offDelayMs < 0)
            {
                error = "Negative TON/TOF: " + rule.id;
                return false;
            }

            for (const auto &condition : rule.conditions)
            {
                if (condition.inputIndex < 1 ||
                    condition.inputIndex > 4)
                {
                    error = "Invalid input: " + rule.id;
                    return false;
                }
            }

            for (const auto &action : rule.actions)
            {
                if (action.type != ControlActionType::Delay &&
                    (action.outputIndex < 1 ||
                     action.outputIndex > 4))
                {
                    error = "Invalid output: " + rule.id;
                    return false;
                }

                if (action.type == ControlActionType::Delay &&
                    action.durationMs < 0)
                {
                    error = "Invalid DELAY: " + rule.id;
                    return false;
                }

                if (action.type == ControlActionType::BlinkOutput &&
                    (action.durationMs <= 0 ||
                     action.offDurationMs <= 0))
                {
                    error = "Invalid BLINK: " + rule.id;
                    return false;
                }
            }
        }
    }

    return true;
}
