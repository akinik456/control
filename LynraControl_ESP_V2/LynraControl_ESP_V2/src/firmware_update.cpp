#include "firmware_update.h"
#include <esp_ota_ops.h>

// Call from one serialized execution context only.
// Prototype: validates image structure, not publisher authenticity.
namespace FirmwareUpdate {
namespace {
const esp_partition_t* target = nullptr;
esp_ota_handle_t handle = 0;
size_t expected = 0;
size_t written = 0;
bool opened = false;
void clear() {
    target = nullptr;
    handle = 0;
    expected = written = 0;
    opened = false;
}
}

bool active() { return opened; }
size_t received() { return written; }

esp_err_t begin(size_t imageSize) {
    if (opened) return ESP_ERR_INVALID_STATE;
    const esp_partition_t* p = esp_ota_get_next_update_partition(nullptr);
    if (!p) return ESP_ERR_NOT_FOUND;
    if (!imageSize || imageSize > p->size) return ESP_ERR_INVALID_SIZE;
    esp_ota_handle_t h = 0;
    esp_err_t err = esp_ota_begin(p, imageSize, &h);
    if (err != ESP_OK) return err;
    target = p;
    handle = h;
    expected = imageSize;
    written = 0;
    opened = true;
    return ESP_OK;
}

void abort() {
    if (opened) esp_ota_abort(handle);
    clear();
}

esp_err_t write(size_t offset, const uint8_t* data, size_t length) {
    if (!opened) return ESP_ERR_INVALID_STATE;
    if (!data || !length || offset != written || length > expected - written)
        return ESP_ERR_INVALID_ARG;
    esp_err_t err = esp_ota_write(handle, data, length);
    if (err != ESP_OK) { abort(); return err; }
    written += length;
    return ESP_OK;
}

esp_err_t finish() {
    if (!opened) return ESP_ERR_INVALID_STATE;
    if (written != expected) return ESP_ERR_INVALID_SIZE;
    const esp_partition_t* p = target;
    esp_err_t err = esp_ota_end(handle);
    clear(); // esp_ota_end consumes the handle even on failure.
    if (err != ESP_OK) return err;
    // Prototype only: production must verify signature and hardware ID first.
    return esp_ota_set_boot_partition(p);
}
}
