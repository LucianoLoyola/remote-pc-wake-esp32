# Runbook 02 — Development environment (tools to build and flash the firmware)

This runbook installs everything needed on a **Windows** computer to compile the firmware and upload it to the ESP32. You only need this setup once. Any Windows PC works; it doesn't have to be the target PC.

**Estimated time:** 20–30 minutes (most of it downloads).

---

## Hardware you need

| Item | Notes |
|---|---|
| ESP32 development board | Any classic **ESP32** board works (e.g. *ESP32 DevKit V1*, *ESP32-WROOM-32*). ESP32-S2/S3/C3 also work if you pick the matching board in the IDE. |
| USB cable **with data lines** | Many cheap cables only carry power. If the board isn't detected, try another cable first. |
| USB power supply (5 V, ≥ 500 mA) | For the permanent install. The router's USB port or any phone charger works. |

---

## Overview

| # | Tool | Required? | Purpose |
|---|---|---|---|
| 1 | Git | Recommended | Download this repository and get updates |
| 2 | USB-to-serial driver | Only if the board isn't detected | Lets Windows talk to the ESP32 |
| 3 | Arduino IDE 2.x | **Yes** | Code editor, compiler and uploader |
| 4 | ESP32 board package (Espressif) | **Yes** | ESP32 compiler and tools |
| 5 | UniversalTelegramBot library | **Yes** | Telegram Bot API client |
| 6 | ArduinoJson library | **Yes** | JSON parsing (used by the Telegram library) |
| 7 | Arduino CLI | Optional | Build and upload from the command line |

---

## Step 1 — Install Git and get the repository

```powershell
winget install --id Git.Git -e
```

Close and reopen the terminal, then clone the repository:

```powershell
cd $HOME\Documents
git clone https://github.com/<owner>/remote-pc-wake-esp32.git
```

> No Git? On the GitHub page, click **Code → Download ZIP** and extract it.

---

## Step 2 — Connect the ESP32 and check the driver

1. Plug the ESP32 into the PC with the USB cable.
2. Open **Device Manager** (`devmgmt.msc`) → **Ports (COM & LPT)**.
3. You should see something like:
   - `Silicon Labs CP210x USB to UART Bridge (COM3)`, or
   - `USB-SERIAL CH340 (COM4)`, or
   - `USB Serial Device (COM5)` (boards with native USB, like the ESP32-S3/C3)

Write down the **COM port number**.

**If the board doesn't appear**, or shows up under *Other devices* with a warning icon:

1. Try a different USB cable or port.
2. Look at the small chip next to the USB connector on the board and install the matching driver:

| Chip marking | Driver |
|---|---|
| **CP2102 / CP2104** (Silicon Labs) | <https://www.silabs.com/developers/usb-to-uart-bridge-vcp-drivers> → *CP210x Windows Drivers* |
| **CH340 / CH341 / CH9102** (WCH) | <https://www.wch-ic.com/downloads/CH341SER_EXE.html> |

3. Unplug and re-plug the board, then check **Ports (COM & LPT)** again.

---

## Step 3 — Install Arduino IDE 2.x

```powershell
winget install --id ArduinoSA.IDE.stable -e
```

Or download it from <https://www.arduino.cc/en/software>.

Launch it once and accept any prompts to install USB drivers.

---

## Step 4 — Install the ESP32 board package

1. **File → Preferences** (`Ctrl + ,`).
2. In **Additional boards manager URLs**, paste:
   ```
   https://espressif.github.io/arduino-esp32/package_esp32_index.json
   ```
3. Click **OK**.
4. Open **Tools → Board → Boards Manager** (`Ctrl + Shift + B`).
5. Search for **esp32** and install **"esp32" by Espressif Systems**. Don't install "Arduino ESP32 Boards" by Arduino; that one is for Arduino-branded boards only.
6. The download is several hundred MB, so wait for it to finish.

---

## Step 5 — Install the libraries

1. Open **Tools → Manage Libraries** (`Ctrl + Shift + I`).
2. Search and install:
   - **UniversalTelegramBot** by *Brian Lough*
   - **ArduinoJson** by *Benoit Blanchon*

If the IDE asks to install dependencies, click **Install all**.

---

## Step 6 — Select the board and port

1. **Tools → Board → esp32 → ESP32 Dev Module**. For other variants, choose the matching entry (e.g. *ESP32S3 Dev Module*).
2. **Tools → Port** → select the COM port from Step 2.

---

## Step 7 — Verify the toolchain (build test)

1. Open `firmware/remote-pc-wake/remote-pc-wake.ino` from the repository (**File → Open**).
2. Copy `config.example.h` to `config.h` in the same folder. You can keep the placeholder values for this test.
   ```powershell
   cd remote-pc-wake-esp32\firmware\remote-pc-wake
   Copy-Item config.example.h config.h
   ```
3. Click **Verify** (✓ icon, `Ctrl + R`).

If it ends with **"Done compiling"**, your environment is ready. Continue with [Runbook 03 — Telegram bot, flashing and deployment](03-telegram-bot-flash-and-deploy.md).

---

## Optional — Arduino CLI

For people who prefer the command line, or for automation:

```powershell
winget install --id ArduinoSA.CLI -e

arduino-cli config init
arduino-cli config add board_manager.additional_urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli core update-index
arduino-cli core install esp32:esp32
arduino-cli lib install UniversalTelegramBot ArduinoJson

# Build
arduino-cli compile --fqbn esp32:esp32:esp32 firmware/remote-pc-wake

# Upload (replace COM3 with your port)
arduino-cli upload --fqbn esp32:esp32:esp32 -p COM3 firmware/remote-pc-wake

# Serial monitor
arduino-cli monitor -p COM3 -c baudrate=115200
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `config.h not found` | Copy `config.example.h` to `config.h` (Step 7). |
| `UniversalTelegramBot.h: No such file or directory` | Install the library (Step 5). |
| `A fatal error occurred: Failed to connect to ESP32: Wrong boot mode detected` | Hold the **BOOT** button on the board while the IDE says *Connecting...*, release it when the upload starts. |
| No COM port listed | Charge-only cable or missing driver (Step 2). |
| `Access is denied` / port busy | Close the Serial Monitor or any other program using the COM port. |
| Deprecation warnings about `DynamicJsonDocument` | Harmless. The Telegram library uses the ArduinoJson 6 API, which version 7 still supports. |
