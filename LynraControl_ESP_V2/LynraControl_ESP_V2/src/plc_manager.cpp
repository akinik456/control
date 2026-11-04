#include "plc_manager.h"
#include "plc_native/lynra_PLC_engine.h"

#include <Arduino.h>

static LynraPlcEngine *nativeEngine = nullptr;

enum class PlcState
{
    Stop,
    Programming,
    Run
};

static PlcState plcState = PlcState::Stop;

static constexpr uint8_t INPUT_PINS[4] = {32, 33, 25, 26};
static constexpr uint8_t OUTPUT_PINS[4] = {16, 17, 18, 19};

bool plcInit()
{
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
    if (nativeEngine == nullptr)
        return false;

    if (plcState == PlcState::Programming)
        return false;

    lynra_plc_reset(nativeEngine);
    plcState = PlcState::Run;

    Serial.println("PLC STATE: RUN");
    return true;
}
void plcStop()
{
    plcState = PlcState::Stop;

    if (nativeEngine != nullptr)
        lynra_plc_reset(nativeEngine);

    for (int i = 0; i < 4; ++i)
        digitalWrite(OUTPUT_PINS[i], LOW);

    Serial.println("PLC STATE: STOP");
}
void plcLoop()
{
    if (nativeEngine == nullptr)
        return;

    if (plcState != PlcState::Run)
        return;

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
