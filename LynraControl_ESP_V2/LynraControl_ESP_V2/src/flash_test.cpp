#include "flash_test.h"

#include <Arduino.h>
#include <LittleFS.h>
#include <string.h>

namespace {
constexpr char kPath[] = "/lynra_flash_smoke.bin";
constexpr uint8_t kPayload[] = "LYNRA_FLASH_TEST_V1";

uint32_t crc32(const uint8_t* data, size_t length) {
  uint32_t crc = 0xFFFFFFFFUL;
  for (size_t i = 0; i < length; ++i) {
    crc ^= data[i];
    for (uint8_t bit = 0; bit < 8; ++bit)
      crc = (crc & 1U) ? (crc >> 1) ^ 0xEDB88320UL : (crc >> 1);
  }
  return crc ^ 0xFFFFFFFFUL;
}

bool readAndVerify() {
  File file = LittleFS.open(kPath, "r");
  if (!file) return false;
  constexpr size_t len = sizeof(kPayload) - 1;
  if (file.size() != len) { file.close(); return false; }
  uint8_t buffer[len];
  const size_t count = file.read(buffer, len);
  file.close();
  if (count != len) return false;
  const uint32_t expected = crc32(kPayload, len);
  const uint32_t actual = crc32(buffer, len);
  Serial.printf("FLASH TEST: CRC expected=%08lX actual=%08lX\n",
                (unsigned long)expected, (unsigned long)actual);
  return actual == expected && memcmp(buffer, kPayload, len) == 0;
}
} // namespace

void flashTestRun() {
  Serial.println("FLASH TEST: START");
  // false: NEVER format an existing filesystem on mount failure.
  if (!LittleFS.begin(false)) {
    Serial.println("FLASH TEST: MOUNT FAILED - NO FORMAT PERFORMED");
    return;
  }

  if (LittleFS.exists(kPath)) {
    Serial.println(readAndVerify()
      ? "FLASH TEST: REBOOT PERSISTENCE PASS"
      : "FLASH TEST: EXISTING TEST FILE INVALID - NOT OVERWRITTEN");
    return;
  }

  File file = LittleFS.open(kPath, "w");
  if (!file) {
    Serial.println("FLASH TEST: FILE OPEN FAILED");
    return;
  }
  constexpr size_t len = sizeof(kPayload) - 1;
  const size_t written = file.write(kPayload, len);
  file.flush();
  file.close();
  if (written != len) {
    Serial.println("FLASH TEST: WRITE FAILED");
    return;
  }
  Serial.println(readAndVerify()
    ? "FLASH TEST: WRITE/READ/CRC PASS - RESET ESP32 TO TEST PERSISTENCE"
    : "FLASH TEST: VERIFY FAILED");
}
