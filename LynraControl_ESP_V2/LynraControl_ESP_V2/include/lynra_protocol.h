
#pragma once

#include <stddef.h>
#include <stdint.h>

namespace LynraProtocol
{

    constexpr uint8_t VERSION = 1;
    constexpr uint8_t SOF1 = 0x4C; // L
    constexpr uint8_t SOF2 = 0x43; // C

    constexpr size_t HEADER_SIZE = 23;
    constexpr size_t CRC_SIZE = 4;
    constexpr size_t MIN_FRAME_SIZE = HEADER_SIZE + CRC_SIZE;

    uint32_t calculateCRC32(const uint8_t *data, size_t length);

    bool verifyFrame(const uint8_t *data, size_t length);

}
