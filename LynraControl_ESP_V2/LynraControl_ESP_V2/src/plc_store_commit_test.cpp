#include "plc_store_stage_test.h"
#include "plc_program_store.h"
#include <Arduino.h>
#include <string.h>

namespace {
constexpr uint8_t kSample[] = "LYNRA_COMMIT_TEST_V1";
uint8_t readBuffer[sizeof(kSample)];
}

void plcStoreStageTestRun() {
  Serial.println("PLC STORE COMMIT TEST: START");
  if (!PlcProgramStore::begin()) {
    Serial.println("PLC STORE COMMIT TEST: MOUNT FAILED - NO FORMAT");
    return;
  }

  if (PlcProgramStore::hasProgram()) {
    size_t length = 0;
    const bool loaded = PlcProgramStore::load(readBuffer, sizeof(readBuffer), length);
    if (loaded && length == sizeof(kSample) - 1 &&
        memcmp(readBuffer, kSample, length) == 0) {
      Serial.println("PLC STORE COMMIT TEST: REBOOT PERSISTENCE PASS");
    } else {
      Serial.println("PLC STORE COMMIT TEST: EXISTING ACTIVE PROGRAM - NOT MODIFIED");
    }
    return;
  }

  if (!PlcProgramStore::prepare(kSample, sizeof(kSample) - 1)) {
    Serial.println("PLC STORE COMMIT TEST: PREPARE FAILED");
    return;
  }
  if (PlcProgramStore::hasProgram()) {
    Serial.println("PLC STORE COMMIT TEST: ACTIVE BEFORE COMMIT - FAIL");
    return;
  }
  if (!PlcProgramStore::commit()) {
    Serial.println("PLC STORE COMMIT TEST: COMMIT FAILED");
    return;
  }
  size_t length = 0;
  if (PlcProgramStore::load(readBuffer, sizeof(readBuffer), length) &&
      length == sizeof(kSample) - 1 &&
      memcmp(readBuffer, kSample, length) == 0) {
    Serial.println("PLC STORE COMMIT TEST: COMMIT/READ PASS - RESET ESP32");
  } else {
    Serial.println("PLC STORE COMMIT TEST: READBACK FAILED");
  }
}
