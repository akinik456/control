#include "control_program.h"
#include "../core/control_engine.h"

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

void testControlProgramJson()
{
    const char *testJson = R"json(
{
  "formatVersion": 2,
  "name": "Yeni Program",
  "steps": [],
  "controlBlocks": [
    {
      "id": "main",
      "groups": [
        {
          "id": "rule_1",
          "logicOperator": "and",
          "conditions": [
            {
              "inputIndex": 1,
              "expectedState": true,
              "trigger": "highLevel"
            }
          ],
          "actions": [
            {
              "type": "setOutput",
              "outputIndex": 1,
              "outputState": true
            }
          ],
          "outputBehavior": "followCondition",
          "onDelayMs": 0,
          "offDelayMs": 0,
          "runPolicy": "repeat",
          "executionMode": "continuous",
          "retriggerBehavior": "ignore",
          "conditionLostBehavior": "continueRunning"
        }
      ]
    }
  ]
}
)json";

    JsonDocument doc;
    DeserializationError error = deserializeJson(doc, testJson);

    ControlProgram program;

    if (error || !program.fromJson(doc.as<JsonVariantConst>()))
    {
        Serial.println("JSON TEST FAILED");
        return;
    }

    Serial.printf("Program: %s\n", program.name.c_str());
    Serial.printf("Blocks: %u\n", (unsigned)program.controlBlocks.size());

    if (!program.controlBlocks.empty())
    {
        Serial.printf("Rules: %u\n",
                      (unsigned)program.controlBlocks[0].groups.size());
        const auto &rule = program.controlBlocks[0].groups[0];

        Serial.printf("Conditions: %u\n",
                      (unsigned)rule.conditions.size());

        Serial.printf("Actions: %u\n",
                      (unsigned)rule.actions.size());

        if (!rule.conditions.empty())
        {
            Serial.printf("Input: I%d, Expected: %d\n",
                          rule.conditions[0].inputIndex,
                          rule.conditions[0].expectedState);
        }

        if (!rule.actions.empty())
        {
            Serial.printf("Output: Q%d, State: %d\n",
                          rule.actions[0].outputIndex,
                          rule.actions[0].outputState);
        }
    }
    ControlEngine engine(program);

    std::map<int, bool> inputs;

    inputs[1] = false;
    engine.scan(0, inputs);
    Serial.printf("I1=0 Q1=%d\n", engine.output(1));

    inputs[1] = true;
    engine.scan(10, inputs);
    Serial.printf("I1=1 Q1=%d\n", engine.output(1));

    inputs[1] = false;
    engine.scan(20, inputs);
    Serial.printf("I1=0 Q1=%d\n", engine.output(1));

    // TON TEST: 1000 ms
    ControlProgram tonProgram = program;
    tonProgram.controlBlocks[0].groups[0].onDelayMs = 1000;

    ControlEngine tonEngine(tonProgram);
    std::map<int, bool> tonInputs;

    tonInputs[1] = false;
    tonEngine.scan(0, tonInputs);

    tonInputs[1] = true;

    tonEngine.scan(100, tonInputs);
    Serial.printf("TON t=100 Q1=%d\n", tonEngine.output(1));

    tonEngine.scan(1099, tonInputs);
    Serial.printf("TON t=1099 Q1=%d\n", tonEngine.output(1));

    tonEngine.scan(1100, tonInputs);
    Serial.printf("TON t=1100 Q1=%d\n", tonEngine.output(1));

    tonInputs[1] = false;
    tonEngine.scan(1200, tonInputs);
    Serial.printf("TON t=1200 Q1=%d\n", tonEngine.output(1));

    // TOF TEST: 1000 ms
    ControlProgram tofProgram = program;
    tofProgram.controlBlocks[0].groups[0].offDelayMs = 1000;

    ControlEngine tofEngine(tofProgram);
    std::map<int, bool> tofInputs;

    tofInputs[1] = true;
    tofEngine.scan(0, tofInputs);
    Serial.printf("TOF t=0 Q1=%d\n", tofEngine.output(1));

    tofInputs[1] = false;
    tofEngine.scan(100, tofInputs);
    Serial.printf("TOF t=100 Q1=%d\n", tofEngine.output(1));

    tofEngine.scan(1099, tofInputs);
    Serial.printf("TOF t=1099 Q1=%d\n", tofEngine.output(1));

    tofEngine.scan(1100, tofInputs);
    Serial.printf("TOF t=1100 Q1=%d\n", tofEngine.output(1));

    // DELAY TEST: 1000 ms bekle, sonra Q1 ON
    ControlProgram delayProgram = program;
    auto &delayRule = delayProgram.controlBlocks[0].groups[0];

    delayRule.actions.clear();

    ControlAction waitAction;
    waitAction.type = ControlActionType::Delay;
    waitAction.durationMs = 1000;
    delayRule.actions.push_back(waitAction);

    ControlAction onAction;
    onAction.type = ControlActionType::SetOutput;
    onAction.outputIndex = 1;
    onAction.outputState = true;
    delayRule.actions.push_back(onAction);

    ControlEngine delayEngine(delayProgram);
    std::map<int, bool> delayInputs;
    delayInputs[1] = true;

    delayEngine.scan(0, delayInputs);
    Serial.printf("DELAY t=0 Q1=%d\n", delayEngine.output(1));

    delayEngine.scan(999, delayInputs);
    Serial.printf("DELAY t=999 Q1=%d\n", delayEngine.output(1));

    delayEngine.scan(1000, delayInputs);
    Serial.printf("DELAY t=1000 Q1=%d\n", delayEngine.output(1));

    // LATCH TEST
    ControlProgram latchProgram = program;
    auto &latchRule = latchProgram.controlBlocks[0].groups[0];

    latchRule.actions.clear();
    latchRule.outputBehavior = OutputBehavior::Latch;

    ControlAction latchAction;
    latchAction.type = ControlActionType::SetLatch;
    latchAction.outputIndex = 1;
    latchRule.actions.push_back(latchAction);

    ControlEngine latchEngine(latchProgram);
    std::map<int, bool> latchInputs;

    latchInputs[1] = false;
    latchEngine.scan(0, latchInputs);
    Serial.printf("LATCH I1=0 Q1=%d\n", latchEngine.output(1));

    latchInputs[1] = true;
    latchEngine.scan(10, latchInputs);
    Serial.printf("LATCH I1=1 Q1=%d\n", latchEngine.output(1));

    latchInputs[1] = false;
    latchEngine.scan(20, latchInputs);
    Serial.printf("LATCH I1=0 Q1=%d\n", latchEngine.output(1));

    // RESET LATCH TEST
    ControlProgram resetProgram = latchProgram;

    ControlConditionGroup resetRule;
    resetRule.id = "rule_reset";

    InputCondition resetCondition;
    resetCondition.inputIndex = 2;
    resetCondition.trigger = ConditionTrigger::HighLevel;
    resetRule.conditions.push_back(resetCondition);

    ControlAction resetAction;
    resetAction.type = ControlActionType::ResetLatch;
    resetAction.outputIndex = 1;
    resetRule.actions.push_back(resetAction);

    resetProgram.controlBlocks[0].groups.push_back(resetRule);

    ControlEngine resetEngine(resetProgram);
    std::map<int, bool> resetInputs;

    resetInputs[1] = true;
    resetInputs[2] = false;
    resetEngine.scan(0, resetInputs);
    Serial.printf("RESET I1=1 I2=0 Q1=%d\n", resetEngine.output(1));

    resetInputs[1] = false;
    resetEngine.scan(10, resetInputs);
    Serial.printf("RESET I1=0 I2=0 Q1=%d\n", resetEngine.output(1));

    resetInputs[2] = true;
    resetEngine.scan(20, resetInputs);
    Serial.printf("RESET I1=0 I2=1 Q1=%d\n", resetEngine.output(1));
    // BLINK TEST: 300 ms ON, 200 ms OFF
    ControlProgram blinkProgram = program;
    auto &blinkRule = blinkProgram.controlBlocks[0].groups[0];

    blinkRule.actions.clear();

    ControlAction blinkAction;
    blinkAction.type = ControlActionType::BlinkOutput;
    blinkAction.outputIndex = 1;
    blinkAction.durationMs = 300;
    blinkAction.offDurationMs = 200;
    blinkRule.actions.push_back(blinkAction);

    ControlEngine blinkEngine(blinkProgram);
    std::map<int, bool> blinkInputs;
    blinkInputs[1] = true;

    for (uint32_t t : {0U, 299U, 300U, 499U, 500U, 800U})
    {
        blinkEngine.scan(t, blinkInputs);
        Serial.printf("BLINK t=%u Q1=%d\n", t, blinkEngine.output(1));
    }

    blinkInputs[1] = false;
    blinkEngine.scan(900, blinkInputs);
    Serial.printf("BLINK t=900 Q1=%d\n", blinkEngine.output(1));
    // PROGRAM VALIDATION NEGATIVE TESTS
    auto testInvalid = [](const char *name, ControlProgram p)
    {
        String error;
        bool accepted = p.validate(error);

        Serial.printf("VALIDATION TEST %-18s : %s (%s)\n",
                      name,
                      accepted ? "FAIL" : "PASS",
                      error.c_str());
    };

    ControlProgram invalid = program;

    invalid.controlBlocks[0].groups[0].conditions[0].inputIndex = 5;
    testInvalid("Input I5", invalid);

    invalid = program;
    invalid.controlBlocks[0].groups[0].actions[0].outputIndex = 5;
    testInvalid("Output Q5", invalid);

    invalid = program;
    invalid.controlBlocks[0].groups[0].onDelayMs = -100;
    testInvalid("Negative TON", invalid);

    invalid = program;
    invalid.controlBlocks[0].groups[0].offDelayMs = -100;
    testInvalid("Negative TOF", invalid);

    invalid = program;
    invalid.controlBlocks[0].groups[0].actions[0].type =
        ControlActionType::Delay;
    invalid.controlBlocks[0].groups[0].actions[0].durationMs = -100;
    testInvalid("Negative DELAY", invalid);

    invalid = program;
    invalid.controlBlocks[0].groups[0].actions[0].type =
        ControlActionType::BlinkOutput;
    invalid.controlBlocks[0].groups[0].actions[0].durationMs = 0;
    invalid.controlBlocks[0].groups[0].actions[0].offDurationMs = 200;
    testInvalid("Invalid BLINK", invalid);

    invalid = program;
    invalid.controlBlocks[0].groups.push_back(
        invalid.controlBlocks[0].groups[0]);
    testInvalid("Duplicate rule ID", invalid);
}
