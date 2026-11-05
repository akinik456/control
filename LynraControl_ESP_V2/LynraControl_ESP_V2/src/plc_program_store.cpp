#include "plc_program_store.h"
#include <Arduino.h>
#include <LittleFS.h>
#include <string.h>

namespace PlcProgramStore {
namespace {
constexpr char kSlotA[] = "/lynra_program_a.bin";
constexpr char kSlotB[] = "/lynra_program_b.bin";
constexpr char kPending[] = "/lynra_program_pending.bin";
constexpr uint32_t kMagic = 0x4C594E50UL;
constexpr uint32_t kFormat = 1;
struct Header {
  uint32_t magic;
  uint32_t format;
  uint32_t generation;
  uint32_t length;
  uint32_t crc;
};
static_assert(sizeof(Header) == 20, "Header layout changed");
bool mounted = false;
bool prepared = false;
uint32_t preparedGeneration = 0;

uint32_t crcUpdate(uint32_t crc, const uint8_t* data, size_t len) {
  for (size_t i = 0; i < len; ++i) {
    crc ^= data[i];
    for (unsigned bit = 0; bit < 8; ++bit)
      crc = (crc & 1U) ? ((crc >> 1) ^ 0xEDB88320UL) : (crc >> 1);
  }
  return crc;
}

bool inspect(const char* path, Header& header) {
  if (!mounted) return false;
  File f = LittleFS.open(path, "r");
  if (!f) return false;
  Header h{};
  bool ok = f.read(reinterpret_cast<uint8_t*>(&h), sizeof(h)) == sizeof(h);
  ok = ok && h.magic == kMagic && h.format == kFormat && h.generation != 0 &&
       h.length > 0 && h.length <= kMaxProgramSize &&
       f.size() == sizeof(h) + h.length;
  if (ok) {
    uint32_t crc = 0xFFFFFFFFUL;
    uint8_t buf[128];
    size_t left = h.length;
    while (left) {
      const size_t count = left < sizeof(buf) ? left : sizeof(buf);
      if (f.read(buf, count) != count) { ok = false; break; }
      crc = crcUpdate(crc, buf, count);
      left -= count;
    }
    ok = ok && ((crc ^ 0xFFFFFFFFUL) == h.crc);
  }
  f.close();
  if (ok) header = h;
  return ok;
}

struct Selected { const char* path; Header header; bool found; };
Selected latest() {
  Header a{}, b{};
  const bool va = inspect(kSlotA, a);
  const bool vb = inspect(kSlotB, b);
  if (!va && !vb) return {nullptr, {}, false};
  if (va && (!vb || a.generation >= b.generation)) return {kSlotA, a, true};
  return {kSlotB, b, true};
}
}

bool begin() {
  prepared = false;
  preparedGeneration = 0;
  mounted = LittleFS.begin(false);
  return mounted;
}

bool hasProgram() { return latest().found; }

bool prepare(const uint8_t* data, size_t length) {
  prepared = false;
  if (!mounted || !data || length == 0 || length > kMaxProgramSize) return false;
  const Selected old = latest();
  if (old.found && old.header.generation == UINT32_MAX) return false;
  const uint32_t generation = old.found ? old.header.generation + 1 : 1;
  const Header header{kMagic, kFormat, generation, static_cast<uint32_t>(length),
                      crcUpdate(0xFFFFFFFFUL, data, length) ^ 0xFFFFFFFFUL};
  if (LittleFS.exists(kPending) && !LittleFS.remove(kPending)) return false;
  File f = LittleFS.open(kPending, "w");
  if (!f) return false;
  const bool wrote =
      f.write(reinterpret_cast<const uint8_t*>(&header), sizeof(header)) == sizeof(header) &&
      f.write(data, length) == length;
  f.flush();
  f.close();
  Header check{};
  if (!wrote || !inspect(kPending, check) || check.generation != generation ||
      check.length != length || check.crc != header.crc) {
    LittleFS.remove(kPending);
    return false;
  }
  preparedGeneration = generation;
  prepared = true;
  return true;
}

bool commit() {
  if (!mounted || !prepared) return false;
  const Selected old = latest();
  const uint32_t expected = old.found ? old.header.generation + 1 : 1;
  Header pending{};
  if (expected != preparedGeneration || !inspect(kPending, pending) ||
      pending.generation != expected) return false;
  const char* target = old.found && strcmp(old.path, kSlotA) == 0 ? kSlotB : kSlotA;
  // Keep the currently selected slot untouched. A failed rename leaves it valid.
  if (LittleFS.exists(target) && !LittleFS.remove(target)) return false;
  if (!LittleFS.rename(kPending, target)) return false;
  prepared = false;
  Header written{};
  return inspect(target, written) && written.generation == expected &&
         written.length == pending.length && written.crc == pending.crc;
}

bool load(uint8_t* destination, size_t capacity, size_t& length) {
  length = 0;
  if (!mounted || !destination) return false;
  const Selected selected = latest();
  if (!selected.found || selected.header.length > capacity) return false;
  File f = LittleFS.open(selected.path, "r");
  if (!f || !f.seek(sizeof(Header))) { if (f) f.close(); return false; }
  const size_t read = f.read(destination, selected.header.length);
  f.close();
  if (read != selected.header.length) return false;
  if ((crcUpdate(0xFFFFFFFFUL, destination, read) ^ 0xFFFFFFFFUL) != selected.header.crc)
    return false;
  length = read;
  return true;
}
}
