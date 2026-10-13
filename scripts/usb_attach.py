#!/usr/bin/env python3
"""OpCode Labs - Zephyr training
Find the ST-Link of an STM32 board on Windows and attach it to WSL2 (usbipd-win).

Run on WINDOWS (cmd or PowerShell), not inside WSL:
    usb_attach.cmd                 find, share (bind) if needed, attach
    usb_attach.cmd --list          show detected ST-Links and their state
    usb_attach.cmd --auto          keep re-attaching after unplug / reset
    usb_attach.cmd --serial 066D   pick one board when several are plugged
    usb_attach.cmd --detach        give the board(s) back to Windows

Requires usbipd-win >= 4.0:  winget install --exact dorssel.usbipd-win
Standard library only.
"""
from __future__ import annotations

import argparse
import ctypes
import json
import os
import re
import shutil
import subprocess
import sys
import time

ST_VID = "0483"
STLINK_PIDS = {
    "3748": "ST-Link/V2",     # STM32F4-Discovery (older revisions)
    "374B": "ST-Link/V2-1",   # Nucleo-64, STM32F4-Discovery MB997D/E
    "3752": "ST-Link/V2-1",
    "374E": "STLINK-V3",
    "374F": "STLINK-V3",
    "3753": "STLINK-V3",
    "3754": "STLINK-V3",
}
ID_RE = re.compile(r"VID_([0-9A-F]{4})&PID_([0-9A-F]{4})\\([^\\]+)$", re.IGNORECASE)
USBIPD = "usbipd"


