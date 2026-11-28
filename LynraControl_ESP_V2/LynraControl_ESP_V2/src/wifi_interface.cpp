#include <Arduino.h>
#include <WiFi.h>
#include "wifi_interface.h"
#include "wifi_config_store.h"
#include "firebase_session.h"
#include "firebase_live_publisher.h"
#include "device_license.h"

namespace
{

    void wifiTask(void *parameter)
    {
        WifiConfig config{};

if (!WifiConfig_Load(config))
{
    Serial.println("[WIFI] NOT CONFIGURED");
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

    return xTaskCreate(
               wifiTask,
               "wifiTask",
               16384,
               nullptr,
               1,
               nullptr) == pdPASS;
}