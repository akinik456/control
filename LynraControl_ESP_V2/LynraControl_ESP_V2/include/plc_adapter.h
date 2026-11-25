
#pragma once

#include <Arduino.h>
#include <vector>

#include "models/control_program.h"
#include "plc_native/lynra_PLC_engine.h"

bool plcConvertProgram(
    const ControlProgram &program,
    std::vector<LynraRule> &rules,
    String &error);
