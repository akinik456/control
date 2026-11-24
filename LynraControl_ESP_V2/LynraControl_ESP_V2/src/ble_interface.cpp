#include <Arduino.h>
#include <esp_timer.h>
#include "ble_interface.h"

#include <ArduinoJson.h>
#include "models/control_program.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "plc_manager.h"
#include "plc_program_store.h"

#define SERVICE_UUID "8d21a100-64c2-4c3a-9d1e-123456789abc"
#define WRITE_UUID "8d21a101-64c2-4c3a-9d1e-123456789abc"
#define NOTIFY_UUID "8d21a102-64c2-4c3a-9d1e-123456789abc"

static BLECharacteristic *tx = nullptr;
static SemaphoreHandle_t transferMutex = nullptr;
static constexpr size_t MAX_PROGRAM_SIZE = 32768;

static uint8_t programBuffer[MAX_PROGRAM_SIZE];

static uint32_t expectedProgramSize = 0;
static uint32_t expectedProgramCRC = 0;
static uint32_t receivedProgramSize = 0;

static bool restartPending = false;
static uint32_t restartRequestedMs = 0;
static bool programTransferActive = false;
static bool hasLastDataSeq = false;
static uint32_t lastDataSeq = 0;
static uint32_t lastProgramPacketMs = 0;

static constexpr uint32_t PROGRAM_TIMEOUT_MS = 10000;

extern bool plcSetManualMode(bool enabled);
extern bool plcSetManualInput(uint8_t index, bool on);

class ServerCallbacks : public BLEServerCallbacks
{
    void onConnect(BLEServer *server) override
    {
        Serial.println("BLE CLIENT CONNECTED");
    }

    void onDisconnect(BLEServer *server) override
    {
        Serial.println("BLE CLIENT DISCONNECTED");
        // Only an interrupted programming session is aborted. Normal RUN
        // remains independent of the phone connection.
        if (transferMutex != nullptr &&
            xSemaphoreTake(transferMutex, pdMS_TO_TICKS(1000)) == pdTRUE)
        {
            if (programTransferActive)
            {
                programTransferActive = false;
                hasLastDataSeq = false;
                plcAbortProgramming();
                Serial.println("PROGRAM TRANSFER ABORTED: BLE DISCONNECT");
            }
            xSemaphoreGive(transferMutex);
        }
        plcSetManualMode(false);
        BLEDevice::startAdvertising();
        Serial.println("BLE ADVERTISING RESTARTED");
    }
};
#include "lynra_protocol.h"

static void sendAck(uint32_t seq)
{
    if (tx == nullptr)
        return;

    uint8_t ack[27] = {};

    ack[0] = 0x4C;
    ack[1] = 0x43;
    ack[2] = 1;
    ack[3] = 23;
    ack[16] = 0x02;

    for (int i = 0; i < 4; ++i)
        ack[17 + i] = (seq >> (8 * i)) & 0xFF;

    const uint32_t crc =
        LynraProtocol::calculateCRC32(ack + 2, 21);

    for (int i = 0; i < 4; ++i)
        ack[23 + i] = (crc >> (8 * i)) & 0xFF;

    tx->setValue(ack, sizeof(ack));
    tx->notify();

    Serial.printf("BLE TX: ACK SEQ=%lu\n",
                  (unsigned long)seq);
}
static void sendPlcStatus(uint32_t seq)
{
    if (tx == nullptr)
        return;

    uint8_t frame[28] = {};

    frame[0] = 0x4C;
    frame[1] = 0x43;
    frame[2] = 1;
    frame[3] = 23;
    frame[16] = 0x30;

    for (int i = 0; i < 4; ++i)
        frame[17 + i] = (seq >> (8 * i)) & 0xFF;

    frame[21] = 1; // Payload uzunluğu
    frame[23] = plcGetStatus();

    const uint32_t crc =
        LynraProtocol::calculateCRC32(frame + 2, 22);

    for (int i = 0; i < 4; ++i)
        frame[24 + i] = (crc >> (8 * i)) & 0xFF;

    tx->setValue(frame, sizeof(frame));
    tx->notify();

    Serial.printf("BLE TX: STATUS=%u SEQ=%lu\n",
                  frame[23], (unsigned long)seq);
}
// Declared here to avoid changing the existing project header.
extern bool plcReadIo(uint32_t &inputs, uint32_t &outputs, bool &manual);

