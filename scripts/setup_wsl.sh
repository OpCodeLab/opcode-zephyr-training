#!/usr/bin/env bash
# OpCode Labs - Zephyr training: workspace setup for WSL2 Ubuntu (22.04 / 24.04)
#
#   mkdir -p ~/opcode-ws && cd ~/opcode-ws
#   git clone https://github.com/opcode-labs/opcode-zephyr-training
#   ./opcode-zephyr-training/scripts/setup_wsl.sh
#
# Overridable: BOARD=stm32f4_disco ZEPHYR_SDK_VERSION=0.17.2 MANIFEST=west.yml
#              LIGHT=0 (keep the full Zephyr + hal_stm32 trees instead of the sparse checkout)
set -euo pipefail

ZEPHYR_SDK_VERSION="${ZEPHYR_SDK_VERSION:-0.17.2}"
MANIFEST="${MANIFEST:-west.yml}"
LIGHT="${LIGHT:-1}"

# Training boards: "zephyr_board_name|description"
BOARDS=(
  "stm32f4_disco|STM32F407 Discovery (STM32F4DISCOVERY)"
  "nucleo_f446re|Nucleo-F446RE"
  "nucleo_f429zi|Nucleo-F429ZI"
  "nucleo_g474re|Nucleo-G474RE"
)

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WS="$(dirname "$REPO_DIR")"
VENV="$WS/.venv"
SDK_DIR="$HOME/zephyr-sdk-$ZEPHYR_SDK_VERSION"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARNING: %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# --- 0. Sanity checks -------------------------------------------------------
grep -qi microsoft /proc/version || warn "This does not look like WSL (fine on native Linux)."
case "$REPO_DIR" in
  /mnt/*) die "Repo is on a Windows drive ($REPO_DIR). Clone it under your Linux home, e.g. ~/opcode-ws (much faster builds)." ;;
esac
case "$WS" in *" "*) die "Workspace path contains a space: '$WS'" ;; esac
[ "$WS" = "$HOME" ] && die "Clone the repo inside a dedicated folder, e.g. ~/opcode-ws/opcode-zephyr-training"

# --- Board selection --------------------------------------------------------
if [ -z "${BOARD:-}" ]; then
  if [ -t 0 ]; then
    echo "Which board do you use?"
    for i in "${!BOARDS[@]}"; do printf '  [%d] %s\n' $((i + 1)) "${BOARDS[$i]#*|}"; done
    read -rp "Choice [1]: " choice
    choice="${choice:-1}"
    [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#BOARDS[@]} ] \
      || die "Invalid choice: $choice"
    BOARD="${BOARDS[$((choice - 1))]%%|*}"
  else
    BOARD="${BOARDS[0]%%|*}"
  fi
fi
printf '%s\n' "${BOARDS[@]%%|*}" | grep -qx "$BOARD" \
  || warn "$BOARD is not one of the training boards (${BOARDS[*]%%|*})"
say "Board: $BOARD"

# --- 1. Ubuntu packages -----------------------------------------------------
say "Installing Ubuntu packages (sudo password required)"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  git cmake ninja-build gperf ccache dfu-util device-tree-compiler wget curl \
  python3-dev python3-venv python3-pip python3-setuptools python3-wheel \
  xz-utils file make gcc g++ gcc-multilib g++-multilib libmagic1 \
  openocd usbutils

CMAKE_VER="$(cmake --version | awk 'NR==1{print $3}')"
dpkg --compare-versions "$CMAKE_VER" ge 3.20.5 || die "CMake $CMAKE_VER too old (need >= 3.20.5)"

# --- 2. Python venv + west --------------------------------------------------
say "Python virtual environment: $VENV"
[ -d "$VENV" ] || python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
pip install -q --upgrade pip west

# --- 3. West workspace ------------------------------------------------------
say "West workspace: $WS (manifest $MANIFEST)"
cd "$WS"
unset ZEPHYR_BASE   # a previous env.sh in ~/.bashrc would point west at another workspace
[ -d .west ] || west init -l --mf "$MANIFEST" "$REPO_DIR"
west update --narrow -o=--depth=1

# Light workspace: only check out what STM32F4/G4 labs need (about 1.5 GB -> 0.4 GB).
# Re-running 'west update' keeps these settings. LIGHT=0 restores the full trees.
if [ "$LIGHT" = 1 ]; then
  say "Sparse checkout (light workspace)"
  git -C zephyr sparse-checkout set --cone \
    arch boards/common boards/shields boards/st cmake drivers \
    dts/arm/st dts/bindings dts/common include kernel lib misc modules \
    samples/basic samples/hello_world scripts share snippets soc submanifests subsys
  git -C modules/hal/stm32 sparse-checkout set --cone \
    dts/st/f4 dts/st/g4 lib scripts zephyr \
    stm32cube/common_ll stm32cube/stm32f4xx stm32cube/stm32g4xx
else
  git -C zephyr sparse-checkout disable 2>/dev/null || true
  git -C modules/hal/stm32 sparse-checkout disable 2>/dev/null || true
fi
west zephyr-export
pip install -q -r zephyr/scripts/requirements.txt

# --- 4. Zephyr SDK (ARM toolchain only) -------------------------------------
if [ ! -d "$SDK_DIR" ]; then
  say "Installing Zephyr SDK $ZEPHYR_SDK_VERSION (arm-zephyr-eabi only)"
  west sdk install --version "$ZEPHYR_SDK_VERSION" -t arm-zephyr-eabi
fi
[ -x "$SDK_DIR/arm-zephyr-eabi/bin/arm-zephyr-eabi-gcc" ] || die "SDK not found in $SDK_DIR"

# --- 5. ST-Link access without sudo -----------------------------------------
say "udev rules for ST-Link"
sudo tee /etc/udev/rules.d/49-opcode-stlink.rules >/dev/null <<'RULES'
# OpCode Labs: ST-Link V2 / V2-1 / V3 accessible without root
SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="3748|374b|3752|374e|374f|3753|3754", MODE="0666"
SUBSYSTEM=="tty", ATTRS{idVendor}=="0483", MODE="0666"
RULES
if systemctl is-active --quiet systemd-udevd 2>/dev/null; then
  sudo udevadm control --reload-rules && sudo udevadm trigger
else
  warn "udev is not running (systemd disabled in WSL). Add to /etc/wsl.conf:"
  warn "   [boot]"
  warn "   systemd=true"
  warn "then run 'wsl --shutdown' in Windows and reopen Ubuntu."
fi

# --- 6. Environment file ----------------------------------------------------
cat > "$WS/env.sh" <<ENV
# OpCode Labs Zephyr training environment
source "$VENV/bin/activate"
export ZEPHYR_BASE="$WS/zephyr"
export ZEPHYR_SDK_INSTALL_DIR="$SDK_DIR"
export BOARD="$BOARD"
ENV
grep -qF "$WS/env.sh" ~/.bashrc || echo "source \"$WS/env.sh\"" >> ~/.bashrc

# --- 7. Copy the USB attach tool to Windows ---------------------------------
if command -v cmd.exe >/dev/null 2>&1; then
  WINPROFILE="$(cd /mnt/c && cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')"
  if [ -n "$WINPROFILE" ]; then
    WINTOOLS="$(wslpath "$WINPROFILE")/opcode-tools"
    mkdir -p "$WINTOOLS"
    cp "$REPO_DIR/scripts/usb_attach.py" "$REPO_DIR/scripts/usb_attach.cmd" "$WINTOOLS/"
    say "USB tool copied to Windows: $WINPROFILE\\opcode-tools\\usb_attach.cmd"
  fi
fi

# --- 8. Smoke test build ----------------------------------------------------
# shellcheck disable=SC1091
source "$WS/env.sh"
LAB="$REPO_DIR/labs/01-blinky"
[ -d "$LAB" ] || LAB="$WS/zephyr/samples/basic/blinky"
say "Test build: $LAB for $BOARD"
west build -p always -b "$BOARD" "$LAB" -d "$REPO_DIR/build/01-blinky"

say "Done. Open a new Ubuntu terminal (or: source $WS/env.sh)."
echo "Next: on Windows run opcode-tools\\usb_attach.cmd, then here: west flash -d build/01-blinky"
echo "Change board later: edit BOARD in $WS/env.sh (or re-run this script with BOARD=...)."
