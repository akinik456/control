#pragma once
#include "device_data.h"
#include "device_access.h"
#include <stdint.h>

namespace DeviceApi {
struct IoSnapshot {
    uint32_t inputs;
    uint32_t outputs;
    uint64_t timeMs;
    bool manual;
};
// Existing state codes: 0 STOP, 1 PROGRAMMING, 2 RUN.
uint8_t getState();
bool readIo(IoSnapshot &snapshot);
bool run(DeviceAccess::Channel channel);
bool stop(DeviceAccess::Channel channel);
bool setManualMode(DeviceAccess::Channel channel, bool enabled);
void releaseManual(DeviceAccess::Channel channel);
void serviceManualTimeout();
bool setInput(DeviceAccess::Channel channel, uint8_t index, bool on);
using DeviceData::IoEvent;
using DeviceData::IoEventBatch;
using DeviceData::ActionValues;
bool readEvents(uint32_t cursor, IoEventBatch &batch);
void readActionValues(uint8_t rule, uint8_t action, ActionValues &result);
bool readRules(uint8_t *counts, size_t capacity, size_t &count);
}
