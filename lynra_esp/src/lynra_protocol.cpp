
#include "lynra_protocol.h"

namespace LynraProtocol
{

    uint32_t calculateCRC32(const uint8_t *data, size_t length)
    {
        uint32_t crc = 0xFFFFFFFF;

        for (size_t i = 0; i < length; ++i)
        {
            crc ^= data[i];

            for (int bit = 0; bit < 8; ++bit)
            {
                if (crc & 1)
                {
                    crc = (crc >> 1) ^ 0xEDB88320;
                }
                else
                {
                    crc >>= 1;
                }
            }
        }

        return crc ^ 0xFFFFFFFF;
    }

    bool verifyFrame(const uint8_t *data, size_t length)
    {
        if (data == nullptr || length < MIN_FRAME_SIZE)
        {
            return false;
        }

        if (data[0] != SOF1 || data[1] != SOF2)
        {
            return false;
        }

        if (data[2] != VERSION || data[3] != HEADER_SIZE)
        {
            return false;
        }

        // LEN: offset 21, little-endian
        const uint16_t payloadLength =
            static_cast<uint16_t>(data[21]) |
            (static_cast<uint16_t>(data[22]) << 8);

        if (length != HEADER_SIZE + payloadLength + CRC_SIZE)
        {
            return false;
        }

        const size_t crcOffset = length - CRC_SIZE;

        const uint32_t receivedCRC =
            static_cast<uint32_t>(data[crcOffset]) |
            (static_cast<uint32_t>(data[crcOffset + 1]) << 8) |
            (static_cast<uint32_t>(data[crcOffset + 2]) << 16) |
            (static_cast<uint32_t>(data[crcOffset + 3]) << 24);

        // CRC covers everything after SOF, excluding the CRC itself.
        const uint32_t calculatedCRC =
            calculateCRC32(data + 2, length - 2 - CRC_SIZE);

        return receivedCRC == calculatedCRC;
    }

}
