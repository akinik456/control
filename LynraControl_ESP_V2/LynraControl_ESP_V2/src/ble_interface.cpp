#include <Arduino.h>
#include "device_api.h"
#include "ble_interface.h"

#include <ArduinoJson.h>
#include "models/control_program.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "plc_manager.h"
#include "plc_program_store.h"
#include "firmware_update.h"
#include <esp_ota_ops.h>

#define SERVICE_UUID "8d21a100-64c2-4c3a-9d1e-123456789abc"
#define WRITE_UUID "8d21a101-64c2-4c3a-9d1e-123456789abc"
#define NOTIFY_UUID "8d21a102-64c2-4c3a-9d1e-123456789abc"

static BLECharacteristic *tx = nullptr;
static bool accessReady = false;
using DeviceAccess::Channel;
using DeviceAccess::Lock;
static constexpr Channel BLE_CHANNEL = Channel::Ble;
static constexpr size_t MAX_PROGRAM_SIZE = 32768;

static uint8_t programBuffer[MAX_PROGRAM_SIZE];

static uint32_t expectedProgramSize = 0;
static uint32_t expectedProgramCRC = 0;
static uint32_t receivedProgramSize = 0;

static size_t readProgramSize = 0;
static uint32_t readProgramCRC = 0;
static bool restartPending = false;
static uint32_t restartRequestedMs = 0;
static bool programTransferActive = false;
static bool hasLastDataSeq = false;
static uint32_t lastDataSeq = 0;
static uint32_t lastProgramPacketMs = 0;

static bool fwReady = false;
static uint32_t fwSize = 0, fwLastMs = 0;
static constexpr uint32_t FW_TIMEOUT_MS = 30000;
static uint32_t fwLastOffset = 0;
static uint16_t fwLastLength = 0;
static uint8_t fwLastData[200];
// Publish transaction state before releasing the shared mutex.
static void unlockAccess() {
    DeviceAccess::setLock(restartPending ? Lock::Restart :
        (FirmwareUpdate::active() || fwReady) ? Lock::Firmware :
        programTransferActive ? Lock::Program : Lock::None, BLE_CHANNEL);
    DeviceAccess::give();
}
static void fwAbort() {
    FirmwareUpdate::abort();
    fwSize = 0; fwLastLength = 0;
    Serial.println("FW ABORT: STOP");
}
static constexpr uint32_t PROGRAM_TIMEOUT_MS = 10000;




class ServerCallbacks : public BLEServerCallbacks
{
    void onConnect(BLEServer *server,
               esp_ble_gatts_cb_param_t *param) override
{
    Serial.println("BLE CLIENT CONNECTED");

    server->updateConnParams(
        param->connect.remote_bda,
        6,   // Min interval: 7.5 ms
        12,  // Max interval: 15 ms
        0,   // Slave latency
        400  // Supervision timeout: 4 s
    );

    Serial.println("BLE FAST INTERVAL REQUESTED");
}

