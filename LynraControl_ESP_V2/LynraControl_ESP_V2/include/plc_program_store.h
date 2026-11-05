#pragma once
#include <stddef.h>
#include <stdint.h>

// LittleFS must already be mounted. No automatic formatting.
namespace PlcProgramStore {
constexpr size_t kMaxProgramSize = 32768;
bool begin();
bool prepare(const uint8_t* data, size_t length);
bool commit();
bool load(uint8_t* destination, size_t capacity, size_t& length);
bool hasProgram();
}
