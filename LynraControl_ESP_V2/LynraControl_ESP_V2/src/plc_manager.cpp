#include "plc_manager.h"
#include "plc_native/lynra_PLC_engine.h"

#include <Arduino.h>
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
        uint32_t inputMask = 0;

        for (int i = 0; i < 4; ++i)
        {
            if (digitalRead(INPUT_PINS[i]) == HIGH)
                inputMask |= (1UL << i);
        }

        lynra_plc_scan(nativeEngine, millis(), inputMask);

        const uint32_t outputMask =
            lynra_plc_get_outputs(nativeEngine);

        for (int i = 0; i < 4; ++i)
        {
            digitalWrite(
                OUTPUT_PINS[i],
                (outputMask & (1UL << i)) ? HIGH : LOW);
        }
    }

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