def die(msg: str) -> None:
    print(f"\nERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    r = subprocess.run(cmd, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    if check and r.returncode != 0:
        die(f"{' '.join(cmd)} failed:\n{(r.stderr or r.stdout).strip()}")
    return r


class Dev:
    def __init__(self, raw: dict):
        self.busid = raw.get("BusId")
        self.attached = bool(raw.get("ClientIPAddress"))
        self.shared = bool(raw.get("PersistedGuid"))
        m = ID_RE.search(raw.get("InstanceId") or "")
        self.vid, self.pid, self.serial = (
            (m.group(1).upper(), m.group(2).upper(), m.group(3)) if m else ("", "", ""))

    @property
    def kind(self) -> str:
        return STLINK_PIDS.get(self.pid, "ST device")

    def state(self) -> str:
        if self.attached:
            return "ATTACHED to WSL"
        return "shared, not attached" if self.shared else "not shared (needs bind)"

    def __str__(self) -> str:
        return f"busid {self.busid:<6} {self.kind:<13} serial {self.serial:<26} {self.state()}"


def check_usbipd() -> None:
    global USBIPD
    found = shutil.which("usbipd")
    default = r"C:\Program Files\usbipd-win\usbipd.exe"
    if not found and os.path.exists(default):
        found = default
    if not found:
        die("usbipd-win is not installed.\n"
            "  Install it once (admin):  winget install --exact dorssel.usbipd-win\n"
            "  then open a NEW terminal and run this script again.")
    USBIPD = found
    ver = run([USBIPD, "--version"]).stdout.strip()
    m = re.match(r"(\d+)\.", ver)
    if m and int(m.group(1)) < 4:
        die(f"usbipd-win {ver} is too old, version 4.0 or newer is required.")


def list_stlinks() -> list[Dev]:
    out = run([USBIPD, "state"]).stdout.lstrip("\ufeff")
    devs = [Dev(d) for d in json.loads(out).get("Devices", [])]
    # BusId is null for devices that are remembered but not plugged in
    return [d for d in devs if d.busid and d.vid == ST_VID and d.pid in STLINK_PIDS]


def is_admin() -> bool:
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


def bind(dev: Dev) -> Dev:
    print(f"Sharing busid {dev.busid} with WSL (one-time per board, needs administrator)...")
    if is_admin():
        run([USBIPD, "bind", "--busid", dev.busid])
    else:
        ps = (f"Start-Process -FilePath '{USBIPD}' -ArgumentList 'bind','--busid','{dev.busid}' "
              f"-Verb RunAs -Wait -WindowStyle Hidden")
        if run(["powershell", "-NoProfile", "-Command", ps], check=False).returncode != 0:
            die("Administrator elevation was refused or failed.\n"
                f"  Ask the trainer/IT to run once in an admin terminal:  usbipd bind --busid {dev.busid}")
    for d in list_stlinks():
        if d.busid == dev.busid and d.shared:
            return d
    die(f"busid {dev.busid} is still not shared after bind.")
    raise SystemExit  # unreachable


def wsl_cmd(distro: str | None) -> list[str]:
    return ["wsl"] + (["-d", distro] if distro else [])


def wake_wsl(distro: str | None) -> None:
    if run(wsl_cmd(distro) + ["-e", "true"], check=False).returncode != 0:
        die("Cannot start WSL. Check 'wsl -l -v' and that Ubuntu is installed.")


def attach(dev: Dev, distro: str | None, auto: bool) -> None:
    cmd = [USBIPD, "attach", "--busid", dev.busid, "--wsl"] + ([distro] if distro else [])
    if auto:
        cmd.append("--auto-attach")
        subprocess.Popen(cmd, creationflags=subprocess.CREATE_NEW_CONSOLE)
        print(f"Auto-attach running for {dev.busid} in a separate window (close it to stop).")
        time.sleep(3)
        return
    r = run(cmd, check=False)
    if r.returncode != 0:
        die(f"Attach failed:\n{(r.stderr or r.stdout).strip()}\n"
            "  - Close STM32CubeProgrammer/IDE on Windows (they lock the ST-Link)\n"
            "  - If it mentions the firewall or VPN, ask the trainer (see README)")


def verify(dev: Dev, distro: str | None) -> None:
    for _ in range(12):
        r = run(wsl_cmd(distro) + ["-e", "lsusb", "-d", f"{ST_VID}:{dev.pid.lower()}"], check=False)
        if r.returncode == 0 and r.stdout.strip():
            print(f"  OK, visible in WSL: {r.stdout.strip().splitlines()[0]}")
            return
        if r.returncode == 127:
            print("  (lsusb missing in WSL: run scripts/setup_wsl.sh)")
            return
        time.sleep(0.5)
    print("  WARNING: not visible in WSL yet. Run 'lsusb' in Ubuntu to check.")


def select(devs: list[Dev], serial: str | None, take_all: bool) -> list[Dev]:
    if serial:
        devs = [d for d in devs if serial.lower() in d.serial.lower()]
        if not devs:
            die(f"No ST-Link with serial containing '{serial}'. Use --list.")
    if take_all or len(devs) == 1:
        return devs
    if not sys.stdin.isatty():
        die("Several ST-Links found, use --serial or --all.")
    print("Several boards found:")
    for i, d in enumerate(devs, 1):
        print(f"  [{i}] {d}")
    choice = input("Which one? [1]: ").strip() or "1"
    if not choice.isdigit() or not 1 <= int(choice) <= len(devs):
        die("Invalid choice.")
    return [devs[int(choice) - 1]]


def main() -> None:
    if sys.platform != "win32":
        die("Run this script on Windows, not inside WSL.")

    ap = argparse.ArgumentParser(description="Attach an ST-Link (STM32 board) to WSL2.")
    ap.add_argument("--list", action="store_true", help="list detected ST-Links and exit")
    ap.add_argument("--detach", action="store_true", help="give the board(s) back to Windows")
    ap.add_argument("--auto", action="store_true", help="re-attach automatically after unplug/reset")
    ap.add_argument("--serial", help="select a board by (part of) its ST-Link serial")
    ap.add_argument("--all", action="store_true", help="attach every detected ST-Link")
    ap.add_argument("--distro", help="WSL distribution (default: the default distro)")
    args = ap.parse_args()

    check_usbipd()
    devs = list_stlinks()

    if args.list:
        print("\n".join(str(d) for d in devs) if devs else "No ST-Link detected.")
        return

    if args.detach:
        attached = [d for d in select(devs, args.serial, True) if d.attached]
        for d in attached:
            run([USBIPD, "detach", "--busid", d.busid])
            print(f"Detached {d.busid}, the board is back on Windows.")
        if not attached:
            print("Nothing attached.")
        return

    if not devs:
        die("No ST-Link found.\n"
            "  - Plug the board on its ST-Link USB port (Nucleo: CN1, Discovery: mini-USB CN1)\n"
            "  - Use a data cable, not a charge-only cable")

    targets = select(devs, args.serial, args.all)
    wake_wsl(args.distro)

    for d in targets:
        print(f"\n{d}")
        if d.attached:
            print("  Already attached, nothing to do.")
            continue
        if not d.shared:
            d = bind(d)
        attach(d, args.distro, args.auto)
        verify(d, args.distro)

    print("\nKeep an Ubuntu terminal or VS Code (WSL) open, otherwise WSL stops and the board is released.")
    print("In WSL:  west flash -d build/01-blinky -r openocd    |    west debug -d build/01-blinky")


if __name__ == "__main__":
    main()
