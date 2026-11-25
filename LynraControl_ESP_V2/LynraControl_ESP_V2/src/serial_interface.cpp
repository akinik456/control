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

// Parse a one-based index without overflow or silent truncation.
bool parseActionIndex(const char *&p, uint8_t &index) {
    unsigned value = 0;
    if (*p < '0' || *p > '9') return false;
    while (*p >= '0' && *p <= '9') {
        value = value * 10 + static_cast<unsigned>(*p++ - '0');
        if (value > 256) return false;
    }
    if (value == 0) return false;
    index = static_cast<uint8_t>(value - 1);
    return true;
}

void printAction(uint8_t rule, uint8_t action, bool all) {
    DeviceApi::ActionValues result{};
    DeviceApi::readActionValues(rule, action, result);
    if (result.status == 1) {
        if (all) Serial2.printf("ERR RULE=%u ACTION=%u ACTION_UNAVAILABLE\r\n", unsigned(rule)+1, unsigned(action)+1);
        else Serial2.println("ERR ACTION_UNAVAILABLE");
        return;
    }
    if (result.status == 2) {
        if (all) Serial2.printf("ERR RULE=%u ACTION=%u NO_VALUES\r\n", unsigned(rule)+1, unsigned(action)+1);
        else Serial2.println("ERR NO_VALUES");
        return;
    }
    if (result.status != 0 || result.count > 22) {
        if (all) Serial2.printf("ERR RULE=%u ACTION=%u ACTION_RESPONSE\r\n", unsigned(rule)+1, unsigned(action)+1);
        else Serial2.println("ERR ACTION_RESPONSE");
        return;
    }
    Serial2.printf("OK RULE=%u ACTION=%u TYPE=%u COUNT=%u",
                   static_cast<unsigned>(rule) + 1,
                   static_cast<unsigned>(action) + 1,
                   static_cast<unsigned>(result.type),
                   static_cast<unsigned>(result.count));
    for (uint8_t i = 0; i < result.count; ++i) {
        Serial2.printf(" V%u=%lld", static_cast<unsigned>(result.items[i].id),
                       static_cast<long long>(result.items[i].value));
    }
    Serial2.print("\r\n");
}

void handleAction() {
    const char *p = line + 11;
    uint8_t rule, action;
    if (!parseActionIndex(p, rule) || *p != ' ') {
        Serial2.println("ERR INVALID_ACTION");
        return;
    }
    ++p;
    if (!parseActionIndex(p, action) || *p != '\0') {
        Serial2.println("ERR INVALID_ACTION");
        return;
    }
    printAction(rule, action, false);
}

uint8_t allCounts[256];
size_t allRules = 0, allRule = 0, allAction = 0;
bool allPending = false;

void handleRules(bool all) {
    size_t count = 0;
    if (!DeviceApi::readRules(allCounts, sizeof(allCounts), count)) {
        Serial2.println("ERR RULES_UNAVAILABLE");
        return;
    }
    Serial2.printf("OK RULES=%u", static_cast<unsigned>(count));
    if (!all) {
        for (size_t r = 0; r < count; ++r)
            Serial2.printf(" R%u=%u", unsigned(r)+1, unsigned(allCounts[r]));
    }
    Serial2.print("\r\n");
    if (all) { allRules = count; allRule = allAction = 0; allPending = true; }
}

void serviceAll() {
    while (allRule < allRules && allAction >= allCounts[allRule]) {
        ++allRule; allAction = 0;
    }
    if (allRule == allRules) {
        Serial2.println("END"); allPending = false; return;
    }
    printAction(static_cast<uint8_t>(allRule), static_cast<uint8_t>(allAction++), true);
}

