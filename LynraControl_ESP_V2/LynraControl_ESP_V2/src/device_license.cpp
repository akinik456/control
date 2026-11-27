#include "device_license.h"
#include <Arduino.h>
#include <Preferences.h>

namespace
{
    bool wifiEnabled = false;
}

bool DeviceLicense_Init()
{
    wifiEnabled = false;

    Preferences prefs;

    if (!prefs.begin("license", false))
        return false;

    wifiEnabled = prefs.getBool("wifiEnabled", false);

    prefs.end();

    Serial.printf(
        "LICENSE: WIFI %s\n",
        wifiEnabled ? "ENABLED" : "DISABLED"
    );

    return true;
}

bool DeviceLicense_IsWifiEnabled()
{
    return wifiEnabled;
}