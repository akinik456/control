#include "device_api.h"
#include "plc_manager.h"
#include <esp_timer.h>

namespace DeviceApi {
uint8_t getState() {
    return plcGetStatus();
}
bool readIo(IoSnapshot &snapshot) {
    IoSnapshot result{};
    if (!plcReadIo(result.inputs, result.outputs, result.manual)) return false;
    result.timeMs = static_cast<uint64_t>(esp_timer_get_time()) / 1000;
    snapshot = result;
    return true;
}
using DeviceAccess::Channel;
struct Guard {
    bool held = DeviceAccess::take(pdMS_TO_TICKS(1000));
    ~Guard() { if (held) DeviceAccess::give(); }
};
bool run(Channel channel) { Guard g; return g.held && DeviceAccess::canControl(channel) && plcRun(); }
bool stop(Channel channel) { Guard g; if (!g.held || !DeviceAccess::canControl(channel)) return false; plcStop(); return plcGetStatus()==0; }
bool setManualMode(Channel channel, bool enabled) {
    Guard g;
    if (!g.held || !DeviceAccess::canManual(channel, enabled)) return false;
    if (!plcSetManualMode(enabled)) return false;
    DeviceAccess::setManualOwner(enabled ? channel : Channel::None);
    return true;
}
bool setInput(Channel channel, uint8_t index, bool on) {
    Guard g;
    if (!g.held || !DeviceAccess::canManual(channel,true) || DeviceAccess::manualOwner()!=channel) return false;
    if (!plcSetManualInput(index,on)) return false;
    DeviceAccess::refreshManual(); return true;
}
void releaseManual(Channel channel) {
    Guard g;
    if (g.held && DeviceAccess::manualOwner()==channel && plcSetManualMode(false)) DeviceAccess::setManualOwner(Channel::None);
}
void serviceManualTimeout() {
    Guard g;
    if (g.held && DeviceAccess::manualExpired() && plcSetManualMode(false)) DeviceAccess::setManualOwner(Channel::None);
}
bool readEvents(uint32_t cursor, IoEventBatch &batch) { return plcReadEvents(cursor, batch); }
void readActionValues(uint8_t rule, uint8_t action, ActionValues &result) { plcReadActionValues(rule, action, result); }
bool readRules(uint8_t *counts, size_t capacity, size_t &count) { return plcReadRules(counts, capacity, count); }
}
