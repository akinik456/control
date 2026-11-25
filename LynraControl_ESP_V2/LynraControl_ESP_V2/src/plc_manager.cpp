#include "plc_manager.h"
#include "plc_native/lynra_PLC_engine.h"

#include <Arduino.h>
#include <esp_timer.h>
#include "plc_adapter.h"
#include <vector>

static LynraPlcEngine *nativeEngine = nullptr;
static SemaphoreHandle_t plcMutex = nullptr;

enum class PlcState
{
    Stop,
    Programming,
    Run
};

static PlcState plcState = PlcState::Stop;
static bool programLoaded = false;

static constexpr uint8_t INPUT_PINS[4] = {32, 33, 25, 26};
static constexpr uint8_t OUTPUT_PINS[4] = {16, 17, 18, 19};

static bool manualMode = false;
static uint32_t bleInputs = 0;
static uint32_t effectiveInputsLocked() {
    if (manualMode) return bleInputs;
    uint32_t mask = 0;
    for (int i = 0; i < 4; ++i)
        if (digitalRead(INPUT_PINS[i]) == HIGH) mask |= 1UL << i;
    return mask;
}
bool plcSetManualMode(bool enabled) {
    if (!plcMutex || xSemaphoreTake(plcMutex, portMAX_DELAY) != pdTRUE) return false;
    manualMode = enabled;
    xSemaphoreGive(plcMutex);
    return true;
}
bool plcSetManualInput(uint8_t index, bool on) {
    if (index >= 4 || !plcMutex || xSemaphoreTake(plcMutex, portMAX_DELAY) != pdTRUE) return false;
    const bool accepted = manualMode;
    if (accepted) {
        if (on) bleInputs |= 1UL << index;
        else bleInputs &= ~(1UL << index);
    }
    xSemaphoreGive(plcMutex);
    return accepted;
}

using DeviceData::IoEvent;
static IoEvent ioRing[256];
static uint32_t ioNext = 1;
static uint32_t ioCount = 0;
static_assert(sizeof(IoEvent) == 16, "IO event size");

// Caller holds plcMutex. Capture effective inputs and actual outputs.
static void recordIoLocked()
{
    IoEvent e = {static_cast<uint64_t>(esp_timer_get_time()) / 1000, 0, 0};
    e.inputs = effectiveInputsLocked();
    for (int i = 0; i < 4; ++i) {
        if (digitalRead(OUTPUT_PINS[i]) == HIGH) e.outputs |= 1UL << i;
    }
    if (ioCount) {
        const IoEvent &last = ioRing[(ioNext - 2) & 255];
        if (last.inputs == e.inputs && last.outputs == e.outputs) return;
    }
    ioRing[(ioNext - 1) & 255] = e;
    ++ioNext;
    if (ioCount < 256) ++ioCount;
}

bool plcReadEvents(uint32_t cursor, DeviceData::IoEventBatch &batch)
{
    if (!plcMutex || xSemaphoreTake(plcMutex, pdMS_TO_TICKS(10)) != pdTRUE) return false;
    recordIoLocked();
    const uint32_t oldest = ioNext - ioCount;
    batch.first = cursor == 0 ? ioNext - 1 : cursor;
    batch.lost = cursor != 0 && (ioNext - cursor > ioCount);
    if (batch.lost) batch.first = oldest;
    const uint32_t available = ioNext - batch.first;
    batch.count = available > 10 ? 10 : static_cast<uint8_t>(available);
    for (uint8_t j = 0; j < batch.count; ++j)
        batch.records[j] = ioRing[(batch.first + j - 1) & 255];
    xSemaphoreGive(plcMutex);
    return true;
}

