#include <Arduino.h>
#include <WiFi.h>
#include "wifi_interface.h"
#include "wifi_config_store.h"
#include "firebase_session.h"
#include "firebase_live_publisher.h"
#include "device_license.h"
#include <atomic>
#include <string.h>

namespace
{
std::atomic<bool> wifiTaskStarted{false};
std::atomic<bool> wifiConfigChanged{false};
    void wifiTask(void *parameter)
    {
 
WifiConfig config{};

if (!WifiConfig_Load(config))
{
    Serial.println("[WIFI] NOT CONFIGURED");
    wifiTaskStarted = false;
    vTaskDelete(nullptr);
    return;
}

WiFi.mode(WIFI_STA);
WiFi.setAutoReconnect(true);
WiFi.begin(config.ssid, config.password);

        bool wasConnected = false;
        uint32_t lastRetry = millis();

        Serial.println("[WIFI] Connecting...");

        for (;;)
        {
					if (wifiConfigChanged.exchange(false))
{
    WifiConfig newConfig{};

    if (WifiConfig_Load(newConfig))
    {
        if (strcmp(config.ssid, newConfig.ssid) != 0 ||
            strcmp(config.password, newConfig.password) != 0)
        {
            Serial.println("[WIFI] CONFIG CHANGED");

            WiFi.setAutoReconnect(false);
            WiFi.disconnect(false, false);

            vTaskDelay(pdMS_TO_TICKS(250));

            config = newConfig;

            wasConnected = false;
            lastRetry = millis();

            WiFi.setAutoReconnect(true);
            WiFi.begin(config.ssid, config.password);

            Serial.println("[WIFI] Connecting...");

            vTaskDelay(pdMS_TO_TICKS(250));
            continue;
        }
    }
    else
    {
        Serial.println("[WIFI] CONFIG RELOAD FAILED");
        wifiConfigChanged = true;
    }
}
            const bool connected =
                WiFi.status() == WL_CONNECTED;

            if (connected != wasConnected)
            {
                wasConnected = connected;

                if (connected)
                {
                    Serial.println("[WIFI] Connected");
                    Serial.print("[WIFI] IP: ");
                    Serial.println(WiFi.localIP());

                    Serial.printf(
                        "[WIFI] Heap: %u, Largest: %u\n",
                        ESP.getFreeHeap(),
                        ESP.getMaxAllocHeap());
                }
                else
                {
                    Serial.println("[WIFI] Disconnected");
                }
            }

            if (!connected &&
                millis() - lastRetry >= 10000UL)
            {

                lastRetry = millis();

                Serial.println("[WIFI] Reconnecting...");
                WiFi.reconnect();
            }
						if (connected)
						{
								FirebaseSession_Poll();
								FirebaseLivePublisher_Poll();
						}

            vTaskDelay(pdMS_TO_TICKS(250));
						
        }
    }

}

bool wifiInterfaceInit()
{
    if (!DeviceLicense_IsWifiEnabled())
    {
        Serial.println("[WIFI] DISABLED BY LICENSE");
        return true;
    }

    if (wifiTaskStarted.load())
        return true;

    WifiConfig config{};

    if (!WifiConfig_Load(config))
    {
        Serial.println("[WIFI] NOT CONFIGURED");
        return true;
    }

    bool expected = false;

    if (!wifiTaskStarted.compare_exchange_strong(
            expected, true))
        return true;

    if (xTaskCreate(
            wifiTask,
            "wifiTask",
            16384,
            nullptr,
            1,
            nullptr) != pdPASS)
    {
        wifiTaskStarted = false;
        return false;
    }

    return true;
}
void wifiInterfaceConfigChanged()
{
    wifiConfigChanged = true;
}