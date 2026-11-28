#include "device_api.h"
#include "plc_manager.h"
#include <esp_timer.h>
#include <esp_system.h>
#include "device_config.h"
#include "plc_program_store.h"
#include "lynra_protocol.h"
#include <ArduinoJson.h>
#include <string.h>
#include "device_identity.h"
#include "device_license.h"
#include "wifi_config_store.h"

namespace DeviceApi
{
    bool readInfo(DeviceInfo &info)
    {
        DeviceInfo result{};
        if (esp_efuse_mac_get_default(result.deviceId) != ESP_OK)
            return false;
        result.model = DeviceConfig::kModel;
        result.serial = DeviceConfig::kSerialNumber;
        result.firmware = DeviceConfig::kFirmwareVersion;
        result.hardware = DeviceConfig::kHardwareVersion;
        result.inputs = DeviceConfig::kInputCount;
        result.outputs = DeviceConfig::kOutputCount;
        info = result;
        return true;
    }
		bool readPairingCode(char *dest, size_t capacity)
		{
				const String &code = DeviceIdentity_PairingCode();

				if (!dest || capacity < 20 || code.length() != 19)
						return false;

				memcpy(dest, code.c_str(), 20);
				return true;
		}
		bool readWifiLicense()
		{
				return DeviceLicense_IsWifiEnabled();
		}
    uint8_t getState()
    {
        return plcGetStatus();
    }
    bool readIo(IoSnapshot &snapshot)
    {
        IoSnapshot result{};
        if (!plcReadIo(result.inputs, result.outputs, result.manual))
            return false;
        result.timeMs = static_cast<uint64_t>(esp_timer_get_time()) / 1000;
        snapshot = result;
        return true;
    }
		bool readLiveSnapshot(LiveSnapshot &snapshot)
		{
				LiveSnapshot result{};

				if (!plcReadSnapshot(result.state,
														 result.inputs,
														 result.outputs,
														 result.manual))
						return false;

				result.uptimeMs =
						static_cast<uint64_t>(esp_timer_get_time()) / 1000;

				snapshot = result;
				return true;
		}
    using DeviceAccess::Channel;
    struct Guard
    {
        bool held = DeviceAccess::take(pdMS_TO_TICKS(1000));
        ~Guard()
        {
            if (held)
                DeviceAccess::give();
        }
    };
		bool activateWifiLicense(Channel channel, const char *code)
		{
				Guard g;

				if (!g.held)
						return false;

				if (channel != Channel::Ble &&
						channel != Channel::Serial)
						return false;

				if (DeviceAccess::currentLock() != DeviceAccess::Lock::None)
						return false;

				return DeviceLicense_SaveWifiCode(code);
		}
		bool saveWifiConfig(
    Channel channel,
    const char *ssid,
    const char *password)
{
    Guard g;

    if (!g.held)
        return false;

    if (channel != Channel::Ble &&
        channel != Channel::Serial)
        return false;

    if (DeviceAccess::currentLock() !=
        DeviceAccess::Lock::None)
        return false;

    if (!DeviceLicense_IsWifiEnabled())
        return false;

    return WifiConfig_Save(ssid, password);
}
    bool run(Channel channel)
    {
        Guard g;
        return g.held && DeviceAccess::canControl(channel) && plcRun();
    }
    bool stop(Channel channel)
    {
        Guard g;
        if (!g.held || !DeviceAccess::canControl(channel))
            return false;
        abortProgram(channel);
        plcStop();
        return plcGetStatus() == 0;
    }
    bool setManualMode(Channel channel, bool enabled)
    {
        Guard g;
        if (!g.held || !DeviceAccess::canManual(channel, enabled))
            return false;
        if (!plcSetManualMode(enabled))
            return false;
        DeviceAccess::setManualOwner(enabled ? channel : Channel::None);
        return true;
    }
    bool setInput(Channel channel, uint8_t index, bool on)
    {
        Guard g;
        if (!g.held || !DeviceAccess::canManual(channel, true) || DeviceAccess::manualOwner() != channel)
            return false;
        if (!plcSetManualInput(index, on))
            return false;
        DeviceAccess::refreshManual();
        return true;
    }
    void releaseManual(Channel channel)
    {
        Guard g;
        if (g.held && DeviceAccess::manualOwner() == channel && plcSetManualMode(false))
            DeviceAccess::setManualOwner(Channel::None);
    }
    void serviceManualTimeout()
    {
        Guard g;
        if (g.held && DeviceAccess::manualExpired() && plcSetManualMode(false))
            DeviceAccess::setManualOwner(Channel::None);
    }
    bool readEvents(uint32_t cursor, IoEventBatch &batch) { return plcReadEvents(cursor, batch); }
    void readActionValues(uint8_t rule, uint8_t action, ActionValues &result) { plcReadActionValues(rule, action, result); }
    bool readRules(uint8_t *counts, size_t capacity, size_t &count) { return plcReadRules(counts, capacity, count); }

