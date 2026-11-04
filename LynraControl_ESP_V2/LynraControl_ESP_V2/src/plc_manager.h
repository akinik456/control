#pragma once
#include <Arduino.h>
#include "models/control_program.h"

bool plcInit();
void plcLoop();

bool plcRun();
void plcStop();

uint8_t plcGetStatus();

bool plcLoadProgram(const ControlProgram &program);

bool plcBeginProgramming();
void plcAbortProgramming();
bool plcFinishProgramming();