    void onDisconnect(BLEServer *server) override
    {
        Serial.println("BLE CLIENT DISCONNECTED");
        // Only an interrupted programming session is aborted. Normal RUN
        // remains independent of the phone connection.
        if (accessReady &&
            DeviceAccess::take(pdMS_TO_TICKS(1000)))
        {
            if (FirmwareUpdate::active()) fwAbort();
            readProgramSize = 0;
            if (programTransferActive)
            {
                programTransferActive = false;
                hasLastDataSeq = false;
                plcAbortProgramming();
                Serial.println("PROGRAM TRANSFER ABORTED: BLE DISCONNECT");
            }
            unlockAccess();
        }
        DeviceApi::releaseManual(BLE_CHANNEL);
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
    frame[23] = DeviceApi::getState();

    const uint32_t crc =
        LynraProtocol::calculateCRC32(frame + 2, 22);

    for (int i = 0; i < 4; ++i)
        frame[24 + i] = (crc >> (8 * i)) & 0xFF;

    tx->setValue(frame, sizeof(frame));
    tx->notify();

    Serial.printf("BLE TX: STATUS=%u SEQ=%lu\n",
                  frame[23], (unsigned long)seq);
}

static void sendIoResponse(uint32_t seq)
{
    DeviceApi::IoSnapshot io{};
    if (!tx || !DeviceApi::readIo(io)) return;
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
        frame[23+i] = (io.inputs >> (8*i)) & 0xFF;
        frame[27+i] = (io.outputs >> (8*i)) & 0xFF;
    }
    for (int i = 0; i < 8; ++i)
        frame[31+i] = (io.timeMs >> (8*i)) & 0xFF;
    frame[39] = io.manual ? 1 : 0;
    const uint32_t crc = LynraProtocol::calculateCRC32(frame + 2, 38);
    for (int i = 0; i < 4; ++i)
        frame[40+i] = (crc >> (8*i)) & 0xFF;
    tx->setValue(frame, sizeof(frame));
    tx->notify();
}
static void sendEvents(uint32_t seq, uint32_t cursor)
{
    uint8_t frame[27 + 6 + 160] = {};
    DeviceApi::IoEventBatch batch{};
    if (!tx || !DeviceApi::readEvents(cursor, batch)) return;
    const uint16_t len = 6 + 16 * batch.count;
    frame[0]=0x4C; frame[1]=0x43; frame[2]=1; frame[3]=23; frame[16]=0x35;
    frame[21]=len & 255; frame[22]=len >> 8;
    for (int i=0;i<4;++i) { frame[17+i]=seq>>(8*i); frame[23+i]=batch.first>>(8*i); }
    frame[27]=batch.lost ? 1 : 0; frame[28]=batch.count;
    for (uint8_t j=0;j<batch.count;++j) {
        const auto &e=batch.records[j];
        uint8_t *p=frame+29+16*j;
        for (int i=0;i<8;++i) p[i]=e.ms>>(8*i);
        for (int i=0;i<4;++i) { p[8+i]=e.inputs>>(8*i); p[12+i]=e.outputs>>(8*i); }
    }
    const uint32_t crc = LynraProtocol::calculateCRC32(frame+2,21+len);
    for (int i=0;i<4;++i) frame[23+len+i]=crc>>(8*i);
    tx->setValue(frame,27+len); tx->notify();
}
// Program readback: request/response, one chunk per request.
// The existing upload buffer is reused only outside programming sessions.
static void sendReadFrame(uint8_t type, uint32_t seq,
                          const uint8_t *payload, uint16_t len)
{
    if (!tx || len > 204) return;
    uint8_t frame[27 + 204] = {};
    frame[0]=0x4C; frame[1]=0x43; frame[2]=1; frame[3]=23;
    frame[16]=type; frame[21]=len & 255; frame[22]=len >> 8;
    for (int i=0;i<4;++i) frame[17+i]=seq>>(8*i);
    memcpy(frame+23,payload,len);
    const uint32_t crc=LynraProtocol::calculateCRC32(frame+2,21+len);
    for (int i=0;i<4;++i) frame[23+len+i]=crc>>(8*i);
    tx->setValue(frame,27+len); tx->notify();
}

static void sendActionValues(uint32_t seq, uint8_t rule, uint8_t action)
{
    DeviceApi::ActionValues result{};
    DeviceApi::readActionValues(rule, action, result);
    uint8_t payload[204] = {rule, action, result.status, result.type, result.count};
    uint16_t length=5;
    for (uint8_t i=0;i<result.count;++i) {
        payload[length++]=result.items[i].id;
        const uint64_t bits=static_cast<uint64_t>(result.items[i].value);
        for (int j=0;j<8;++j) payload[length++]=bits>>(8*j);
    }
    sendReadFrame(0x45, seq, payload, length);
}

