
#pragma once

#include <Arduino.h>
#include <ArduinoJson.h>
#include <vector>

#include "control_block.h"

// Flutter: models/control_program.dart
struct ControlProgram
{
    String name;
    std::vector<ControlBlock> controlBlocks;
    bool fromJson(JsonVariantConst json);
    bool validate(String &error) const;
};
