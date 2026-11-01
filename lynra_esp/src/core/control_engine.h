#pragma once

#include <Arduino.h>
#include <map>
#include <vector>
#include <set>

#include "../models/control_program.h"

class ControlEngine
{
public:
    explicit ControlEngine(const ControlProgram &program);

    // PLC motorunu başlangıç durumuna döndürür.
    void reset();

    // Bir PLC tarama döngüsü çalıştırır.
    // Giriş numaraları 1'den başlar.
    // nowMs monoton artan zaman değeridir.
    void scan(uint32_t nowMs, const std::map<int, bool> &inputs);

    // İstenen çıkışın mevcut durumunu döndürür.
    bool output(int index) const;

private:
    const ControlProgram &program_;

    // Çıkışların çalışma zamanı durumları.
    std::map<int, bool> outputs_;

    std::map<int, bool> previousInputs_;

    bool matches(
        const ControlConditionGroup &rule,
        const std::map<int, bool> &inputs) const;

    struct RuleState
    {
        bool previousMatch = false;
        bool completedOnce = false;

        int64_t rawOnSinceMs = -1;
        int64_t rawOffSinceMs = -1;
        bool timedMatch = false;

        bool running = false;
        size_t actionIndex = 0;
        int64_t waitUntilMs = -1;

        std::map<int, uint32_t> outputVersions;

        int64_t blinkStartedMs = -1;
        int64_t blinkActivationSerial = -1;
    };

    // Her kuralın ID'sine göre bağımsız çalışma durumu.
    std::map<String, RuleState> ruleStates_;
    void startRule(RuleState &state, uint32_t nowMs);
    std::map<int, uint32_t> outputVersions_;
    std::map<int, int64_t> blinkSuppressedThrough_;
    int64_t blinkActivationSerial_ = 0;

    void writeOutput(int index, bool value, bool fromBlink = false);
    std::set<int> resetPriority_;

    void advanceRule(
        const ControlConditionGroup &rule,
        RuleState &state,
        uint32_t nowMs);

    struct BlinkCandidate
    {
        String ruleId;
        int64_t serial = -1;
        ControlAction action;
    };

    std::map<int, String> blinkOwners_;
    std::map<int, int64_t> blinkOwnerStartedMs_;
};