static void sendProgramInfo(uint32_t seq)
{
    readProgramSize=0;
    readProgramCRC=0;
    size_t length=0;
    if (PlcProgramStore::load(programBuffer,MAX_PROGRAM_SIZE,length)) {
        readProgramSize=length;
        readProgramCRC=LynraProtocol::calculateCRC32(programBuffer,length);
    }
    uint8_t payload[8]={};
    for (int i=0;i<4;++i) {
        payload[i]=uint32_t(readProgramSize)>>(8*i);
        payload[4+i]=readProgramCRC>>(8*i);
    }
    sendReadFrame(0x41,seq,payload,sizeof(payload));
    Serial.printf("PROGRAM READ: SIZE=%lu CRC=%08lX\n",
                  (unsigned long)readProgramSize,(unsigned long)readProgramCRC);
}

static void sendProgramChunk(uint32_t seq,uint32_t offset)
{
    uint8_t payload[204]={};
    for (int i=0;i<4;++i) payload[i]=offset>>(8*i);
    size_t count=0;
    if (offset < readProgramSize) {
        count=readProgramSize-offset;
        if (count>200) count=200;
        memcpy(payload+4,programBuffer+offset,count);
    }
    sendReadFrame(0x43,seq,payload,4+count);
}

// OTA responses: 0x56, payload [command, esp_err_t LE32, value LE32].
// FW_INFO value is target capacity; other values are received bytes.
static uint32_t fwU32(const uint8_t* p) {
    uint32_t v=0; for (int i=0;i<4;++i) v |= uint32_t(p[i]) << (8*i); return v;
}
static void fwReply(uint8_t cmd, uint32_t seq, esp_err_t err, uint32_t value) {
    uint8_t p[9]={cmd};
    for (int i=0;i<4;++i) { p[1+i]=uint32_t(err)>>(8*i); p[5+i]=value>>(8*i); }
    sendReadFrame(0x56,seq,p,sizeof(p));
}
static void handleFirmware(uint8_t type, uint32_t seq, const uint8_t* p, uint16_t n) {
    esp_err_t err=ESP_ERR_INVALID_ARG;
    uint32_t value=FirmwareUpdate::received();
    if (type==0x50 && n==0) {
        const auto* target=esp_ota_get_next_update_partition(nullptr);
        err=target ? ESP_OK : ESP_ERR_NOT_FOUND;
        value=target ? target->size : 0;
    } else if (type==0x51 && n==4) {
        uint32_t size=fwU32(p);
        const auto* target=esp_ota_get_next_update_partition(nullptr);
        if (programTransferActive || fwReady) err=ESP_ERR_INVALID_STATE;
        else if (FirmwareUpdate::active()) {
            err=(size==fwSize && FirmwareUpdate::received()==0) ? ESP_OK : ESP_ERR_INVALID_STATE;
        } else if (!target || !size || size>target->size) err=ESP_ERR_INVALID_SIZE;
        else {
            DeviceApi::stop(BLE_CHANNEL);
            DeviceApi::setManualMode(BLE_CHANNEL, false);
            err=FirmwareUpdate::begin(size);
            if (err==ESP_OK) { fwSize=size; fwLastLength=0; readProgramSize=0; }
        }
        value=FirmwareUpdate::received();
    } else if (type==0x52 && n>4 && n<=204 && FirmwareUpdate::active()) {
        uint32_t offset=fwU32(p); uint16_t count=n-4;
        if (fwLastLength==count && offset==fwLastOffset &&
            offset+count==FirmwareUpdate::received() && !memcmp(fwLastData,p+4,count)) err=ESP_OK;
        else {
            err=FirmwareUpdate::write(offset,p+4,count);
            if (err==ESP_OK) { fwLastOffset=offset; fwLastLength=count; memcpy(fwLastData,p+4,count); }
        }
        value=FirmwareUpdate::received();
    } else if (type==0x53 && n==0) {
        if (fwReady) err=ESP_OK;
        else if (FirmwareUpdate::active()) {
            err=FirmwareUpdate::finish();
            if (err==ESP_OK) fwReady=true;
        } else err=ESP_ERR_INVALID_STATE;
        value=fwReady ? fwSize : FirmwareUpdate::received();
    } else if (type==0x54 && n==0) {
        if (fwReady) err=ESP_ERR_INVALID_STATE;
        else { fwAbort(); err=ESP_OK; value=0; }
    } else if (type==0x55 && n==0 && fwReady) {
        err=ESP_OK; value=fwSize;
        restartPending=true; restartRequestedMs=millis();
    }
    if (err==ESP_OK && FirmwareUpdate::active()) fwLastMs=millis();
    if (type!=0x52 || err!=ESP_OK) Serial.printf("FW CMD=%02X ERR=%s VALUE=%lu\n",type,esp_err_to_name(err),(unsigned long)value);
    fwReply(type,seq,err,value);
}

