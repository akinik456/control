#include "device_license.h"
#include <Arduino.h>
#include <Preferences.h>
#include "license_public_key.h"
#include <esp_mac.h>
#include <mbedtls/ecdsa.h>
#include <mbedtls/sha256.h>
#include <mbedtls/base64.h>

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

    String code = prefs.getString("wifiCode", "");

    prefs.end();

    if (!code.isEmpty())
    {
        wifiEnabled =
            DeviceLicense_VerifyWifiCode(code.c_str());
    }

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

bool DeviceLicense_VerifyWifiCode(const char *code)
{
    if (!code || strlen(code) != 86)
        return false;

    // Base64URL -> Base64
    char base64[89];

    for (size_t i = 0; i < 86; i++)
    {
        char c = code[i];

        if (c == '-')
            c = '+';
        else if (c == '_')
            c = '/';
        else if (!((c >= 'A' && c <= 'Z') ||
                   (c >= 'a' && c <= 'z') ||
                   (c >= '0' && c <= '9')))
            return false;

        base64[i] = c;
    }

    base64[86] = '=';
    base64[87] = '=';
    base64[88] = '\0';

    // Decode R + S
    uint8_t signature[64];
    size_t signatureLength = 0;

    if (mbedtls_base64_decode(
            signature,
            sizeof(signature),
            &signatureLength,
            reinterpret_cast<const unsigned char *>(base64),
            88) != 0)
        return false;

    if (signatureLength != 64)
        return false;

    // Read physical device ID
    uint8_t mac[6];

    if (esp_efuse_mac_get_default(mac) != ESP_OK)
        return false;

    char message[64];

    snprintf(
        message,
        sizeof(message),
        "LYNRACONTROL|V1|%02X%02X%02X%02X%02X%02X|WIFI",
        mac[0], mac[1], mac[2],
        mac[3], mac[4], mac[5]);

    // SHA-256
    uint8_t hash[32];

    if (mbedtls_sha256_ret(
            reinterpret_cast<const unsigned char *>(message),
            strlen(message),
            hash,
            0) != 0)
        return false;

    // ECDSA P-256
    mbedtls_ecp_group group;
    mbedtls_ecp_point publicKey;
    mbedtls_mpi r;
    mbedtls_mpi s;

    mbedtls_ecp_group_init(&group);
    mbedtls_ecp_point_init(&publicKey);
    mbedtls_mpi_init(&r);
    mbedtls_mpi_init(&s);

    bool valid =
        mbedtls_ecp_group_load(
            &group,
            MBEDTLS_ECP_DP_SECP256R1) == 0 &&

        mbedtls_ecp_point_read_string(
            &publicKey,
            16,
            LicensePublicKey::X,
            LicensePublicKey::Y) == 0 &&

        mbedtls_ecp_check_pubkey(
            &group,
            &publicKey) == 0 &&

        mbedtls_mpi_read_binary(
            &r, signature, 32) == 0 &&

        mbedtls_mpi_read_binary(
            &s, signature + 32, 32) == 0 &&

        mbedtls_ecdsa_verify(
            &group,
            hash,
            sizeof(hash),
            &publicKey,
            &r,
            &s) == 0;

    mbedtls_mpi_free(&s);
    mbedtls_mpi_free(&r);
    mbedtls_ecp_point_free(&publicKey);
    mbedtls_ecp_group_free(&group);

    return valid;
}

bool DeviceLicense_SaveWifiCode(const char *code)
{
    if (!DeviceLicense_VerifyWifiCode(code))
        return false;

    Preferences prefs;

    if (!prefs.begin("license", false))
        return false;

    const size_t written =
        prefs.putString("wifiCode", code);

    prefs.end();

    if (written != 86)
        return false;

    return true;
}