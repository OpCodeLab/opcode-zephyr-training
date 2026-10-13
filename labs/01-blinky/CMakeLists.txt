cmake_minimum_required(VERSION 3.20.0)

# Students flash/debug through the ST-Link with OpenOCD (STM32CubeProgrammer is
# the board default but is not installed in WSL).
set(BOARD_FLASH_RUNNER openocd CACHE STRING "")
set(BOARD_DEBUG_RUNNER openocd CACHE STRING "")

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(blinky)

target_sources(app PRIVATE src/main.c)
