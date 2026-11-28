#pragma once

bool wifiInterfaceInit();
void wifiInterfaceConfigChanged();

#include <stdint.h>

enum class WifiState : uint8_t
{
    Disabled = 0,
    NotConfigured = 1,
    Connecting = 2,
    Connected = 3,
    FirebaseReady = 4,
    CloudOnline = 5,
    TaskError = 6
};

WifiState wifiInterfaceGetState();