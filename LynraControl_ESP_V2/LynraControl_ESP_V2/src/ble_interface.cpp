#include "ble_interface.h"

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "plc_manager.h"

#define SERVICE_UUID "8d21a100-64c2-4c3a-9d1e-123456789abc"
#define WRITE_UUID "8d21a101-64c2-4c3a-9d1e-123456789abc"
#define NOTIFY_UUID "8d21a102-64c2-4c3a-9d1e-123456789abc"

static BLECharacteristic *tx = nullptr;

class ServerCallbacks : public BLEServerCallbacks
{
    void onConnect(BLEServer *server) override
    {
        Serial.println("BLE CLIENT CONNECTED");
    }

    void onDisconnect(BLEServer *server) override
    {
        Serial.println("BLE CLIENT DISCONNECTED");
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
class ReceiveCallbacks : public BLECharacteristicCallbacks
{
    void onWrite(BLECharacteristic *characteristic) override
    {
        std::string value = characteristic->getValue();

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

            if (type == 0x01 || type == 0x31)
            {
                Serial.printf("BLE RX: TYPE=0x%02X SEQ=%lu\n",
                              type, (unsigned long)seq);

                sendAck(seq);
                if (type == 0x31)
                    sendPlcStatus(seq);
            }

            return;
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
    }
};

bool bleInit()
{
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