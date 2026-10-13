# OpCode Labs – Zephyr RTOS training

Supported boards:

| Board                 | Zephyr name     | LED used by Lab 01 |
|-----------------------|-----------------|--------------------|
| STM32F407 Discovery   | `stm32f4_disco` | LD4 green (PD12)   |
| Nucleo-F446RE         | `nucleo_f446re` | LD2 green (PA5)    |
| Nucleo-F429ZI         | `nucleo_f429zi` | LD1 green (PB0)    |
| Nucleo-G474RE         | `nucleo_g474re` | LD2 green (PA5)    |

## 1. One-time setup (Windows + WSL2 Ubuntu 22.04/24.04)

Windows, in an admin terminal:

```
wsl --install -d Ubuntu-24.04
winget install --exact dorssel.usbipd-win
```

Ubuntu (keep everything under your Linux home, **not** `/mnt/c`):

```bash
mkdir -p ~/opcode-ws && cd ~/opcode-ws
git clone https://github.com/opcode-labs/opcode-zephyr-training
./opcode-zephyr-training/scripts/setup_wsl.sh      # asks which board you use
```

The script installs the packages, a Python venv with `west`, Zephyr v4.2.0, and the
Zephyr SDK (ARM toolchain only). It also builds Lab 01 as a test. Only the folders
needed for the STM32F4/G4 labs are checked out (~0.4 GB instead of ~1.5 GB).
Use `LIGHT=0` to get the full trees.

Options: `BOARD=nucleo_g474re ./opcode-zephyr-training/scripts/setup_wsl.sh` skips the board menu.

## 2. Connect the board to WSL

Plug the board into its ST-Link USB port. Then, on **Windows**:

```
%USERPROFILE%\opcode-tools\usb_attach.cmd
```

In Ubuntu, `lsusb` should list `STMicroelectronics ST-LINK`.

## 3. Build, flash, debug (Lab 01 – blinky)

```bash
cd ~/opcode-ws/opcode-zephyr-training
west build -b $BOARD labs/01-blinky -d build/01-blinky
west flash -d build/01-blinky          # OpenOCD through the ST-Link
```

After you change boards, run a pristine build: `west build -p always -b <board> ...`.

In VS Code (`code .` from Ubuntu): **Ctrl+Shift+B** builds, *Run Task → Flash Lab 01* flashes,
and **F5** starts the debugger. Each of them asks which board you use.

## Repository layout

```
west.yml                 Zephyr version + allowed modules
scripts/setup_wsl.sh     environment setup (WSL/Linux)
scripts/usb_attach.*     Windows tool: attach the ST-Link to WSL (usbipd-win)
labs/01-blinky/          LED toggled from one thread (K_THREAD_DEFINE)
.vscode/                 build/flash tasks and Cortex-Debug config
```
