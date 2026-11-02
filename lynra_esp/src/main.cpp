

#include <Arduino.h>
#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "lynra_protocol.h"
#include "models/control_program.h"
#include "core/control_engine.h"

void testControlProgramJson();

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

ControlProgram activeProgram;
ControlEngine controlEngine(activeProgram);
enum class PlcState
{
  Stop,
  Programming,
  Run
};

PlcState plcState = PlcState::Stop;
SemaphoreHandle_t programMutex = nullptr;
// LynraControl physical I/O (ESP32-WROOM-32D, 3.3V logic)
constexpr uint8_t INPUT_PINS[4] = {32, 33, 25, 26};
constexpr uint8_t OUTPUT_PINS[4] = {16, 17, 18, 19};

uint32_t lastSeq = 0;
bool hasLastSeq = false;

uint32_t lastProgramPacketMs = 0;
constexpr uint32_t PROGRAM_TIMEOUT_MS = 10000;
constexpr uint8_t BLE_TYPE_STATUS = 0x30;
constexpr uint8_t BLE_TYPE_STATUS_REQUEST = 0x31;

// STATUS payload: 0=STOP, 1=PROGRAMMING, 2=RUN.
// STATUS is a notification, not an ACK. Its SEQ echoes the request when available.
void sendPlcStatus(uint32_t seq)
{
  if (tx == nullptr)
    return;

  xSemaphoreTake(programMutex, portMAX_DELAY);
  const PlcState state = plcState;
  xSemaphoreGive(programMutex);

  uint8_t frame[28] = {};
  frame[0] = 0x4C;
  frame[1] = 0x43;
  frame[2] = 1;
  frame[3] = 23;
  frame[16] = BLE_TYPE_STATUS;
  for (int i = 0; i < 4; ++i)
    frame[17 + i] = (seq >> (8 * i)) & 0xFF;
  frame[21] = 1; // payload length
  frame[23] = state == PlcState::Run ? 2 : state == PlcState::Programming ? 1
                                                                          : 0;

  const uint32_t crc = LynraProtocol::calculateCRC32(frame + 2, 22);
  for (int i = 0; i < 4; ++i)
    frame[24 + i] = (crc >> (8 * i)) & 0xFF;

  tx->setValue(frame, sizeof(frame));
  tx->notify();
  Serial.printf("BLE TX: STATUS=%u SEQ=%lu\n",
                (unsigned)frame[23], (unsigned long)seq);
}

class ServerCallbacks : public BLEServerCallbacks
{
  void onConnect(BLEServer *server) override
  {
    hasLastSeq = false;
    lastSeq = 0;

    Serial.println("BLE CLIENT CONNECTED");
  }