    namespace
    {
        uint8_t programBuffer[PlcProgramStore::kMaxProgramSize];
        Channel uploadOwner = Channel::None, readOwner = Channel::None;
        uint32_t expectedSize = 0, expectedCRC = 0, received = 0, lastSeq = 0, lastMs = 0;
        size_t readSize = 0;
        bool hasSeq = false;
        void abortLocked()
        {
            plcAbortProgramming();
            uploadOwner = Channel::None;
            hasSeq = false;
            DeviceAccess::setLock(DeviceAccess::Lock::None, Channel::None);
        }
    }
    bool programActive()
    {
        Guard g;
        return !g.held || uploadOwner != Channel::None;
    }
    bool beginProgram(Channel channel, uint32_t size, uint32_t crc)
    {
        Guard g;
        if (!g.held || channel == Channel::None || !size || size > sizeof(programBuffer) ||
            (DeviceAccess::currentLock() != DeviceAccess::Lock::None && uploadOwner != channel))
            return false;
        if (!plcBeginProgramming())
            return false;
        readOwner = Channel::None;
        readSize = 0;
        uploadOwner = channel;
        expectedSize = size;
        expectedCRC = crc;
        received = 0;
        hasSeq = false;
        lastMs = millis();
        DeviceAccess::setLock(DeviceAccess::Lock::Program, channel);
        Serial.printf("PROGRAM_BEGIN: SIZE=%lu CRC=%08lX\n", (unsigned long)size, (unsigned long)crc);
        return true;
    }
    bool appendProgram(Channel channel, uint32_t seq, const uint8_t *data, size_t size)
    {
        Guard g;
        if (!g.held || channel == Channel::None || uploadOwner != channel)
            return false;
        if (hasSeq && seq == lastSeq)
            return true;
        if (!data || size > expectedSize - received)
        {
            abortLocked();
            return false;
        }
        memcpy(programBuffer + received, data, size);
        received += size;
        lastSeq = seq;
        hasSeq = true;
        lastMs = millis();
        Serial.printf("PROGRAM_DATA: RECEIVED=%lu/%lu\n", (unsigned long)received, (unsigned long)expectedSize);
        return true;
    }
    bool finishProgram(Channel channel)
    {
        Guard g;
        if (!g.held || channel == Channel::None || uploadOwner != channel)
            return false;
        bool ok = false;
        do
        {
            if (received != expectedSize || LynraProtocol::calculateCRC32(programBuffer, received) != expectedCRC)
                break;
            Serial.println("PROGRAM_END: CRC OK");
            JsonDocument doc;
            if (deserializeJson(doc, programBuffer, received))
                break;
            ControlProgram program;
            if (!program.fromJson(doc.as<JsonVariantConst>()))
                break;
            String error;
            if (!program.validate(error))
                break;
            Serial.println("PROGRAM VALIDATION OK");
            Serial.printf(
                "HEAP: free=%u largest=%u min=%u\n",
                ESP.getFreeHeap(),
                ESP.getMaxAllocHeap(),
                ESP.getMinFreeHeap());
            if (!plcPreflightProgram(program) || !PlcProgramStore::prepare(programBuffer, received) || !PlcProgramStore::commit())
                break;
            Serial.println("PROGRAM FLASH COMMIT OK");
            ok = plcLoadProgram(program) && plcFinishProgramming();
        } while (false);
        if (!ok)
        {
            Serial.println("PROGRAM END FAILED - STOP");
            abortLocked();
        }
        else
        {
            uploadOwner = Channel::None;
            hasSeq = false;
            DeviceAccess::setLock(DeviceAccess::Lock::None, Channel::None);
            Serial.println("PROGRAM ACTIVATED");
        }
        return ok;
    }
    void abortProgram(Channel channel)
    {
        Guard g;
        if (g.held && channel != Channel::None && uploadOwner == channel)
            abortLocked();
    }
    void serviceProgramTimeout()
    {
        Guard g;
        if (g.held && uploadOwner != Channel::None && uint32_t(millis() - lastMs) > 10000)
        {
            abortLocked();
            Serial.println("PROGRAM TRANSFER TIMEOUT");
        }
    }
    void clearProgramRead(Channel channel)
    {
        Guard g;
        if (g.held && readOwner == channel)
        {
            readOwner = Channel::None;
            readSize = 0;
        }
    }
    bool programInfo(Channel channel, uint32_t &size, uint32_t &crc)
    {
        Guard g;
        size = crc = 0;
        if (!g.held || channel == Channel::None || DeviceAccess::currentLock() != DeviceAccess::Lock::None)
            return false;
        readOwner = channel;
        readSize = 0;
        if (PlcProgramStore::load(programBuffer, sizeof(programBuffer), readSize))
        {
            size = readSize;
            crc = LynraProtocol::calculateCRC32(programBuffer, readSize);
        }
        return true;
    }
    size_t programChunk(Channel channel, uint32_t offset, uint8_t *dest, size_t capacity)
    {
        Guard g;
        if (!g.held || channel == Channel::None || readOwner != channel || DeviceAccess::currentLock() != DeviceAccess::Lock::None || !dest || offset >= readSize)
            return 0;
        size_t n = readSize - offset;
        if (n > capacity)
            n = capacity;
        memcpy(dest, programBuffer + offset, n);
        return n;
    }
}
