
#pragma once

#include <Arduino.h>
#include <vector>

#include "control_block.h"

// Flutter: models/control_program.dart
struct ControlProgram
{
    String name;
    std::vector<ControlBlock> controlBlocks;
};
