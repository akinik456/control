#pragma once
#include <Arduino.h>
namespace DeviceAccess {
enum class Channel : uint8_t { None, Wifi, Ble, Serial };
enum class Lock : uint8_t { None, Program, Firmware, Restart };
bool init();
bool take(TickType_t timeout);
void give();
// Caller must hold the shared recursive mutex.
void setLock(Lock lock, Channel owner);
Lock currentLock();
Channel lockOwner();
bool canControl(Channel channel);
bool canManual(Channel channel, bool enable);
void setManualOwner(Channel channel);
Channel manualOwner();
void refreshManual();
bool manualExpired();
}
