#pragma once
#include <stdint.h>

namespace DeviceData {
struct IoEvent { uint64_t ms; uint32_t inputs; uint32_t outputs; };
struct IoEventBatch {
    uint32_t first;
    uint8_t count;
    bool lost;
    IoEvent records[10];
};
struct ActionValue { uint8_t id; int64_t value; };
struct ActionValues {
    uint8_t status; // 0 OK, 1 unavailable, 2 no values
    uint8_t type;
    uint8_t count;
    ActionValue items[22];
};
}
