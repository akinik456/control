#pragma once
#include <stddef.h>
#include <stdint.h>
#include <esp_err.h>

namespace FirmwareUpdate {
esp_err_t begin(size_t imageSize);
esp_err_t write(size_t offset, const uint8_t* data, size_t length);
esp_err_t finish();
void abort();
bool active();
size_t received();
}
