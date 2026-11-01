

#include <Arduino.h>
#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "lynra_protocol.h"

#define SERVICE_UUID "8d21a100-64c2-4c3a-9d1e-123456789abc"
#define WRITE_UUID "8d21a101-64c2-4c3a-9d1e-123456789abc"
#define NOTIFY_UUID "8d21a102-64c2-4c3a-9d1e-123456789abc"

BLECharacteristic *tx = nullptr;

constexpr size_t MAX_PROGRAM_SIZE = 32768;

uint8_t programBuffer[MAX_PROGRAM_SIZE];
uint32_t expectedProgramSize = 0;
uint32_t expectedProgramCRC = 0;
uint32_t receivedProgramSize = 0;
bool programTransferActive = false;
bool plcReady = false;
bool virtualInputs[4] = {false, false, false, false};
bool virtualOutputs[4] = {false, false, false, false};

uint32_t lastSeq = 0;
bool hasLastSeq = false;

struct PlcRule
{
  uint8_t inputIndex;
  bool expectedState;
  uint8_t outputIndex;
  bool outputState;
};

constexpr uint8_t MAX_PLC_RULES = 16;

PlcRule activeRules[MAX_PLC_RULES];

uint8_t activeRuleCount = 0;

class ReceiveCallbacks : public BLECharacteristicCallbacks
{
  void onWrite(BLECharacteristic *characteristic) override
  {

    std::string value = characteristic->getValue();

    const uint8_t *data =
        reinterpret_cast<const uint8_t *>(value.data());

    const size_t length = value.size();

    if (value == "HELLO")
    {
      Serial.println("BLE RX: HELLO");

      if (tx != nullptr)
      {
        tx->setValue("HELLO_ACK");
        tx->notify();
      }
      return;
    }

    if (LynraProtocol::verifyFrame(data, length))
    {
      Serial.printf("BLE FRAME VALID (%u bytes)\n",
                    (unsigned)length);

      const uint8_t type = data[16];

      const uint32_t seq =
          (uint32_t)data[17] |
          ((uint32_t)data[18] << 8) |
          ((uint32_t)data[19] << 16) |
          ((uint32_t)data[20] << 24);

      if (hasLastSeq && seq == lastSeq)
      {
        Serial.printf("DUPLICATE SEQ=%lu\n",
                      (unsigned long)seq);
      }
      else
      {
        lastSeq = seq;
        hasLastSeq = true;

        Serial.printf("NEW COMMAND SEQ=%lu\n",
                      (unsigned long)seq);

        // Komut ileride yalnızca burada işlenecek.

        if (type == 0x10) // PROGRAM_BEGIN
        {
          const uint16_t payloadLength =
              (uint16_t)data[21] |
              ((uint16_t)data[22] << 8);

          if (payloadLength != 8)
          {
            Serial.println("PROGRAM_BEGIN: INVALID LENGTH");
          }
          else
          {
            const uint32_t size =
                (uint32_t)data[23] |
                ((uint32_t)data[24] << 8) |
                ((uint32_t)data[25] << 16) |
                ((uint32_t)data[26] << 24);

            const uint32_t crc =
                (uint32_t)data[27] |
                ((uint32_t)data[28] << 8) |
                ((uint32_t)data[29] << 16) |
                ((uint32_t)data[30] << 24);

            if (size == 0 || size > MAX_PROGRAM_SIZE)
            {
              Serial.println("PROGRAM_BEGIN: INVALID SIZE");
            }
            else
            {
              expectedProgramSize = size;
              expectedProgramCRC = crc;
              receivedProgramSize = 0;
              programTransferActive = true;

              Serial.printf(
                  "PROGRAM_BEGIN: SIZE=%lu CRC=%08lX\n",
                  (unsigned long)size,
                  (unsigned long)crc);
            }
          }
        }

        if (type == 0x11) // PROGRAM_DATA
        {
          const uint16_t payloadLength =
              (uint16_t)data[21] |
              ((uint16_t)data[22] << 8);

          if (!programTransferActive)
          {
            Serial.println("PROGRAM_DATA: NO ACTIVE TRANSFER");
          }
          else if (payloadLength > expectedProgramSize - receivedProgramSize)
          {
            Serial.println("PROGRAM_DATA: SIZE OVERFLOW");
          }
          else
          {
            memcpy(
                programBuffer + receivedProgramSize,
                data + 23,
                payloadLength);

            receivedProgramSize += payloadLength;

            Serial.printf(
                "PROGRAM_DATA: RECEIVED=%lu/%lu\n",
                (unsigned long)receivedProgramSize,
                (unsigned long)expectedProgramSize);
          }
        }

        if (type == 0x12) // PROGRAM_END
        {
          const uint16_t payloadLength =
              (uint16_t)data[21] |
              ((uint16_t)data[22] << 8);

          if (payloadLength != 0)
          {
            Serial.println("PROGRAM_END: INVALID LENGTH");
          }
          else if (!programTransferActive)
          {
            Serial.println("PROGRAM_END: NO ACTIVE TRANSFER");
          }
          else if (receivedProgramSize != expectedProgramSize)
          {
            Serial.printf(
                "PROGRAM_END: SIZE ERROR %lu/%lu\n",
                (unsigned long)receivedProgramSize,
                (unsigned long)expectedProgramSize);
          }
          else
          {
            const uint32_t actualCRC =
                LynraProtocol::calculateCRC32(
                    programBuffer, receivedProgramSize);

            if (actualCRC != expectedProgramCRC)
            {
              Serial.println("PROGRAM_END: CRC ERROR");
            }
            else
            {
              Serial.println("PROGRAM_END: CRC OK");
              Serial.println("PROGRAM TRANSFER COMPLETE");

              programTransferActive = false;
              JsonDocument doc;

              DeserializationError error = deserializeJson(
                  doc,
                  programBuffer,
                  receivedProgramSize);

              if (error)
              {
                Serial.printf("JSON ERROR: %s\n", error.c_str());
              }
              else
              {
                const char *name = doc["name"] | "Unknown";
                JsonArray blocks = doc["controlBlocks"].as<JsonArray>();

                Serial.printf("PROGRAM NAME: %s\n", name);
                Serial.printf("CONTROL BLOCKS: %u\n",
                              (unsigned)blocks.size());

                if (!blocks.isNull() && blocks.size() > 0)
                {
                  JsonArray groups = blocks[0]["groups"].as<JsonArray>();

                  Serial.printf("RULE COUNT: %u\n",
                                (unsigned)groups.size());

                  activeRuleCount = 0;
                  plcReady = false;

                  for (JsonObject rule : groups)
                  {
                    if (activeRuleCount >= MAX_PLC_RULES)
                      break;

                    JsonArray conditions = rule["conditions"].as<JsonArray>();
                    JsonArray actions = rule["actions"].as<JsonArray>();

                    if (conditions.size() != 1 || actions.size() != 1)
                      continue;

                    JsonObject condition = conditions[0];
                    JsonObject action = actions[0];

                    if (strcmp(condition["trigger"] | "", "highLevel") != 0 ||
                        strcmp(action["type"] | "", "setOutput") != 0)
                      continue;

                    int input = condition["inputIndex"] | 0;
                    int output = action["outputIndex"] | 0;

                    if (input < 1 || input > 4 || output < 1 || output > 4)
                      continue;

                    PlcRule &r = activeRules[activeRuleCount++];

                    r.inputIndex = input;
                    r.expectedState = condition["expectedState"] | true;
                    r.outputIndex = output;
                    r.outputState = action["outputState"] | true;

                    Serial.printf("RULE LOADED: I%d -> Q%d\n", input, output);
                  }

                  plcReady = activeRuleCount > 0;

                  Serial.printf("PLC READY: %u RULES\n", activeRuleCount);
                }
              }

              // JSON doğrulama ve programı etkinleştirme
              // sonraki aşamada yapılacak.
            }
          }
        }
      }

      if (tx != nullptr)
      {
        uint8_t ack[27] = {};

        ack[0] = 0x4C;
        ack[1] = 0x43;
        ack[2] = 1;
        ack[3] = 23;

        ack[16] = 2; // ACK

        // Gelen SEQ numarasını aynen geri gönder
        ack[17] = seq & 0xFF;
        ack[18] = (seq >> 8) & 0xFF;
        ack[19] = (seq >> 16) & 0xFF;
        ack[20] = (seq >> 24) & 0xFF;

        const uint32_t crc =
            LynraProtocol::calculateCRC32(ack + 2, 21);

        ack[23] = crc & 0xFF;
        ack[24] = (crc >> 8) & 0xFF;
        ack[25] = (crc >> 16) & 0xFF;
        ack[26] = (crc >> 24) & 0xFF;

        tx->setValue(ack, sizeof(ack));
        tx->notify();

        Serial.printf("BLE TX: ACK SEQ=%lu\n",
                      (unsigned long)seq);
      }
    }
    else
    {
      Serial.printf("BLE FRAME REJECTED (%u bytes)\n",
                    (unsigned)length);
    }
  }
};

