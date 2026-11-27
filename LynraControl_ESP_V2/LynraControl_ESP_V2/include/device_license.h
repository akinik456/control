#pragma once

#include <stdbool.h>

bool DeviceLicense_Init();
bool DeviceLicense_IsWifiEnabled();
bool DeviceLicense_VerifyWifiCode(const char *code);
bool DeviceLicense_SaveWifiCode(const char *code);