class ReceiveCallbacks : public BLECharacteristicCallbacks
{
    void onWrite(BLECharacteristic *characteristic) override
    {
        if (!accessReady)
            return;

        if (!DeviceAccess::take(pdMS_TO_TICKS(1000)))
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

            if (FirmwareUpdate::active() && (uint32_t)(millis()-fwLastMs)>FW_TIMEOUT_MS) fwAbort();
            if (type>=0x50 && type<=0x55 && !restartPending) {
                handleFirmware(type,seq,data+23,uint16_t(data[21]) | (uint16_t(data[22])<<8));
                unlockAccess(); return;
            }
            if (FirmwareUpdate::active() || fwReady) {
                unlockAccess(); return;
            }
            if (type == 0x38) {
                if (value.size() == 27 && !programTransferActive) {
                    if (!restartPending) {
                        restartPending = true;
                        restartRequestedMs = millis();
                    }
                    sendAck(seq);
                }
                unlockAccess();
                return;
            }
            if (restartPending) {
                unlockAccess();
                return;
            }

            if (type == 0x36 || type == 0x37) {
                bool ok = false;
                if (!programTransferActive) {
                    if (type == 0x36 && value.size() == 28 && data[23] <= 1)
                        ok = DeviceApi::setManualMode(BLE_CHANNEL, data[23] != 0);
                    if (type == 0x37 && value.size() == 29 && data[23] < 4 && data[24] <= 1)
                        ok = DeviceApi::setInput(BLE_CHANNEL, data[23], data[24] != 0);
                }
                if (ok) sendAck(seq);
                unlockAccess();
                return;
            }

            if (type == 0x44)
            {
                if (!programTransferActive && value.size() == 29)
                    sendActionValues(seq, data[23], data[24]);
                unlockAccess();
                return;
            }

            if (type == 0x40 || type == 0x42)
            {
                if (!programTransferActive) {
                    if (type == 0x40 && value.size() == 27)
                        sendProgramInfo(seq);
                    else if (type == 0x42 && value.size() == 31) {
                        uint32_t offset=0;
                        for (int i=0;i<4;++i) offset |= uint32_t(data[23+i]) << (8*i);
                        sendProgramChunk(seq,offset);
                    }
                }
                unlockAccess();
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
                unlockAccess();
                return;
            }
            if (type == 0x32)
            {
                if (value.size() == 27 && !programTransferActive)
                    sendIoResponse(seq);
                unlockAccess();
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
                    if (!programTransferActive && DeviceApi::run(BLE_CHANNEL))
                        Serial.println("PLC STATE: RUN (BLE)");
                    else
                        Serial.println("RUN REJECTED (BLE)");
                }
                else if (type == 0x21) // STOP
                {
                    DeviceApi::stop(BLE_CHANNEL);
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
                            readProgramSize = 0;
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

            unlockAccess();
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
        unlockAccess();
    }
};
bool bleInit()
{
    accessReady = DeviceAccess::init();

    if (!accessReady)
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
    if (!accessReady)
        return;

    if (!DeviceAccess::take(pdMS_TO_TICKS(10)))
        return;

    DeviceApi::serviceManualTimeout();
    if (FirmwareUpdate::active() && (uint32_t)(millis()-fwLastMs)>FW_TIMEOUT_MS) fwAbort();

    if (restartPending && (uint32_t)(millis() - restartRequestedMs) >= 300)
    {
        unlockAccess();
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

    unlockAccess();
}