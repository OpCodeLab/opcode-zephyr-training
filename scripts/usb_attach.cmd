@echo off
rem OpCode Labs - attach the ST-Link of the STM32 board to WSL (wrapper for usb_attach.py)
where py >nul 2>&1
if %errorlevel%==0 (
  py -3 "%~dp0usb_attach.py" %*
) else (
  python "%~dp0usb_attach.py" %*
)