static void sendIoResponse(uint32_t seq)
{
    uint32_t inputs, outputs;
    bool manual;
    if (!tx || !plcReadIo(inputs, outputs, manual)) return;
    const uint64_t timeMs = static_cast<uint64_t>(esp_timer_get_time()) / 1000;
    uint8_t frame[44] = {};
    frame[0] = 0x4C;
    frame[1] = 0x43;
    frame[2] = 1;
    frame[3] = 23;
    frame[16] = 0x33;
    frame[21] = 17;
    for (int i = 0; i < 4; ++i)
    {
        frame[17+i] = (seq >> (8*i)) & 0xFF;
        frame[23+i] = (inputs >> (8*i)) & 0xFF;
        frame[27+i] = (outputs >> (8*i)) & 0xFF;
    }
    for (int i = 0; i < 8; ++i)
        frame[31+i] = (timeMs >> (8*i)) & 0xFF;
    frame[39] = manual ? 1 : 0;
    const uint32_t crc = LynraProtocol::calculateCRC32(frame + 2, 38);
    for (int i = 0; i < 4; ++i)
        frame[40+i] = (crc >> (8*i)) & 0xFF;
    tx->setValue(frame, sizeof(frame));
    tx->notify();
}
extern bool plcReadEvents(uint32_t cursor, uint32_t &first, uint8_t &count,
                          bool &lost, uint8_t *records);