void handleEvents() {
    const char *p = line + 11;
    uint32_t cursor = 0;
    if (*p < '0' || *p > '9') {
        Serial2.println("ERR INVALID_CURSOR");
        return;
    }
    while (*p >= '0' && *p <= '9') {
        const uint32_t digit = static_cast<uint32_t>(*p++ - '0');
        if (cursor > (UINT32_MAX - digit) / 10U) {
            Serial2.println("ERR INVALID_CURSOR");
            return;
        }
        cursor = cursor * 10U + digit;
    }
    if (*p != '\0') {
        Serial2.println("ERR INVALID_CURSOR");
        return;
    }
    DeviceApi::IoEventBatch batch{};
    if (!DeviceApi::readEvents(cursor, batch) || batch.count > 10) {
        Serial2.println("ERR EVENTS_UNAVAILABLE");
        return;
    }
    Serial2.printf("OK FIRST=%lu COUNT=%u LOST=%u\r\n",
                   static_cast<unsigned long>(batch.first),
                   static_cast<unsigned>(batch.count),
                   static_cast<unsigned>(batch.lost));
    for (uint8_t i = 0; i < batch.count; ++i) {
        const auto &e = batch.records[i];
        Serial2.printf("EVENT=%lu TIME_MS=%llu IN=0x%08lX OUT=0x%08lX\r\n",
                       static_cast<unsigned long>(batch.first + i),
                       static_cast<unsigned long long>(e.ms),
                       static_cast<unsigned long>(e.inputs),
                       static_cast<unsigned long>(e.outputs));
    }
    Serial2.printf("END NEXT=%lu\r\n",
                   static_cast<unsigned long>(batch.first + batch.count));
}

void handleCommand() {
    if (strcmp(line, "GET INFO") == 0) {
        DeviceApi::DeviceInfo info{};
        if (!DeviceApi::readInfo(info)) {
            Serial2.println("ERR INFO_UNAVAILABLE");
            return;
        }
        Serial2.printf("OK MODEL=%s SERIAL=%s FW=%s HW=%s DEVICE_ID=%02X%02X%02X%02X%02X%02X INPUTS=%u OUTPUTS=%u\r\n",
                       info.model, info.serial, info.firmware, info.hardware,
                       unsigned(info.deviceId[0]), unsigned(info.deviceId[1]),
                       unsigned(info.deviceId[2]), unsigned(info.deviceId[3]),
                       unsigned(info.deviceId[4]), unsigned(info.deviceId[5]),
                       unsigned(info.inputs), unsigned(info.outputs));
    } else if (strcmp(line, "GET STATE") == 0) {
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
    } else if (strncmp(line, "GET EVENTS ", 11) == 0) {
        handleEvents();
    } else if (strcmp(line, "GET EVENTS") == 0) {
        Serial2.println("ERR INVALID_CURSOR");
    } else if (strcmp(line, "GET RULES") == 0) {
        handleRules(false);
    } else if (strcmp(line, "GET ACTION ALL") == 0) {
        handleRules(true);
    } else if (strncmp(line, "GET ACTION ", 11) == 0) {
        handleAction();
    } else if (strcmp(line, "GET ACTION") == 0) {
        Serial2.println("ERR INVALID_ACTION");
    } else if (strcmp(line, "RUN") == 0) {
        Serial2.println(DeviceApi::run(DeviceAccess::Channel::Serial) ? "OK" : "ERR RUN_REJECTED");
    } else if (strcmp(line, "STOP") == 0) {
        Serial2.println(DeviceApi::stop(DeviceAccess::Channel::Serial) ? "OK" : "ERR STOP_REJECTED");
    } else if (strcmp(line, "MANUAL ON") == 0 || strcmp(line, "MANUAL OFF") == 0) {
        const bool enabled = strcmp(line, "MANUAL ON") == 0;
        Serial2.println(DeviceApi::setManualMode(DeviceAccess::Channel::Serial, enabled) ? "OK" : "ERR MANUAL_REJECTED");
    } else if (strncmp(line, "SET I", 5) == 0) {
        if (strlen(line) != 8 || line[5] < '1' || line[5] > '4' || line[6] != ' ' || (line[7] != '0' && line[7] != '1')) {
            Serial2.println("ERR INVALID_INPUT");
            return;
        }
        Serial2.println(DeviceApi::setInput(DeviceAccess::Channel::Serial, static_cast<uint8_t>(line[5] - '1'), line[7] == '1') ? "OK" : "ERR INPUT_REJECTED");
    } else {
        Serial2.println("ERR UNKNOWN_COMMAND");
    }
}
}

void serialInterfaceInit() {
    Serial2.begin(115200, SERIAL_8N1, 27, 23);
}

void serialInterfaceLoop() {
    if (allPending) { serviceAll(); return; }
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
            if (allPending) break;
        } else if (!invalid) {
            if (c < 32 || c > 126 || length >= kLineSize - 1) invalid = true;
            else line[length++] = static_cast<char>(c);
        }
    }
}
