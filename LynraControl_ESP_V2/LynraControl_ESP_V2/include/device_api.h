#pragma once
#include "device_data.h"
#include "device_access.h"
#include <stdint.h>

namespace DeviceApi {
struct DeviceInfo {
    const char *model;
    const char *serial;
    const char *firmware;
    const char *hardware;
    uint8_t deviceId[6];
    uint8_t inputs;
    uint8_t outputs;
};
bool readInfo(DeviceInfo &info);
bool readPairingCode(char *dest, size_t capacity);
bool readWifiLicense();
uint8_t readWifiState();
bool activateWifiLicense(
    DeviceAccess::Channel channel,
    const char *code);
bool saveWifiConfig(
    DeviceAccess::Channel channel,
    const char *ssid,
    const char *password);
struct IoSnapshot {
    uint32_t inputs;
    uint32_t outputs;
    uint64_t timeMs;
    bool manual;
};
struct LiveSnapshot {
    uint8_t state;
    uint32_t inputs;
    uint32_t outputs;
    uint64_t uptimeMs;
    bool manual;
};

bool readLiveSnapshot(LiveSnapshot &snapshot);
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
// Program transfers share one buffer; read snapshots belong to the requesting channel.
bool programActive();
bool beginProgram(DeviceAccess::Channel channel, uint32_t size, uint32_t crc);
bool appendProgram(DeviceAccess::Channel channel, uint32_t seq, const uint8_t* data, size_t size);
bool finishProgram(DeviceAccess::Channel channel);
void abortProgram(DeviceAccess::Channel channel);
void serviceProgramTimeout();
void clearProgramRead(DeviceAccess::Channel channel);
bool programInfo(DeviceAccess::Channel channel, uint32_t &size, uint32_t &crc);
size_t programChunk(DeviceAccess::Channel channel, uint32_t offset, uint8_t* dest, size_t capacity);
}
