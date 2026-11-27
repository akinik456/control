#include <Arduino.h>
#include <WiFi.h>
#include "wifi_interface.h"
#include "wifi_config.h"
#include "firebase_session.h"
#include "firebase_live_publisher.h"

namespace
{

    void wifiTask(void *parameter)
    {
        WiFi.mode(WIFI_STA);
        WiFi.setAutoReconnect(true);
        WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

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
    return xTaskCreate(
               wifiTask,
               "wifiTask",
               16384,
               nullptr,
               1,
               nullptr) == pdPASS;
}