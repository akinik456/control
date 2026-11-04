#include <Arduino.h>
#include "plc_manager.h"
#include "ble_interface.h"

void setup()
{
  Serial.begin(115200);

  if (!plcInit())
  {
    Serial.println("PLC INIT FAILED");
    while (true)
      delay(1000);
  }
  if (!bleInit())
  {
    Serial.println("BLE INIT FAILED");
    while (true)
      delay(1000);
  }
}

void loop()
{
  plcLoop();
  bleLoop();
  delay(1);
}