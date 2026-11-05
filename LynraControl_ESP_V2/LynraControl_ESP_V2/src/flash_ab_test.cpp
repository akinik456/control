#include "flash_ab_test.h"

#include <Arduino.h>
#include <LittleFS.h>
#include <string.h>

namespace {
constexpr char kA[] = "/lynra_ab_test_a.bin";
constexpr char kB[] = "/lynra_ab_test_b.bin";
constexpr char kTmp[] = "/lynra_ab_test_tmp.bin";
constexpr uint32_t kMagic = 0x41424C59UL; // 'YLBA' marker
constexpr size_t kMaxData = 32768;
constexpr uint8_t kProgramA[] = "LYNRA_TEST_PROGRAM_A";
constexpr uint8_t kProgramB[] = "LYNRA_TEST_PROGRAM_B";

struct Header {
  uint32_t magic;
  uint32_t generation;
  uint32_t length;
  uint32_t crc;
};
static_assert(sizeof(Header) == 16, "Unexpected header layout");

uint32_t crc32(const uint8_t* data, size_t length) {
  uint32_t crc = 0xFFFFFFFFUL;
  for (size_t i = 0; i < length; ++i) {
    crc ^= data[i];
    for (uint8_t bit = 0; bit < 8; ++bit)
      crc = (crc & 1U) ? (crc >> 1) ^ 0xEDB88320UL : (crc >> 1);
  }
  return crc ^ 0xFFFFFFFFUL;
}

bool validSlot(const char* path, Header& out) {
  File f = LittleFS.open(path, "r");
  if (!f) return false;
  Header h{};
  bool ok = f.read(reinterpret_cast<uint8_t*>(&h), sizeof(h)) == sizeof(h);
  ok = ok && h.magic == kMagic && h.generation != 0 &&
       h.length > 0 && h.length <= kMaxData &&
       f.size() == sizeof(h) + h.length;
  if (ok) {
    uint32_t crc = 0xFFFFFFFFUL;
    uint8_t buf[128];
    uint32_t remaining = h.length;
    while (remaining) {
      const size_t n = remaining < sizeof(buf) ? remaining : sizeof(buf);
      if (f.read(buf, n) != n) { ok = false; break; }
      for (size_t i = 0; i < n; ++i) {
        crc ^= buf[i];
        for (uint8_t bit = 0; bit < 8; ++bit)
          crc = (crc & 1U) ? (crc >> 1) ^ 0xEDB88320UL : (crc >> 1);
      }
      remaining -= n;
    }
    ok = ok && ((crc ^ 0xFFFFFFFFUL) == h.crc);
  }
  f.close();
  if (ok) out = h;
  return ok;
}

struct Selection { const char* path; Header header; bool found; };

Selection latest() {
  Header a{}, b{};
  const bool va = validSlot(kA, a);
  const bool vb = validSlot(kB, b);
  if (!va && !vb) return {nullptr, {}, false};
  if (va && (!vb || a.generation >= b.generation)) return {kA, a, true};
  return {kB, b, true};
}

bool saveNext(const uint8_t* data, size_t len) {
  if (!data || len == 0 || len > kMaxData) return false;
  const Selection old = latest();
  if (old.found && old.header.generation == UINT32_MAX) return false;
  const char* target = !old.found || strcmp(old.path, kB) == 0 ? kA : kB;
  const Header header{kMagic, old.found ? old.header.generation + 1 : 1,
                      static_cast<uint32_t>(len), crc32(data, len)};
  // Temporary file is never considered an active program.
  LittleFS.remove(kTmp);
  File f = LittleFS.open(kTmp, "w");
  if (!f) return false;
  bool ok = f.write(reinterpret_cast<const uint8_t*>(&header), sizeof(header)) == sizeof(header);
  ok = ok && f.write(data, len) == len;
  f.flush();
  f.close();
  Header check{};
  ok = ok && validSlot(kTmp, check) && check.generation == header.generation;
  if (!ok) { LittleFS.remove(kTmp); return false; }
  // Old active slot is never removed. The inactive slot is replaced.
  if (LittleFS.exists(target) && !LittleFS.remove(target)) return false;
  if (!LittleFS.rename(kTmp, target)) return false;
  Header committed{};
  return validSlot(target, committed) && committed.generation == header.generation;
}

bool payloadEquals(const char* path, const uint8_t* data, size_t len) {
  File f = LittleFS.open(path, "r");
  if (!f || f.size() != sizeof(Header) + len) { if (f) f.close(); return false; }
  if (!f.seek(sizeof(Header))) { f.close(); return false; }
  uint8_t buf[64];
  if (len > sizeof(buf)) { f.close(); return false; }
  const bool ok = f.read(buf, len) == len && memcmp(buf, data, len) == 0;
  f.close();
  return ok;
}
} // namespace

