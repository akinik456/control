
cmake_minimum_required(VERSION 3.16)

project(LynraPLC C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_library(lynra_PLC_engine SHARED
    lynra_PLC_engine.c
)

target_compile_options(lynra_PLC_engine PRIVATE
    -Wall
    -Wextra
)


if(NOT ANDROID)
    add_executable(test_threshold_trigger test_threshold_trigger.c)
    target_link_libraries(test_threshold_trigger PRIVATE lynra_PLC_engine)
endif()

