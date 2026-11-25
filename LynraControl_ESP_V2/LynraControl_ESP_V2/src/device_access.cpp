#include "device_access.h"
namespace DeviceAccess {
static SemaphoreHandle_t mutex = nullptr;
static Lock operation = Lock::None;
static Channel operationOwner = Channel::None;
static Channel manual = Channel::None;
static uint32_t lastManual = 0;
bool init() { if (!mutex) mutex = xSemaphoreCreateRecursiveMutex(); return mutex != nullptr; }
bool take(TickType_t timeout) { return mutex && xSemaphoreTakeRecursive(mutex, timeout)==pdTRUE; }
void give() { xSemaphoreGiveRecursive(mutex); }
void setLock(Lock lock, Channel owner) { operation=lock; operationOwner=lock==Lock::None ? Channel::None : owner; }
bool canControl(Channel channel) { return channel!=Channel::None && (operation==Lock::None || (operation==Lock::Program && operationOwner==channel)); }
bool canManual(Channel channel, bool enable) {
    if (channel==Channel::None || operation!=Lock::None) return false;
    if (!enable) return manual==Channel::None || manual==channel || channel>manual;
    return manual==Channel::None || channel>=manual;
}
void setManualOwner(Channel channel) { manual=channel; refreshManual(); }
Channel manualOwner() { return manual; }
void refreshManual() { lastManual=millis(); }
bool manualExpired() { return (manual==Channel::Serial || manual==Channel::Wifi) && uint32_t(millis()-lastManual)>=30000; }
}