static void sendEvents(uint32_t seq, uint32_t cursor)
{
    uint8_t frame[27 + 6 + 160] = {};
    uint32_t first; uint8_t count; bool lost;
    if (!tx || !plcReadEvents(cursor, first, count, lost, frame + 29)) return;
    const uint16_t len = 6 + 16 * count;
    frame[0]=0x4C; frame[1]=0x43; frame[2]=1; frame[3]=23; frame[16]=0x35;
    frame[21]=len & 255; frame[22]=len >> 8;
    for (int i=0;i<4;++i) { frame[17+i]=seq>>(8*i); frame[23+i]=first>>(8*i); }
    frame[27]=lost ? 1 : 0; frame[28]=count;
    const uint32_t crc = LynraProtocol::calculateCRC32(frame+2,21+len);
    for (int i=0;i<4;++i) frame[23+len+i]=crc>>(8*i);
    tx->setValue(frame,27+len); tx->notify();
}
class ReceiveCallbacks : public BLECharacteristicCallbacks
{
    void onWrite(BLECharacteristic *characteristic) override
    {
        if (transferMutex == nullptr)
            return;

        if (xSemaphoreTake(transferMutex, pdMS_TO_TICKS(1000)) != pdTRUE)
        {
            Serial.println("BLE RX: MUTEX TIMEOUT");
            return;
        }
        std::string value = characteristic->getValue();
        if (programTransferActive &&
            (uint32_t)(millis() - lastProgramPacketMs) > PROGRAM_TIMEOUT_MS)
        {
            programTransferActive = false;
            hasLastDataSeq = false;

            plcAbortProgramming();

            Serial.println("PROGRAM TRANSFER TIMEOUT");
        }

        const uint8_t *data =
            reinterpret_cast<const uint8_t *>(value.data());

        if (LynraProtocol::verifyFrame(data, value.size()))
        {
            const uint8_t type = data[16];

            const uint32_t seq =
                (uint32_t)data[17] |
                ((uint32_t)data[18] << 8) |
                ((uint32_t)data[19] << 16) |
                ((uint32_t)data[20] << 24);

            if (type == 0x38) {
                if (value.size() == 27 && !programTransferActive) {
                    if (!restartPending) {
                        restartPending = true;
                        restartRequestedMs = millis();
                    }
                    sendAck(seq);
                }
                xSemaphoreGive(transferMutex);
                return;
            }
            if (restartPending) {
                xSemaphoreGive(transferMutex);
                return;
            }

            if (type == 0x36 || type == 0x37) {
                bool ok = false;
                if (!programTransferActive) {
                    if (type == 0x36 && value.size() == 28 && data[23] <= 1)
                        ok = plcSetManualMode(data[23] != 0);
                    if (type == 0x37 && value.size() == 29 && data[23] < 4 && data[24] <= 1)
                        ok = plcSetManualInput(data[23], data[24] != 0);
                }
                if (ok) sendAck(seq);
                xSemaphoreGive(transferMutex);
                return;
            }

            // Read-only query; response itself confirms receipt.
            if (type == 0x34)
            {
                if (value.size() == 31 && !programTransferActive) {
                    uint32_t cursor = 0;
                    for (int i=0;i<4;++i) cursor |= uint32_t(data[23+i]) << (8*i);
                    sendEvents(seq,cursor);
                }
                xSemaphoreGive(transferMutex);
                return;
            }
            if (type == 0x32)
            {
                if (value.size() == 27 && !programTransferActive)
                    sendIoResponse(seq);
                xSemaphoreGive(transferMutex);
                return;
            }

            if (type == 0x01 || type == 0x31 ||
                type == 0x20 || type == 0x21 ||
                type == 0x10 || type == 0x11 || type == 0x12)
            {
                Serial.printf("BLE RX: TYPE=0x%02X SEQ=%lu\n",
                              type, (unsigned long)seq);
                if (type == 0x20) // RUN
                {
                    if (!programTransferActive && plcRun())
                        Serial.println("PLC STATE: RUN (BLE)");
                    else
                        Serial.println("RUN REJECTED (BLE)");
                }
                else if (type == 0x21) // STOP
                {
                    plcStop();
                    programTransferActive = false;
                    hasLastDataSeq = false;
                    Serial.println("PLC STATE: STOP (BLE)");
                }
                else if (type == 0x10) // PROGRAM_BEGIN
                {
                    const uint16_t payloadLength =
                        (uint16_t)data[21] |
                        ((uint16_t)data[22] << 8);

                    if (payloadLength == 8)
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

                        if (size > 0 && size <= MAX_PROGRAM_SIZE &&
                            plcBeginProgramming())
                        {
                            expectedProgramSize = size;
                            expectedProgramCRC = crc;
                            receivedProgramSize = 0;
                            programTransferActive = true;
                            hasLastDataSeq = false;
                            lastProgramPacketMs = millis();

                            Serial.printf(
                                "PROGRAM_BEGIN: SIZE=%lu CRC=%08lX\n",
                                (unsigned long)size,
                                (unsigned long)crc);
                        }
                        else
                        {
                            Serial.println("PROGRAM_BEGIN REJECTED");
                        }
                    }
                    else
                    {
                        Serial.println("PROGRAM_BEGIN: INVALID LENGTH");
                    }
                }
                else if (type == 0x11) // PROGRAM_DATA
                {
                    const uint16_t payloadLength =
                        (uint16_t)data[21] |
                        ((uint16_t)data[22] << 8);

                    if (!programTransferActive)
                    {
                        Serial.println("PROGRAM_DATA: NO ACTIVE TRANSFER");
                    }
                    else if (hasLastDataSeq && seq == lastDataSeq)
                    {
                        Serial.printf("PROGRAM_DATA: DUPLICATE SEQ=%lu\n",
                                      (unsigned long)seq);
                    }
                    else if (payloadLength >
                             expectedProgramSize - receivedProgramSize)
                    {
                        programTransferActive = false;
                        plcAbortProgramming();

                        Serial.println("PROGRAM_DATA: SIZE OVERFLOW");
                    }
                    else
                    {
                        memcpy(
                            programBuffer + receivedProgramSize,
                            data + 23,
                            payloadLength);

                        receivedProgramSize += payloadLength;
                        lastDataSeq = seq;
                        hasLastDataSeq = true;
                        lastProgramPacketMs = millis();

                        Serial.printf(
                            "PROGRAM_DATA: RECEIVED=%lu/%lu\n",
                            (unsigned long)receivedProgramSize,
                            (unsigned long)expectedProgramSize);
                    }
                }
                else if (type == 0x12) // PROGRAM_END
                {
                    const uint16_t payloadLength =
                        (uint16_t)data[21] |
                        ((uint16_t)data[22] << 8);

                    if (!programTransferActive ||
                        payloadLength != 0 ||
                        receivedProgramSize != expectedProgramSize)
                    {
                        programTransferActive = false;
                        plcAbortProgramming();

                        Serial.println("PROGRAM_END: INVALID TRANSFER");
                    }
                    else
                    {
                        const uint32_t actualCRC =
                            LynraProtocol::calculateCRC32(
                                programBuffer, receivedProgramSize);

                        if (actualCRC != expectedProgramCRC)
                        {
                            programTransferActive = false;
                            plcAbortProgramming();

                            Serial.println("PROGRAM_END: CRC ERROR");
                        }
                        else
                        {
                            programTransferActive = false;
                            Serial.println("PROGRAM_END: CRC OK");

                            JsonDocument doc;

                            DeserializationError error = deserializeJson(
                                doc, programBuffer, receivedProgramSize);

                            if (error)
                            {
                                Serial.printf(
                                    "JSON ERROR: %s\n", error.c_str());
                                plcAbortProgramming();
                            }
                            else
                            {
                                ControlProgram receivedProgram;

                                if (!receivedProgram.fromJson(
                                        doc.as<JsonVariantConst>()))
                                {
                                    Serial.println("PROGRAM PARSE FAILED");
                                    plcAbortProgramming();
                                }
                                else
                                {
                                    String validationError;

                                    if (!receivedProgram.validate(
                                            validationError))
                                    {
                                        Serial.printf(
                                            "VALIDATION FAILED: %s\n",
                                            validationError.c_str());
                                        plcAbortProgramming();
                                    }
                                    else
                                    {
                                        Serial.println(
                                            "PROGRAM VALIDATION OK");

                                        // Preflight must not mutate the active C engine.
                                        if (!plcPreflightProgram(receivedProgram))
                                        {
                                            Serial.println("PROGRAM PREFLIGHT FAILED");
                                            plcAbortProgramming();
                                        }
                                        else if (!PlcProgramStore::prepare(
                                                     programBuffer, receivedProgramSize))
                                        {
                                            Serial.println("PROGRAM FLASH PREPARE FAILED");
                                            plcAbortProgramming();
                                        }
                                        else if (!PlcProgramStore::commit())
                                        {
                                            // The active RAM program is untouched.
                                            // In rare post-rename verification failures,
                                            // reboot may select the new flash record.
                                            Serial.println("PROGRAM FLASH COMMIT FAILED - STOP");
                                            plcAbortProgramming();
                                        }
                                        else
                                        {
                                            Serial.println("PROGRAM FLASH COMMIT OK");
                                            if (plcLoadProgram(receivedProgram))
                                            {
                                                Serial.println("PROGRAM LOAD SUCCESS");
                                                if (plcFinishProgramming())
                                                    Serial.println("PROGRAM ACTIVATED");
                                                else
                                                {
                                                    Serial.println("PROGRAM ACTIVATION FAILED - STOP");
                                                    plcAbortProgramming();
                                                }
                                            }
                                            else
                                            {
                                                // Persisted program is valid; never RUN
                                                // if unexpected engine load fails.
                                                Serial.println("PROGRAM LOAD FAILED AFTER COMMIT - STOP");
                                                plcAbortProgramming();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                sendAck(seq);

                if (type == 0x31 || type == 0x12 ||
                    type == 0x20 || type == 0x21)
                    sendPlcStatus(seq);
            }

            xSemaphoreGive(transferMutex);
            return;
        }

        // A corrupt framed packet during programming invalidates the session.
        // Do not abort on arbitrary noise while not programming.
        if (programTransferActive)
        {
            programTransferActive = false;
            hasLastDataSeq = false;
            plcAbortProgramming();
            Serial.println("PROGRAM TRANSFER ABORTED: INVALID FRAME/CRC");
        }

        if (value == "HELLO")
        {
            Serial.println("BLE RX: HELLO");

            if (tx != nullptr)
            {
                tx->setValue("HELLO_ACK");
                tx->notify();
            }
        }
        xSemaphoreGive(transferMutex);
    }
};
bool bleInit()
{
    transferMutex = xSemaphoreCreateMutex();

    if (transferMutex == nullptr)
    {
        Serial.println("BLE TRANSFER MUTEX CREATE FAILED");
        return false;
    }
    BLEDevice::init("LynraControl");

    BLEServer *server = BLEDevice::createServer();
    if (server == nullptr)
        return false;
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
    return true;
}
void bleLoop()
{
    if (transferMutex == nullptr)
        return;

    if (xSemaphoreTake(transferMutex, pdMS_TO_TICKS(10)) != pdTRUE)
        return;

    if (restartPending && (uint32_t)(millis() - restartRequestedMs) >= 300)
    {
        xSemaphoreGive(transferMutex);
        Serial.println("SYSTEM RESTART REQUESTED");
        ESP.restart();
        return;
    }

    if (programTransferActive &&
        (uint32_t)(millis() - lastProgramPacketMs) > PROGRAM_TIMEOUT_MS)
    {
        programTransferActive = false;
        hasLastDataSeq = false;

        plcAbortProgramming();

        Serial.println("PROGRAM TRANSFER TIMEOUT");
    }

    xSemaphoreGive(transferMutex);
}