  void onDisconnect(BLEServer *server) override
  {
    Serial.println("BLE CLIENT DISCONNECTED");
    BLEDevice::startAdvertising();
    Serial.println("BLE ADVERTISING RESTARTED");
  }
};
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
        if (type == 0x20) // RUN
        {
          xSemaphoreTake(programMutex, portMAX_DELAY);

          if (plcState == PlcState::Stop &&
              !activeProgram.controlBlocks.empty())
          {
            controlEngine.reset();
            plcState = PlcState::Run;
            Serial.println("PLC STATE: RUN (BLE)");
          }
          else
          {
            Serial.println("RUN REJECTED");
          }

          xSemaphoreGive(programMutex);
        }

        if (type == 0x21) // STOP
        {
          xSemaphoreTake(programMutex, portMAX_DELAY);

          plcState = PlcState::Stop;
          controlEngine.reset();

          xSemaphoreGive(programMutex);

          programTransferActive = false;

          Serial.println("PLC STATE: STOP (BLE)");
        }
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
              // Mevcut RUN durumunu değiştirmiyoruz;
              // geçerli bir programlama oturumu başlamadı.
            }
            else
            {
              expectedProgramSize = size;
              expectedProgramCRC = crc;
              receivedProgramSize = 0;
              programTransferActive = true;

              lastProgramPacketMs = millis();

              xSemaphoreTake(programMutex, portMAX_DELAY);

              plcState = PlcState::Programming;
              controlEngine.reset();

              xSemaphoreGive(programMutex);

              Serial.println("PLC STATE: PROGRAMMING - OUTPUTS OFF");

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
            plcState = PlcState::Stop;
            programTransferActive = false;
            Serial.println("PROGRAM_DATA: SIZE OVERFLOW");
            Serial.println("PLC STATE: STOP");
          }
          else
          {
            memcpy(
                programBuffer + receivedProgramSize,
                data + 23,
                payloadLength);

            receivedProgramSize += payloadLength;

            lastProgramPacketMs = millis();

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
            plcState = PlcState::Stop;
            programTransferActive = false;
            Serial.println("PROGRAM_END: INVALID LENGTH");
            Serial.println("PLC STATE: STOP");
          }
          else if (!programTransferActive)
          {
            Serial.println("PROGRAM_END: NO ACTIVE TRANSFER");
          }
          else if (receivedProgramSize != expectedProgramSize)
          {
            plcState = PlcState::Stop;
            programTransferActive = false;

            Serial.printf(
                "PROGRAM_END: SIZE ERROR %lu/%lu\n",
                (unsigned long)receivedProgramSize,
                (unsigned long)expectedProgramSize);

            Serial.println("PLC STATE: STOP");
          }
          else
          {
            const uint32_t actualCRC =
                LynraProtocol::calculateCRC32(
                    programBuffer, receivedProgramSize);

            if (actualCRC != expectedProgramCRC)
            {
              plcState = PlcState::Stop;
              programTransferActive = false;

              Serial.println("PROGRAM_END: CRC ERROR");
              Serial.println("PLC STATE: STOP");
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
                plcState = PlcState::Stop;
                Serial.printf("JSON ERROR: %s\n", error.c_str());
                Serial.println("PLC STATE: STOP");
              }
              else
              {
                const char *name = doc["name"] | "Unknown";
                JsonArray blocks = doc["controlBlocks"].as<JsonArray>();

                Serial.printf("PROGRAM NAME: %s\n", name);
                Serial.printf("CONTROL BLOCKS: %u\n",
                              (unsigned)blocks.size());

                ControlProgram receivedProgram;

                if (!receivedProgram.fromJson(doc.as<JsonVariantConst>()))
                {
                  plcState = PlcState::Stop;
                  Serial.println("NEW PARSER: FAILED");
                  Serial.println("PLC STATE: STOP");
                }
                else
                {
                  String validationError;

                  if (!receivedProgram.validate(validationError))
                  {
                    xSemaphoreTake(programMutex, portMAX_DELAY);
                    plcState = PlcState::Stop;
                    xSemaphoreGive(programMutex);

                    Serial.printf("PROGRAM VALIDATION FAILED: %s\n",
                                  validationError.c_str());
                    Serial.println("PLC STATE: STOP");
                  }
                  else
                  {
                    Serial.println("PROGRAM VALIDATION OK");

                    xSemaphoreTake(programMutex, portMAX_DELAY);

                    activeProgram = std::move(receivedProgram);
                    controlEngine.reset();
                    plcState = PlcState::Run;

                    xSemaphoreGive(programMutex);

                    Serial.println("PLC STATE: RUN");
                    Serial.println("NEW ENGINE: PROGRAM LOADED");
                  }
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
        // Reply with the actual PLC state after ACK. A command ACK alone
        // does not imply that RUN or program validation succeeded.
        if (type == 1 || type == 0x10 || type == 0x12 ||
            type == 0x20 || type == 0x21 ||
            type == BLE_TYPE_STATUS_REQUEST)
          sendPlcStatus(seq);
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
  programMutex = xSemaphoreCreateMutex();

  if (programMutex == nullptr)
  {
    Serial.println("PROGRAM MUTEX CREATE FAILED");
    while (true)
      delay(1000);
  }
  // Safe default: drive all PLC outputs LOW before enabling BLE.
  for (int i = 0; i < 4; ++i)
  {
    digitalWrite(OUTPUT_PINS[i], LOW);
    pinMode(OUTPUT_PINS[i], OUTPUT);
    pinMode(INPUT_PINS[i], INPUT_PULLDOWN);
  }
  Serial.println("PHYSICAL GPIO READY: I1-I4 / Q1-Q4");
  delay(500);
  testControlProgramJson();
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

  server->setCallbacks(new ServerCallbacks());

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
  static bool previousNewOutputs[4] = {false, false, false, false};
  bool transferTimedOut = false;
  xSemaphoreTake(programMutex, portMAX_DELAY);
  if (plcState == PlcState::Programming &&
      programTransferActive &&
      (uint32_t)(millis() - lastProgramPacketMs) > PROGRAM_TIMEOUT_MS)
  {
    plcState = PlcState::Stop;
    programTransferActive = false;

    transferTimedOut = true;
    Serial.println("PROGRAM TRANSFER TIMEOUT");
    Serial.println("PLC STATE: STOP");
  }

  if (plcState == PlcState::Run &&
      !activeProgram.controlBlocks.empty())
  {
    std::map<int, bool> inputs;

    for (int i = 0; i < 4; i++)
    {
      inputs[i + 1] = (digitalRead(INPUT_PINS[i]) == HIGH);
    }

    controlEngine.scan(millis(), inputs);

    for (int i = 0; i < 4; i++)
    {
      bool state = controlEngine.output(i + 1);
      digitalWrite(OUTPUT_PINS[i], state ? HIGH : LOW);

      if (state != previousNewOutputs[i])
      {
        previousNewOutputs[i] = state;

        Serial.printf(
            "NEW ENGINE: Q%d=%d\n",
            i + 1,
            state);
      }
    }
  }
  if (plcState != PlcState::Run)
  {
    for (int i = 0; i < 4; i++)
    {
      digitalWrite(OUTPUT_PINS[i], LOW);
      if (previousNewOutputs[i])
      {
        previousNewOutputs[i] = false;
        Serial.printf("NEW ENGINE: Q%d=0\n", i + 1);
      }
    }
  }
  xSemaphoreGive(programMutex);
  if (transferTimedOut)
    sendPlcStatus(0);
  delay(100);
}
