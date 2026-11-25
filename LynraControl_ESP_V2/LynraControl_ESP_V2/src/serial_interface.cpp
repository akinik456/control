#include <Arduino.h>
#include <string.h>
#include "serial_interface.h"
#include "device_api.h"

namespace {
constexpr size_t kLineSize = 64;
constexpr size_t kRxBudget = 64;
char line[kLineSize];
size_t length = 0;
bool invalid = false;

void handleCommand() {
    if (strcmp(line, "GET STATE") == 0) {
        const uint8_t state = DeviceApi::getState();
        switch (state) {
            case 0: Serial2.println("OK STATE=STOP"); break;
            case 1: Serial2.println("OK STATE=PROGRAMMING"); break;
            case 2: Serial2.println("OK STATE=RUN"); break;
            default: Serial2.println("ERR STATE"); break;
        }
    } else if (strcmp(line, "GET IO") == 0) {
        DeviceApi::IoSnapshot io{};
        if (!DeviceApi::readIo(io)) {
            Serial2.println("ERR IO_UNAVAILABLE");
            return;
        }
        Serial2.printf("OK IN=0x%08lX OUT=0x%08lX MANUAL=%u TIME_MS=%llu\r\n",
                       static_cast<unsigned long>(io.inputs),
                       static_cast<unsigned long>(io.outputs),
                       static_cast<unsigned>(io.manual),
                       static_cast<unsigned long long>(io.timeMs));
    } else {
        Serial2.println("ERR UNKNOWN_COMMAND");
    }
}
}

void serialInterfaceInit() {
    Serial2.begin(115200, SERIAL_8N1, 27, 23);
}

void serialInterfaceLoop() {
    for (size_t i = 0; i < kRxBudget && Serial2.available() > 0; ++i) {
        const int c = Serial2.read();
        if (c < 0) break;
        if (c == '\r' || c == '\n') {
            if (invalid) Serial2.println("ERR INVALID_LINE");
            else if (length != 0) {
                line[length] = '\0';
                handleCommand();
            }
            length = 0;
            invalid = false;
        } else if (!invalid) {
            if (c < 32 || c > 126 || length >= kLineSize - 1) invalid = true;
            else line[length++] = static_cast<char>(c);
        }
    }
}
