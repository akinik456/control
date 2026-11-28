#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

#include "firebase_live_publisher.h"
#include "firebase_session.h"
#include "wifi_config.h"
#include "device_api.h"

namespace
{
    constexpr uint32_t PUBLISH_INTERVAL = 5000;
    uint32_t lastPublish = 0;
		bool publishSuccess = false;
uint32_t lastSuccess = 0;
}

void FirebaseLivePublisher_Poll()
{
    if (WiFi.status() != WL_CONNECTED)
        return;

    const String &uid = FirebaseSession_Uid();
    const String &token = FirebaseSession_IdToken();

    if (uid.isEmpty() || token.isEmpty())
        return;

    const uint32_t now = millis();

    if (now - lastPublish < PUBLISH_INTERVAL)
        return;

    lastPublish = now;

    DeviceApi::LiveSnapshot snapshot{};

    if (!DeviceApi::readLiveSnapshot(snapshot))
        return;

    JsonDocument doc;

    doc["state"] = snapshot.state;
    doc["inputs"] = snapshot.inputs;
    doc["outputs"] = snapshot.outputs;
    doc["manual"] = snapshot.manual;
    doc["uptimeMs"] = snapshot.uptimeMs;
    doc["lastSeen"][".sv"] = "timestamp";

    String body;
    serializeJson(doc, body);

    String url =
        String(FIREBASE_RTDB_URL) +
        "/devices/" + uid +
        ".json?auth=" + token;

    WiFiClientSecure client;
    client.setInsecure(); // Gecici test

    HTTPClient http;

    if (!http.begin(client, url))
{
    publishSuccess = false;
    return;
}

    http.setConnectTimeout(5000);
    http.setTimeout(5000);

    http.addHeader("Content-Type", "application/json");

    const int httpCode = http.PATCH(body);
		publishSuccess = (httpCode == 200);

if (publishSuccess)
    lastSuccess = millis();

    Serial.printf(
        "[LIVE CLOUD] HTTP=%d STATE=%u IN=%08lX OUT=%08lX\n",
        httpCode,
        snapshot.state,
        (unsigned long)snapshot.inputs,
        (unsigned long)snapshot.outputs);

    http.end();
}
bool FirebaseLivePublisher_IsHealthy()
{
    return publishSuccess &&
           (millis() - lastSuccess < 15000UL);
}

void FirebaseLivePublisher_ResetStatus()
{
    publishSuccess = false;
    lastSuccess = 0;
}