#!/usr/bin/env bash
# Build one lab and put the board's OpenOCD config next to the ELF, so the
# VS Code debug configs do not need to ask for the board again.
#
# Usage: scripts/build_lab.sh <app_dir> <build_dir> <board> [extra west build args]
#   e.g. scripts/build_lab.sh labs_rtos/01-multitask build/rtos/01-multitask stm32f4_disco
set -euo pipefail

app=$1
build=$2
board=$3
shift 3

cd "$(dirname "$0")/.."
source ../env.sh

# west refuses to reuse a build dir made for another board: start clean then.
pristine=()
if [ -f "$build/CMakeCache.txt" ]; then
  cached=$(sed -n 's/^BOARD:STRING=//p' "$build/CMakeCache.txt")
  if [ "$cached" != "$board" ]; then
    echo "Board changed ($cached -> $board): pristine build"
    pristine=(-p always)
  fi
fi

west build "${pristine[@]}" -b "$board" "$app" -d "$build" "$@"

board_dir=$(find "$ZEPHYR_BASE/boards" -mindepth 2 -maxdepth 2 -type d -name "$board" | head -n1)
cfg="$board_dir/support/openocd.cfg"
if [ ! -f "$cfg" ]; then
  echo "No OpenOCD config found for $board ($cfg)" >&2
  exit 1
fi
ln -sf "$cfg" "$build/openocd.cfg"
