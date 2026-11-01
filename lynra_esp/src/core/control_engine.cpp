#include "control_engine.h"
#include <algorithm>
#include <set>

ControlEngine::ControlEngine(const ControlProgram &program)
    : program_(program)
{
    reset();
}

void ControlEngine::reset()
{
    outputs_.clear();
    previousInputs_.clear();
    ruleStates_.clear();
    outputVersions_.clear();
    blinkSuppressedThrough_.clear();
    blinkActivationSerial_ = 0;
    resetPriority_.clear();
    blinkOwners_.clear();
    blinkOwnerStartedMs_.clear();
}

bool ControlEngine::output(int index) const
{
    auto it = outputs_.find(index);
    return it != outputs_.end() ? it->second : false;
}

void ControlEngine::scan(
    uint32_t nowMs,
    const std::map<int, bool> &inputs)
{
    resetPriority_.clear();

    for (const auto &block : program_.controlBlocks)
    {
        for (const auto &rule : block.groups)
        {
            RuleState &state = ruleStates_[rule.id];

            const bool edgeRule = std::any_of(
                rule.conditions.begin(),
                rule.conditions.end(),
                [](const InputCondition &condition)
                {
                    return condition.trigger == ConditionTrigger::RisingEdge ||
                           condition.trigger == ConditionTrigger::FallingEdge;
                });

            const bool rawMatch = matches(rule, inputs);

            // TON / TOF
            if (rawMatch)
            {
                state.rawOffSinceMs = -1;
                if (state.rawOnSinceMs < 0)
                {
                    state.rawOnSinceMs = nowMs;
                }
                if (static_cast<int64_t>(nowMs) - state.rawOnSinceMs >=
                    rule.onDelayMs)
                {
                    state.timedMatch = true;
                }
            }
            else
            {
                state.rawOnSinceMs = -1;
                if (state.timedMatch)
                {
                    if (state.rawOffSinceMs < 0)
                    {
                        state.rawOffSinceMs = nowMs;
                    }
                    if (static_cast<int64_t>(nowMs) - state.rawOffSinceMs >=
                        rule.offDelayMs)
                    {
                        state.timedMatch = false;
                        state.rawOffSinceMs = -1;
                    }
                }
            }
            // Flutter: continuous + edge olmayan + yalnızca BLINK işlemleri.
            const bool blinkOnly =
                rule.executionMode == RuleExecutionMode::Continuous &&
                !edgeRule &&
                !rule.actions.empty() &&
                std::all_of(
                    rule.actions.begin(),
                    rule.actions.end(),
                    [](const ControlAction &action)
                    {
                        return action.type == ControlActionType::BlinkOutput;
                    });

            const bool matched = state.timedMatch;
            const bool rising = matched && !state.previousMatch;

            if (blinkOnly)
            {
                if (matched && state.blinkActivationSerial < 0)
                {
                    state.blinkActivationSerial = ++blinkActivationSerial_;
                }
                else if (!matched)
                {
                    state.blinkActivationSerial = -1;
                }
            }
            else if (edgeRule)
            {
                if (rising && !state.running)
                {
                    startRule(state, nowMs);
                }
                if (state.running)
                {
                    advanceRule(rule, state, nowMs);
                }
            }
            else
            {
                if (!matched)
                {
                    state.completedOnce = false;
                    state.running = false;
                    state.actionIndex = 0;
                    state.waitUntilMs = -1;

                    if (rule.outputBehavior == OutputBehavior::FollowCondition)
                    {
                        for (const auto &action : rule.actions)
                        {
                            if (action.type == ControlActionType::SetOutput)
                            {
                                writeOutput(action.outputIndex, !action.outputState);
                            }
                        }
                    }
                }
                else
                {
                    const bool latchOnly =
                        !rule.actions.empty() &&
                        std::all_of(
                            rule.actions.begin(),
                            rule.actions.end(),
                            [](const ControlAction &action)
                            {
                                return action.type == ControlActionType::SetLatch ||
                                       action.type == ControlActionType::ResetLatch;
                            });

                    const bool canStart =
                        rule.runPolicy == RuleRunPolicy::Once
                            ? !state.completedOnce
                            : (!latchOnly || rising);

                    if (!state.running && canStart)
                    {
                        startRule(state, nowMs);
                    }

                    if (state.running)
                    {
                        advanceRule(rule, state, nowMs);

                        if (!state.running &&
                            rule.runPolicy == RuleRunPolicy::Once)
                        {
                            state.completedOnce = true;
                        }
                    }
                }
            }

            // Sürekli RESET koşulu, kural sırasından bağımsız önceliklidir.
            if (matched && !edgeRule)
            {
                const bool hasDelay = std::any_of(
                    rule.actions.begin(),
                    rule.actions.end(),
                    [](const ControlAction &action)
                    {
                        return action.type == ControlActionType::Delay;
                    });

                if (!hasDelay)
                {
                    for (const auto &action : rule.actions)
                    {
                        if (action.type == ControlActionType::ResetLatch)
                        {
                            resetPriority_.insert(action.outputIndex);
                        }
                    }
                }
            }

            state.previousMatch = matched;
        }
    }

    // RESET önceliğini bütün kurallar değerlendirildikten sonra uygula.
    for (int index : resetPriority_)
    {
        outputs_[index] = false;
        blinkSuppressedThrough_[index] = blinkActivationSerial_;
    }

    // Her çıkış için en son aktive edilen BLINK kuralını seç.
    std::map<int, BlinkCandidate> candidates;

    for (const auto &block : program_.controlBlocks)
    {
        for (const auto &rule : block.groups)
        {
            const RuleState &state = ruleStates_.at(rule.id);
            const int64_t serial = state.blinkActivationSerial;

            if (serial < 0 ||
                rule.executionMode != RuleExecutionMode::Continuous ||
                rule.actions.empty())
            {
                continue;
            }

            const bool hasEdge = std::any_of(
                rule.conditions.begin(),
                rule.conditions.end(),
                [](const InputCondition &condition)
                {
                    return condition.trigger == ConditionTrigger::RisingEdge ||
                           condition.trigger == ConditionTrigger::FallingEdge;
                });

            const bool allBlink = std::all_of(
                rule.actions.begin(),
                rule.actions.end(),
                [](const ControlAction &action)
                {
                    return action.type == ControlActionType::BlinkOutput;
                });

            if (hasEdge || !allBlink)
                continue;

            for (const auto &action : rule.actions)
            {
                const int index = action.outputIndex;

                auto suppressed = blinkSuppressedThrough_.find(index);
                if (suppressed != blinkSuppressedThrough_.end() &&
                    serial <= suppressed->second)
                {
                    continue;
                }

                auto it = candidates.find(index);
                if (it == candidates.end() || serial > it->second.serial)
                {
                    BlinkCandidate candidate;
                    candidate.ruleId = rule.id;
                    candidate.serial = serial;
                    candidate.action = action;

                    candidates[index] = candidate;
                }
            }
        }
    }

    // Önceki sahipleri ve yeni adayları birlikte değerlendir.
    std::set<int> affected;

    for (const auto &entry : blinkOwners_)
    {
        affected.insert(entry.first);
    }

    for (const auto &entry : candidates)
    {
        affected.insert(entry.first);
    }

    for (int index : affected)
    {
        auto candidateIt = candidates.find(index);
        auto ownerIt = blinkOwners_.find(index);

        if (candidateIt == candidates.end())
        {
            if (ownerIt != blinkOwners_.end())
            {
                blinkOwners_.erase(index);
                blinkOwnerStartedMs_.erase(index);
                writeOutput(index, false, true);
            }
            continue;
        }

        const BlinkCandidate &candidate = candidateIt->second;

        if (ownerIt == blinkOwners_.end() ||
            ownerIt->second != candidate.ruleId)
        {
            blinkOwners_[index] = candidate.ruleId;
            blinkOwnerStartedMs_[index] = nowMs;
        }

        const int64_t period =
            static_cast<int64_t>(candidate.action.durationMs) +
            candidate.action.offDurationMs;

        // Geçersiz BLINK süresini çalıştırma.
        if (candidate.action.durationMs <= 0 ||
            candidate.action.offDurationMs <= 0 ||
            period <= 0)
        {
            continue;
        }

        const int64_t phase =
            (static_cast<int64_t>(nowMs) -
             blinkOwnerStartedMs_[index]) %
            period;

        const bool desired = phase < candidate.action.durationMs;

        if (output(index) != desired)
        {
            writeOutput(index, desired, true);
        }
    }

    previousInputs_ = inputs;
}

