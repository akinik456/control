#include "wifi_config_store.h"
#include <Preferences.h>
#include <string.h>

bool WifiConfig_Load(WifiConfig &config)
{
    config = {};

    Preferences prefs;

    if (!prefs.begin("wifi", true))
        return false;

    WifiConfig stored{};

    size_t length = prefs.getBytes(
        "config",
        &stored,
        sizeof(stored));

    prefs.end();

    if (length != sizeof(stored))
        return false;

    if (stored.ssid[0] == '\0' ||
        stored.ssid[32] != '\0' ||
        stored.password[63] != '\0')
        return false;

    config = stored;

    return true;
}

bool WifiConfig_Save(
    const char *ssid,
    const char *password)
{
    if (!ssid || !password)
        return false;

    size_t ssidLength = strlen(ssid);
    size_t passwordLength = strlen(password);

    if (ssidLength == 0 ||
        ssidLength > 32 ||
        passwordLength > 63)
        return false;

    WifiConfig config{};

    memcpy(config.ssid, ssid, ssidLength);
    memcpy(config.password, password, passwordLength);

    Preferences prefs;

    if (!prefs.begin("wifi", false))
        return false;

    size_t written = prefs.putBytes(
        "config",
        &config,
        sizeof(config));

    prefs.end();

    return written == sizeof(config);
}