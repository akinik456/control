#include <esp_ota_ops.h>
#include <Arduino.h>
#include <ArduinoJson.h>
#include <stdlib.h>
#include "plc_manager.h"
#include "ble_interface.h"
#include "serial_interface.h"
#include "plc_program_store.h"
#include "models/control_program.h"
#include "wifi_interface.h"
#include "device_identity.h"
#include "device_license.h"

// Temporary heap buffer: avoid both static DRAM overflow and task stack overflow.
namespace
{

  void restoreProgramFromFlash()
  {
    Serial.println("PLC RESTORE: START");
    if (!PlcProgramStore::begin())
    {
      Serial.println("PLC RESTORE: LITTLEFS MOUNT FAILED - NO FORMAT");
      return;
    }
    if (!PlcProgramStore::hasProgram())
    {
      Serial.println("PLC RESTORE: NO VALID FLASH RECORD");
      return;
    }

    uint8_t *savedProgram = static_cast<uint8_t *>(malloc(PlcProgramStore::kMaxProgramSize));
    if (!savedProgram)
    {
      Serial.println("PLC RESTORE: BUFFER ALLOCATION FAILED - STOP");
      return;
    }
    size_t length = 0;
    if (!PlcProgramStore::load(savedProgram, PlcProgramStore::kMaxProgramSize, length))
    {
      free(savedProgram);
      Serial.println("PLC RESTORE: FLASH READ/CRC FAILED");
      return;
    }

    JsonDocument doc;
    const DeserializationError err = deserializeJson(doc, savedProgram, length);
    free(savedProgram);
    if (err)
    {
      // The previously committed smoke-test payload is intentionally not JSON.
      Serial.println("PLC RESTORE: RECORD IS NOT PLC JSON - STOP");
      return;
    }

    ControlProgram program;
    if (!program.fromJson(doc.as<JsonVariantConst>()))
    {
      Serial.println("PLC RESTORE: PROGRAM PARSE FAILED - STOP");
      return;
    }
    String validationError;
    if (!program.validate(validationError))
    {
      Serial.printf("PLC RESTORE: VALIDATION FAILED: %s\n", validationError.c_str());
      return;
    }
    if (!plcLoadProgram(program))
    {
      Serial.println("PLC RESTORE: ENGINE LOAD FAILED - STOP");
      return;
    }
    if (plcRun())
    {
      Serial.println("PLC RESTORE: PROGRAM LOADED - STATE RUN");
    }
    else
    {
      plcStop();
      Serial.println("PLC RESTORE: RUN FAILED - STATE STOP");
    }
  }
} // namespace

void setup()
{
  Serial.begin(115200);
	if (!DeviceLicense_Init())
	{
			Serial.println("LICENSE INIT FAILED");
	}
	if (!DeviceIdentity_Init())
	{
			Serial.println("IDENTITY INIT FAILED");
	}
  const esp_partition_t *running = esp_ota_get_running_partition();
  const esp_partition_t *next = esp_ota_get_next_update_partition(NULL);

  Serial.printf("OTA RUNNING: %s\n", running->label);
  Serial.printf("OTA TARGET: %s\n", next->label);
  Serial.printf("OTA CAPACITY: %u bytes\n", (unsigned)next->size);

  esp_ota_img_states_t state;
  esp_err_t err = esp_ota_get_state_partition(running, &state);

  Serial.printf("OTA STATE RESULT: %s\n", esp_err_to_name(err));

  if (err == ESP_OK)
  {
    Serial.printf("OTA STATE: %d\n", (int)state);
  }

#ifdef CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE
  Serial.println("OTA ROLLBACK CONFIG: ENABLED");
#else
  Serial.println("OTA ROLLBACK CONFIG: DISABLED");
#endif
  if (!plcInit())
  {
    Serial.println("PLC INIT FAILED");
    while (true)
      delay(1000);
  }
  restoreProgramFromFlash();
  if (!bleInit())
  {
    Serial.println("BLE INIT FAILED");
    while (true)
      delay(1000);
  }
  serialInterfaceInit();
  if (!wifiInterfaceInit())
  {
    Serial.println("WIFI TASK INIT FAILED");
  }
}

void loop()
{
  plcLoop();
  bleLoop();
  serialInterfaceLoop();
  delay(1);
}
