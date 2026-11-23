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

                const char *logicNames[] = {"and", "or", "xor", "nand", "nor", "not"};
                if (!groupJson["logicOperator"].isNull() && !parseEnum(groupJson["logicOperator"], logicNames, 6, parsed))
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

                auto readConditions = [&](JsonArrayConst conditions, std::vector<InputCondition>& dest)->bool {
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

                    dest.push_back(condition);
                }

                    return true;
                };
                auto readOps = [&](JsonVariantConst value, std::vector<LogicOperator>& dest)->bool {
                    for (JsonVariantConst v : value.as<JsonArrayConst>()) { int n; if (!parseEnum(v, logicNames, 6, n)) return false; dest.push_back(static_cast<LogicOperator>(n)); } return true;
                };
                if (!readConditions(groupJson["conditions"].as<JsonArrayConst>(), group.conditions) || !readOps(groupJson["conditionOperators"], group.conditionOperators) || !readOps(groupJson["groupOperators"], group.groupOperators)) return false;
                if (!groupJson["groupsOperator"].isNull()) { if (!parseEnum(groupJson["groupsOperator"], logicNames, 6, parsed)) return false; group.groupsOperator = static_cast<LogicOperator>(parsed); }
                for (JsonObjectConst j : groupJson["conditionGroups"].as<JsonArrayConst>()) {
                    ConditionSubgroup sub;
                    if (!j["logicOperator"].isNull()) { if (!parseEnum(j["logicOperator"], logicNames, 6, parsed)) return false; sub.logicOperator = static_cast<LogicOperator>(parsed); }
                    if (!readConditions(j["conditions"].as<JsonArrayConst>(), sub.conditions) || !readOps(j["conditionOperators"], sub.conditionOperators)) return false;
                    group.conditionGroups.push_back(sub);
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
                    "blinkOutput", "onDelay", "offDelay", "onOffDelay", "wipingRelay", "edgeWipingRelay", "asynchronousPulse", "randomGenerator", "stairwayTimer", "multipleFunctionTimer", "stopwatchTimer", "upDownCounter", "hoursCounter", "thresholdTrigger"};

                for (JsonObjectConst actionJson : actions)
                {
                    int actionType = 0;

                    if (!parseEnum(
                            actionJson["type"],
                            actionNames,
                            19,
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

                    if (!actionJson["timerTMs"].isNull()) { if (!actionJson["timerTMs"].is<int64_t>()) return false; action.timerTMs = actionJson["timerTMs"].as<int64_t>(); }
                    if (!actionJson["timerTHMs"].isNull()) { if (!actionJson["timerTHMs"].is<int64_t>()) return false; action.timerTHMs = actionJson["timerTHMs"].as<int64_t>(); }
                    if (!actionJson["timerTLMs"].isNull()) { if (!actionJson["timerTLMs"].is<int64_t>()) return false; action.timerTLMs = actionJson["timerTLMs"].as<int64_t>(); }
                    if (!actionJson["timerWarningBeforeMs"].isNull()) { if (!actionJson["timerWarningBeforeMs"].is<int64_t>()) return false; action.timerWarningBeforeMs = actionJson["timerWarningBeforeMs"].as<int64_t>(); }
                    if (!actionJson["timerWarningOffMs"].isNull()) { if (!actionJson["timerWarningOffMs"].is<int64_t>()) return false; action.timerWarningOffMs = actionJson["timerWarningOffMs"].as<int64_t>(); }
                    if (!actionJson["timerN"].isNull()) { if (!actionJson["timerN"].is<int64_t>()) return false; action.timerN = actionJson["timerN"].as<int64_t>(); }
                    if (!actionJson["resetInputIndex"].isNull()) { if (!actionJson["resetInputIndex"].is<int64_t>()) return false; action.resetInputIndex = actionJson["resetInputIndex"].as<int64_t>(); }
                    if (!actionJson["counterInputIndex"].isNull()) { if (!actionJson["counterInputIndex"].is<int64_t>()) return false; action.counterInputIndex = actionJson["counterInputIndex"].as<int64_t>(); }
                    if (!actionJson["directionInputIndex"].isNull()) { if (!actionJson["directionInputIndex"].is<int64_t>()) return false; action.directionInputIndex = actionJson["directionInputIndex"].as<int64_t>(); }
                    if (!actionJson["counterStartValue"].isNull()) { if (!actionJson["counterStartValue"].is<int64_t>()) return false; action.counterStartValue = actionJson["counterStartValue"].as<int64_t>(); }
                    if (!actionJson["counterOn"].isNull()) { if (!actionJson["counterOn"].is<int64_t>()) return false; action.counterOn = actionJson["counterOn"].as<int64_t>(); }
                    if (!actionJson["counterOff"].isNull()) { if (!actionJson["counterOff"].is<int64_t>()) return false; action.counterOff = actionJson["counterOff"].as<int64_t>(); }
                    if (!actionJson["hoursEnableInputIndex"].isNull()) { if (!actionJson["hoursEnableInputIndex"].is<int64_t>()) return false; action.hoursEnableInputIndex = actionJson["hoursEnableInputIndex"].as<int64_t>(); }
                    if (!actionJson["hoursResetAllInputIndex"].isNull()) { if (!actionJson["hoursResetAllInputIndex"].is<int64_t>()) return false; action.hoursResetAllInputIndex = actionJson["hoursResetAllInputIndex"].as<int64_t>(); }
                    if (!actionJson["hoursTargetMs"].isNull()) { if (!actionJson["hoursTargetMs"].is<int64_t>()) return false; action.hoursTargetMs = actionJson["hoursTargetMs"].as<int64_t>(); }
                    if (!actionJson["thresholdInputIndex"].isNull()) { if (!actionJson["thresholdInputIndex"].is<int64_t>()) return false; action.thresholdInputIndex = actionJson["thresholdInputIndex"].as<int64_t>(); }
                    if (!actionJson["thresholdGateMs"].isNull()) { if (!actionJson["thresholdGateMs"].is<int64_t>()) return false; action.thresholdGateMs = actionJson["thresholdGateMs"].as<int64_t>(); }
                    if (!actionJson["thresholdOn"].isNull()) { if (!actionJson["thresholdOn"].is<int64_t>()) return false; action.thresholdOn = actionJson["thresholdOn"].as<int64_t>(); }
                    if (!actionJson["thresholdOff"].isNull()) { if (!actionJson["thresholdOff"].is<int64_t>()) return false; action.thresholdOff = actionJson["thresholdOff"].as<int64_t>(); }
                    action.timerTHRandom = actionJson["timerTHRandom"] | false;
                    action.timerTLRandom = actionJson["timerTLRandom"] | false;
                    action.timerRepeat = actionJson["timerRepeat"] | false;
                    action.timerRetrigger = actionJson["timerRetrigger"] | false;
                    action.virtualStart = actionJson["virtualStart"] | false;
                    action.stopwatchTimeBase = actionJson["stopwatchTimeBase"] | "seconds";
                    if (action.type == ControlActionType::UpDownCounter || action.type == ControlActionType::HoursCounter || action.type == ControlActionType::ThresholdTrigger) action.resetInputIndex = actionJson["resetInputIndex"] | 3;
                    if (action.type == ControlActionType::OnDelay || action.type == ControlActionType::OffDelay) { action.timerTHMs = action.type == ControlActionType::OnDelay ? action.timerTMs : 0; action.timerTLMs = action.type == ControlActionType::OffDelay ? action.timerTMs : 0; action.timerTMs = 0; action.type = ControlActionType::OnOffDelay; }
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

            if ((rule.conditions.empty() && rule.conditionGroups.empty()) || rule.actions.empty())
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

            for (const auto &sub : rule.conditionGroups) { if (sub.conditions.empty()) { error = "Empty subgroup"; return false; } for (const auto &c : sub.conditions) if (c.inputIndex < 1 || c.inputIndex > 4) { error = "Invalid subgroup input"; return false; } }
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