bool ControlEngine::matches(
    const ControlConditionGroup &rule,
    const std::map<int, bool> &inputs) const
{
    if (rule.conditions.empty())
        return false;

    int trueCount = 0;

    for (const auto &condition : rule.conditions)
    {
        auto currentIt = inputs.find(condition.inputIndex);
        bool current = currentIt != inputs.end() && currentIt->second;

        auto previousIt = previousInputs_.find(condition.inputIndex);
        bool previous = previousIt != previousInputs_.end() && previousIt->second;

        bool value = false;

        switch (condition.trigger)
        {
        case ConditionTrigger::HighLevel:
            value = current;
            break;
        case ConditionTrigger::LowLevel:
            value = !current;
            break;
        case ConditionTrigger::RisingEdge:
            value = !previous && current;
            break;
        case ConditionTrigger::FallingEdge:
            value = previous && !current;
            break;
        }

        if (value)
            ++trueCount;
    }

    const int count = static_cast<int>(rule.conditions.size());

    switch (rule.logicOperator)
    {
    case LogicOperator::And:
        return trueCount == count;
    case LogicOperator::Or:
        return trueCount > 0;
    case LogicOperator::Xor:
        return (trueCount % 2) == 1;
    }

    return false;
}
void ControlEngine::startRule(
    RuleState &state,
    uint32_t nowMs)
{
    (void)nowMs;

    state.running = true;
    state.actionIndex = 0;
    state.waitUntilMs = -1;

    // Başlangıç anındaki çıkış sürümlerini kaydet.
    state.outputVersions = outputVersions_;
}
void ControlEngine::writeOutput(
    int index,
    bool value,
    bool fromBlink)
{
    // Açık bir çıkış komutu mevcut BLINK aktivasyonlarını bastırır.
    if (!fromBlink)
    {
        blinkSuppressedThrough_[index] = blinkActivationSerial_;
    }

    outputs_[index] = value;

    // Çıkışa verilen her komut sürüm numarasını artırır.
    outputVersions_[index]++;
}