bool plcInit()
{
    plcMutex = xSemaphoreCreateMutex();

    if (plcMutex == nullptr)
    {
        Serial.println("PLC MUTEX CREATE FAILED");
        return false;
    }
    nativeEngine = lynra_plc_create();

    if (nativeEngine == nullptr)
    {
        Serial.println("NATIVE ENGINE CREATE FAILED");
        return false;
    }

    for (int i = 0; i < 4; ++i)
    {
        digitalWrite(OUTPUT_PINS[i], LOW);
        pinMode(OUTPUT_PINS[i], OUTPUT);
        pinMode(INPUT_PINS[i], INPUT_PULLDOWN);
    }

    Serial.println("PLC ENGINE AND GPIO READY");
    return true;
}
bool plcRun()
{
    if (plcMutex == nullptr)
        return false;

    if (xSemaphoreTake(plcMutex, pdMS_TO_TICKS(1000)) != pdTRUE)
    {
        Serial.println("PLC RUN: MUTEX TIMEOUT");
        return false;
    }

    bool success = false;

    if (nativeEngine != nullptr &&
        programLoaded &&
        plcState != PlcState::Programming)
    {
        lynra_plc_reset(nativeEngine);
        plcState = PlcState::Run;

        Serial.println("PLC STATE: RUN");
        success = true;
    }
    else
    {
        Serial.println("PLC RUN REJECTED");
    }

    xSemaphoreGive(plcMutex);

    return success;
}
void plcStop()
{
    if (plcMutex == nullptr)
        return;

    if (xSemaphoreTake(plcMutex, pdMS_TO_TICKS(1000)) != pdTRUE)
    {
        Serial.println("PLC STOP: MUTEX TIMEOUT");
        return;
    }

    plcState = PlcState::Stop;

    if (nativeEngine != nullptr)
        lynra_plc_reset(nativeEngine);

    for (int i = 0; i < 4; ++i)
        digitalWrite(OUTPUT_PINS[i], LOW);

    recordIoLocked();
    xSemaphoreGive(plcMutex);

    Serial.println("PLC STATE: STOP");
}
void plcLoop()
{
    if (plcMutex == nullptr)
        return;

    if (xSemaphoreTake(plcMutex, pdMS_TO_TICKS(10)) != pdTRUE)
        return;

    if (nativeEngine != nullptr && plcState == PlcState::Run)
    {
        const uint32_t inputMask = effectiveInputsLocked();

        lynra_plc_scan(nativeEngine, millis(), inputMask);

        const uint32_t outputMask =
            lynra_plc_get_outputs(nativeEngine);

        static uint32_t lastLog = 0;
        if (millis() - lastLog >= 1000)
        {
            lastLog = millis();
            Serial.printf("PLC DEBUG: IN=%08lX OUT=%08lX\n",
                          (unsigned long)inputMask,
                          (unsigned long)outputMask);
        }

        for (int i = 0; i < 4; ++i)
        {
            digitalWrite(
                OUTPUT_PINS[i],
                (outputMask & (1UL << i)) ? HIGH : LOW);
        }
    }

    recordIoLocked();
    xSemaphoreGive(plcMutex);
}
uint8_t plcGetStatus()
{
    switch (plcState)
    {
    case PlcState::Stop:
        return 0;
    case PlcState::Programming:
        return 1;
    case PlcState::Run:
        return 2;
    }
    return 0;
}
// Validate adapter output and C-engine limits without changing the active engine.
bool plcPreflightProgram(const ControlProgram &program)
{
    String error;
    std::vector<LynraRule> rules;
    if (!plcConvertProgram(program, rules, error))
    {
        Serial.printf("PLC PREFLIGHT FAILED: %s\n", error.c_str());
        return false;
    }
    if (plcMutex == nullptr ||
        xSemaphoreTake(plcMutex, pdMS_TO_TICKS(1000)) != pdTRUE)
        return false;
    const bool ready = nativeEngine != nullptr &&
                       plcState == PlcState::Programming;
    xSemaphoreGive(plcMutex);
    return ready;
}

