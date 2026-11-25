#pragma once
#include <stdint.h>

namespace DeviceConfig {
constexpr char kModel[] = "LC-44";
constexpr char kFirmwareVersion[] = "0.1.0";
constexpr char kHardwareVersion[] = "PROTO";
constexpr char kSerialNumber[] = "UNASSIGNED";
// Current prototype I/O capabilities; must match PLC manager hardware.
constexpr uint8_t kInputCount = 4;
constexpr uint8_t kOutputCount = 4;
}