void setup()
{
  Serial.begin(115200);
  const uint8_t testData[] = {'1', '2', '3', '4', '5', '6', '7', '8', '9'};

  uint32_t crc = LynraProtocol::calculateCRC32(
      testData, sizeof(testData));

  Serial.printf("CRC32 TEST: %08lX\n", (unsigned long)crc);

  uint8_t frame[27] = {
      0x4C, 0x43, // SOF
      1, 23       // VERSION, HEADER_LEN
  };

  // Boş payload için CRC hesapla
  uint32_t frameCRC =
      LynraProtocol::calculateCRC32(frame + 2, 21);

  frame[23] = frameCRC & 0xFF;
  frame[24] = (frameCRC >> 8) & 0xFF;
  frame[25] = (frameCRC >> 16) & 0xFF;
  frame[26] = (frameCRC >> 24) & 0xFF;

  Serial.printf("VALID FRAME: %s\n",
                LynraProtocol::verifyFrame(frame, sizeof(frame)) ? "OK" : "ERROR");

  // CRC kapsamındaki bir byte'ı boz
  frame[4] ^= 0x01;

  Serial.printf("CORRUPTED FRAME: %s\n",
                LynraProtocol::verifyFrame(frame, sizeof(frame)) ? "OK" : "REJECTED");
  delay(1000);

  BLEDevice::init("LynraControl");

  BLEServer *server = BLEDevice::createServer();

  BLEService *service = server->createService(SERVICE_UUID);

  BLECharacteristic *rx = service->createCharacteristic(
      WRITE_UUID,
      BLECharacteristic::PROPERTY_WRITE |
          BLECharacteristic::PROPERTY_WRITE_NR);

  rx->setCallbacks(new ReceiveCallbacks());

  tx = service->createCharacteristic(
      NOTIFY_UUID,
      BLECharacteristic::PROPERTY_NOTIFY);

  tx->addDescriptor(new BLE2902());

  service->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->start();

  Serial.println("LynraControl BLE ready");
}

void loop()
{
  if (Serial.available())
  {
    char c = Serial.read();

    if (c >= '1' && c <= '4')
    {
      int index = c - '1';
      virtualInputs[index] = true;
      Serial.printf("INPUT: I%d=ON\n", index + 1);
    }
    else if (c >= 'a' && c <= 'd')
    {
      int index = c - 'a';
      virtualInputs[index] = false;
      Serial.printf("INPUT: I%d=OFF\n", index + 1);
    }
  }

  if (plcReady)
  {
    for (uint8_t i = 0; i < activeRuleCount; i++)
    {
      const PlcRule &rule = activeRules[i];

      int inputIndex = rule.inputIndex - 1;
      int outputIndex = rule.outputIndex - 1;

      bool inputState = virtualInputs[inputIndex];

      bool newOutput =
          (inputState == rule.expectedState)
              ? rule.outputState
              : !rule.outputState;

      if (newOutput != virtualOutputs[outputIndex])
      {
        virtualOutputs[outputIndex] = newOutput;

        Serial.printf(
            "PLC: I%d=%d -> Q%d=%d\n",
            rule.inputIndex,
            inputState,
            rule.outputIndex,
            newOutput);
      }
    }
  }

  delay(100);
}