bool plcLoadProgram(const ControlProgram &program)
{
    String error;
    std::vector<LynraRule> rules;

    if (!plcConvertProgram(program, rules, error))
    {
        Serial.printf("PLC ADAPTER ERROR: %s\n", error.c_str());
        return false;
    }

    if (plcMutex == nullptr)
        return false;

    if (xSemaphoreTake(plcMutex, pdMS_TO_TICKS(1000)) != pdTRUE)
    {
        Serial.println("PLC MUTEX TIMEOUT");
        return false;
    }

    bool success = false;

    if (nativeEngine != nullptr)
    {
        success = lynra_plc_load_rules(
            nativeEngine, rules.data(), rules.size());

        if (success)
        {
            programLoaded = true;

            Serial.printf("PLC PROGRAM LOADED: %u rules\n",
                          (unsigned)rules.size());
        }
        else
        {
            Serial.println("PLC LOAD FAILED");
        }
    }

    xSemaphoreGive(plcMutex);

    return success;
}
bool plcBeginProgramming()
{
    if (plcMutex == nullptr)
        return false;

    if (xSemaphoreTake(plcMutex, pdMS_TO_TICKS(1000)) != pdTRUE)
    {
        Serial.println("PLC BEGIN PROGRAMMING: MUTEX TIMEOUT");
        return false;
    }

    bool success = false;

    if (nativeEngine != nullptr)
    {
        plcState = PlcState::Programming;

        for (int i = 0; i < 4; ++i)
            digitalWrite(OUTPUT_PINS[i], LOW);

        Serial.println("PLC STATE: PROGRAMMING");
        success = true;
    }

    recordIoLocked();
    xSemaphoreGive(plcMutex);

    return success;
}
void plcAbortProgramming()
{
    if (plcMutex == nullptr)
        return;

    if (xSemaphoreTake(plcMutex, pdMS_TO_TICKS(1000)) != pdTRUE)
    {
        Serial.println("PLC ABORT: MUTEX TIMEOUT");
        return;
    }

    if (plcState == PlcState::Programming)
    {
        plcState = PlcState::Stop;

        if (nativeEngine != nullptr)
            lynra_plc_reset(nativeEngine);

        for (int i = 0; i < 4; ++i)
            digitalWrite(OUTPUT_PINS[i], LOW);

        Serial.println("PLC PROGRAMMING ABORTED - STATE: STOP");
    }

    recordIoLocked();
    xSemaphoreGive(plcMutex);
}
bool plcFinishProgramming()
{
    if (plcMutex == nullptr)
        return false;

    if (xSemaphoreTake(plcMutex, pdMS_TO_TICKS(1000)) != pdTRUE)
    {
        Serial.println("PLC FINISH: MUTEX TIMEOUT");
        return false;
    }

    bool success = false;

    if (nativeEngine != nullptr &&
        plcState == PlcState::Programming &&
        programLoaded)
    {
        lynra_plc_reset(nativeEngine);
        plcState = PlcState::Run;

        Serial.println("PLC STATE: RUN");
        success = true;
    }

    xSemaphoreGive(plcMutex);

    return success;
}

bool plcReadIo(uint32_t &inputs, uint32_t &outputs, bool &manual)
{
    if (!plcMutex || xSemaphoreTake(plcMutex, pdMS_TO_TICKS(10)) != pdTRUE)
        return false;
    inputs = effectiveInputsLocked();
    outputs = 0;
    manual = manualMode;
    for (int i = 0; i < 4; ++i)
    {
        if (digitalRead(OUTPUT_PINS[i]) == HIGH) outputs |= (1UL << i);
    }
    xSemaphoreGive(plcMutex);
    return true;
}

// Read one action's diagnostic values without changing engine state.
void plcReadActionValues(uint8_t rule, uint8_t action, DeviceData::ActionValues &result)
{
    result = {};
    result.status = 1;
    if (!plcMutex || xSemaphoreTake(plcMutex, pdMS_TO_TICKS(10)) != pdTRUE) return;
    LynraActionType type;
    LynraValues values;
    if (nativeEngine && programLoaded && plcState != PlcState::Programming &&
        lynra_plc_get_action_info(nativeEngine, rule, action, &type, nullptr)) {
        result.type = static_cast<uint8_t>(type);
        result.status = 2;
        if (lynra_plc_get_values(nativeEngine, rule, action, &values) && values.count <= 22) {
            result.status = 0;
            result.count = static_cast<uint8_t>(values.count);
            for (size_t i = 0; i < values.count; ++i) {
                result.items[i].id = static_cast<uint8_t>(values.items[i].id);
                result.items[i].value = values.items[i].value;
            }
        }
    }
    xSemaphoreGive(plcMutex);
}