void flashAbTestRun() {
  Serial.println("FLASH AB TEST: START");
  if (!LittleFS.begin(false)) {
    Serial.println("FLASH AB TEST: MOUNT FAILED - NO FORMAT");
    return;
  }
  Selection selected = latest();
  if (!selected.found) {
    // Fresh test: write A, then B into alternate slot.
    if (!saveNext(kProgramA, sizeof(kProgramA) - 1)) {
      Serial.println("FLASH AB TEST: SAVE A FAILED"); return;
    }
    if (!saveNext(kProgramB, sizeof(kProgramB) - 1)) {
      Serial.println("FLASH AB TEST: SAVE B FAILED"); return;
    }
    selected = latest();
    if (selected.found && selected.header.generation == 2 &&
        payloadEquals(selected.path, kProgramB, sizeof(kProgramB) - 1))
      Serial.println("FLASH AB TEST: A/B WRITE VERIFY PASS - RESET TO TEST PERSISTENCE");
    else
      Serial.println("FLASH AB TEST: A/B WRITE VERIFY FAILED");
    return;
  }
  Serial.printf("FLASH AB TEST: SELECTED %s GENERATION=%lu\n", selected.path,
                (unsigned long)selected.header.generation);
  if (strcmp(selected.path, kB) == 0 && selected.header.generation == 2) {
    Header a{};
    if (!validSlot(kA, a) || a.generation != 1 ||
        !payloadEquals(kA, kProgramA, sizeof(kProgramA) - 1)) {
      Serial.println("FLASH AB TEST: A BACKUP INVALID - NO CORRUPTION PERFORMED");
      return;
    }
    // One-shot fault injection: corrupt only B's stored CRC, never A.
    File f = LittleFS.open(kB, "r+");
    if (!f || !f.seek(offsetof(Header, crc))) {
      if (f) f.close();
      Serial.println("FLASH AB TEST: CORRUPT B OPEN/SEEK FAILED");
      return;
    }
    const uint32_t wrongCrc = selected.header.crc ^ 0xFFFFFFFFUL;
    const bool written = f.write(reinterpret_cast<const uint8_t*>(&wrongCrc),
                                 sizeof(wrongCrc)) == sizeof(wrongCrc);
    f.flush();
    f.close();
    if (!written) {
      Serial.println("FLASH AB TEST: CORRUPT B WRITE FAILED");
      return;
    }
    Header b{};
    const Selection recovered = latest();
    if (!validSlot(kB, b) && recovered.found &&
        strcmp(recovered.path, kA) == 0 && recovered.header.generation == 1 &&
        payloadEquals(kA, kProgramA, sizeof(kProgramA) - 1))
      Serial.println("FLASH AB TEST: CORRUPT B / FALLBACK A PASS - RESET ESP32");
    else
      Serial.println("FLASH AB TEST: CORRUPT B / FALLBACK A FAILED");
    return;
  }
  if (strcmp(selected.path, kA) == 0 && selected.header.generation == 1) {
    Header b{};
    if (!validSlot(kB, b) &&
        payloadEquals(kA, kProgramA, sizeof(kProgramA) - 1))
      Serial.println("FLASH AB TEST: REBOOT FALLBACK A PASS");
    else
      Serial.println("FLASH AB TEST: REBOOT FALLBACK A FAILED");
    return;
  }
  if (selected.header.generation == 2 &&
      payloadEquals(selected.path, kProgramB, sizeof(kProgramB) - 1))
    Serial.println("FLASH AB TEST: REBOOT PERSISTENCE PASS");
  else
    Serial.println("FLASH AB TEST: EXISTING TEST SLOTS - NOT OVERWRITTEN");
}
