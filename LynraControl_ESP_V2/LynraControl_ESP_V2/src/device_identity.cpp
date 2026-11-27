#include "device_identity.h"
#include <Preferences.h>
#include <esp_system.h>
#include <bootloader_random.h>

namespace
{
    String pairingCode;
}

bool DeviceIdentity_Init()
{
    Preferences prefs;

    if (!prefs.begin("identity", false))
        return false;

    String code = prefs.getString("pairCode", "");

    if (code.isEmpty())
    {
        const char alphabet[] =
            "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

        // Enable hardware entropy source before WiFi/BLE init.
        bootloader_random_enable();

        for (int i = 0; i < 16; i++)
        {
            if (i > 0 && i % 4 == 0)
                code += "-";

            code += alphabet[esp_random() % 32];
        }

        bootloader_random_disable();

        if (prefs.putString("pairCode", code) != code.length())
        {
            prefs.end();
            return false;
        }

        Serial.println("IDENTITY: PAIRING CODE CREATED");
    }
    else
    {
        Serial.println("IDENTITY: PAIRING CODE LOADED");
    }

    prefs.end();

    pairingCode = code;
    return true;
}

const String& DeviceIdentity_PairingCode()
{
    return pairingCode;
}