void ControlEngine::advanceRule(
    const ControlConditionGroup &rule,
    RuleState &state,
    uint32_t nowMs)
{
    while (state.running && state.actionIndex < rule.actions.size())
    {
        const ControlAction &action = rule.actions[state.actionIndex];

        // Başka bir komut bu çıkışa müdahale etmişse
        // bekleyen işlemi geçersiz kıl.
        if (action.type != ControlActionType::Delay &&
            outputVersions_[action.outputIndex] !=
                state.outputVersions[action.outputIndex])
        {
            state.actionIndex++;
            continue;
        }

        // BLINK ayrı mekanizma tarafından yönetilecek.
        if (action.type == ControlActionType::BlinkOutput)
        {
            state.actionIndex++;
            continue;
        }

        switch (action.type)
        {
        case ControlActionType::SetOutput:
            writeOutput(action.outputIndex, action.outputState);
            break;

        case ControlActionType::ToggleOutput:
            writeOutput(action.outputIndex, !output(action.outputIndex));
            break;

        case ControlActionType::SetLatch:
            writeOutput(action.outputIndex, true);
            break;

        case ControlActionType::ResetLatch:
            writeOutput(action.outputIndex, false);
            resetPriority_.insert(action.outputIndex);
            break;

        case ControlActionType::Delay:
            if (state.waitUntilMs < 0)
            {
                state.waitUntilMs =
                    static_cast<int64_t>(nowMs) + action.durationMs;
            }

            if (nowMs < state.waitUntilMs)
            {
                return;
            }

            state.waitUntilMs = -1;
            state.actionIndex++;
            continue;

        case ControlActionType::BlinkOutput:
            break;
        }

        // Bu işlemden sonraki çıkış sürümünü kaydet.
        state.outputVersions[action.outputIndex] =
            outputVersions_[action.outputIndex];

        state.actionIndex++;
    }

    if (state.actionIndex >= rule.actions.size())
    {
        state.running = false;
    }
}
