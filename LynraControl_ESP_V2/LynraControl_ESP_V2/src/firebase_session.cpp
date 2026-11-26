#include "firebase_session.h"
#include "wifi_config.h"
#include <ArduinoJson.h>
#include <Preferences.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>

namespace {
String firebaseUid;
String firebaseIdToken;
Preferences firebasePrefs;
String firebaseRefreshToken;
uint32_t lastFirebaseRefresh = 0;
constexpr uint32_t FIREBASE_REFRESH_INTERVAL = 50UL * 60UL * 1000UL;
}

bool Firebase_RefreshSession()
{
  firebasePrefs.begin("firebase", true);
  String savedRefreshToken =
      firebasePrefs.getString("refresh", "");
  firebasePrefs.end();

  if (savedRefreshToken.isEmpty())
    return false;

  WiFiClientSecure client;
  client.setInsecure(); // Geçici test

  HTTPClient http;

  String url =
      String("https://securetoken.googleapis.com/v1/token?key=") + FIREBASE_API_KEY;

  if (!http.begin(client, url))
    return false;

  http.addHeader(
      "Content-Type",
      "application/x-www-form-urlencoded");

  String body =
      "grant_type=refresh_token&refresh_token=" +
      savedRefreshToken;

  int httpCode = http.POST(body);

  Serial.printf("Firebase Refresh HTTP: %d\n", httpCode);

  bool success = false;

  if (httpCode == 200)
  {
    JsonDocument doc;

    if (deserializeJson(doc, http.getString()) ==
        DeserializationError::Ok)
    {
      String uid = doc["user_id"].as<String>();
      String idToken = doc["id_token"].as<String>();
      String newRefreshToken =
          doc["refresh_token"].as<String>();

      if (!uid.isEmpty() &&
          !idToken.isEmpty() &&
          !newRefreshToken.isEmpty())
      {
        firebaseUid = uid;
        firebaseIdToken = idToken;
        firebaseRefreshToken = newRefreshToken;

        firebasePrefs.begin("firebase", false);
        firebasePrefs.putString(
            "refresh", firebaseRefreshToken);
        firebasePrefs.putString("uid", firebaseUid);
        firebasePrefs.end();

        lastFirebaseRefresh = millis();
        Serial.println("Firebase session renewed");

        success = true;
      }
    }
  }

  http.end();
  return success;
}
bool Firebase_HasStoredIdentity()
{
  Preferences prefs;

  if (!prefs.begin("firebase", false))
    return true; // NVS okunamıyorsa yeni kimlik oluşturma

  bool exists =
      prefs.isKey("uid") ||
      prefs.isKey("refresh");

  prefs.end();

  return exists;
}

void FirebaseSession_Begin()
{
  if (WiFi.status() == WL_CONNECTED &&
      !Firebase_RefreshSession() &&
      !Firebase_HasStoredIdentity())
  {
    WiFiClientSecure client;
    client.setInsecure(); // Yalnızca ilk bağlantı testi için

    HTTPClient http;

    String url =
        String("https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=") + FIREBASE_API_KEY;

    if (http.begin(client, url))
    {
      http.addHeader("Content-Type", "application/json");

      int httpCode = http.POST(
          "{\"returnSecureToken\":true}");

      Serial.printf("Firebase Auth HTTP: %d\n", httpCode);

      if (httpCode == 200)
      {
        String response = http.getString();

        JsonDocument doc;
        DeserializationError error = deserializeJson(doc, response);

        if (!error)
        {
          firebaseUid = doc["localId"].as<String>();
          firebaseIdToken = doc["idToken"].as<String>();
          firebaseRefreshToken = doc["refreshToken"].as<String>();

          if (!firebaseUid.isEmpty() &&
              !firebaseIdToken.isEmpty() &&
              !firebaseRefreshToken.isEmpty())
          {
            firebasePrefs.begin("firebase", false);

            firebasePrefs.putString("uid", firebaseUid);
            firebasePrefs.putString("refresh", firebaseRefreshToken);

            firebasePrefs.end();
            lastFirebaseRefresh = millis();
            Serial.println("Firebase Auth OK");
            Serial.println("UID and refresh token saved to NVS");
          }
          else
          {
            Serial.println("Firebase Auth: missing fields");
          }
        }
        else
        {
          Serial.println("Firebase Auth: JSON parse error");
        }
      }
      else
      {
        Serial.printf(
            "HTTPS ERROR: %s\n",
            http.errorToString(httpCode).c_str());
      }

      http.end();
    }
    else
    {
      Serial.println("Firebase HTTPS begin failed");
    }
  }

}

void FirebaseSession_Poll()
{
    static uint32_t lastAttempt = 0;
    static bool attempted = false;

    if (WiFi.status() != WL_CONNECTED)
        return;

    const uint32_t now = millis();

    if (attempted && now - lastAttempt < 60000UL)
        return;

    if (!firebaseIdToken.isEmpty() &&
        now - lastFirebaseRefresh < FIREBASE_REFRESH_INTERVAL)
        return;

    attempted = true;
    lastAttempt = now;

    Serial.printf(
        "[FIREBASE] BEFORE: heap=%u largest=%u\n",
        ESP.getFreeHeap(),
        ESP.getMaxAllocHeap());

    FirebaseSession_Begin();

    Serial.printf(
        "[FIREBASE] AFTER: heap=%u largest=%u min=%u\n",
        ESP.getFreeHeap(),
        ESP.getMaxAllocHeap(),
        ESP.getMinFreeHeap());
}

const String& FirebaseSession_Uid() { return firebaseUid; }
const String& FirebaseSession_IdToken() { return firebaseIdToken; }
