#pragma once

struct WifiConfig
{
    char ssid[33];
    char password[64];
};

bool WifiConfig_Load(WifiConfig &config);

bool WifiConfig_Save(
    const char *ssid,
    const char *password);