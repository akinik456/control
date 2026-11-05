#include <Arduino.h>
#include <ArduinoJson.h>
#include <stdlib.h>
#include "plc_manager.h"
#include "ble_interface.h"
#include "plc_program_store.h"
#include "models/control_program.h"

// Temporary heap buffer: avoid both static DRAM overflow and task stack overflow.
namespace {

void restoreProgramFromFlash() {
  Serial.println("PLC RESTORE: START");
  if (!PlcProgramStore::begin()) {
    Serial.println("PLC RESTORE: LITTLEFS MOUNT FAILED - NO FORMAT");
    return;
  }
  if (!PlcProgramStore::hasProgram()) {
    Serial.println("PLC RESTORE: NO VALID FLASH RECORD");
    return;
  }

  uint8_t* savedProgram = static_cast<uint8_t*>(malloc(PlcProgramStore::kMaxProgramSize));
  if (!savedProgram) {
    Serial.println("PLC RESTORE: BUFFER ALLOCATION FAILED - STOP");
    return;
  }
  size_t length = 0;
  if (!PlcProgramStore::load(savedProgram, PlcProgramStore::kMaxProgramSize, length)) {
    free(savedProgram);
    Serial.println("PLC RESTORE: FLASH READ/CRC FAILED");
    return;
  }

  JsonDocument doc;
  const DeserializationError err = deserializeJson(doc, savedProgram, length);
  free(savedProgram);
  if (err) {
    // The previously committed smoke-test payload is intentionally not JSON.
    Serial.println("PLC RESTORE: RECORD IS NOT PLC JSON - STOP");
    return;
  }

  ControlProgram program;
  if (!program.fromJson(doc.as<JsonVariantConst>())) {
    Serial.println("PLC RESTORE: PROGRAM PARSE FAILED - STOP");
    return;
  }
  String validationError;
  if (!program.validate(validationError)) {
    Serial.printf("PLC RESTORE: VALIDATION FAILED: %s\n", validationError.c_str());
    return;
  }
  if (!plcLoadProgram(program)) {
    Serial.println("PLC RESTORE: ENGINE LOAD FAILED - STOP");
    return;
  }
  plcStop();
  Serial.println("PLC RESTORE: PROGRAM LOADED - STATE STOP");
}
} // namespace

void setup() {
  Serial.begin(115200);
  if (!plcInit()) {
    Serial.println("PLC INIT FAILED");
    while (true) delay(1000);
  }
  restoreProgramFromFlash();
  if (!bleInit()) {
    Serial.println("BLE INIT FAILED");
    while (true) delay(1000);
  }
}

void loop() {
  plcLoop();
  bleLoop();
  delay(1);
}
