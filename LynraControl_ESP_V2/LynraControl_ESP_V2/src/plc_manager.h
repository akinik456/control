#pragma once
#include <Arduino.h>

bool plcInit();
void plcLoop();

bool plcRun();
void plcStop();

uint8_t plcGetStatus();