#pragma once
#include "device_data.h"
#include <Arduino.h>
#include "models/control_program.h"

bool plcInit();
void plcLoop();

bool plcRun();
void plcStop();

uint8_t plcGetStatus();

bool plcLoadProgram(const ControlProgram &program);
bool plcPreflightProgram(const ControlProgram &program);

bool plcBeginProgramming();
void plcAbortProgramming();
bool plcFinishProgramming();
// Read effective inputs, actual outputs and manual mode.
bool plcReadIo(uint32_t &inputs, uint32_t &outputs, bool &manual);

bool plcSetManualMode (bool enabled);

bool plcSetManualInput(uint8_t index, bool on);

bool plcReadEvents(uint32_t cursor, DeviceData::IoEventBatch &batch);
void plcReadActionValues(uint8_t rule, uint8_t action, DeviceData::ActionValues &result);

bool plcReadRules(uint8_t *counts, size_t capacity, size_t &count);
