# Getting started — complete onboarding

This guide takes you from zero to a working setup, in the most efficient order. Each step is short and links to the **detailed runbook section** in case you need more information or something goes wrong.

**Total time:** about 1.5–2 hours, most of it downloads and reboots.

```
 Phase 1  Prepare the PC for Wake-on-LAN        (PC, BIOS)            ~25 min
 Phase 2  Remote access: Tailscale + Remote Desktop (PC)              ~10 min
 Phase 3  Install the PC agent                  (PC)                  ~5 min
 Phase 4  Development tools                     (any Windows PC)      ~20 min
 Phase 5  Telegram bot + firmware               (ESP32)               ~15 min
 Phase 6  Final installation next to the router (ESP32, router)       ~10 min
 Phase 7  End-to-end test                       (phone, outside home) ~10 min
```

---

## Before you start

### What you need

- [ ] An **ESP32** board and a USB cable **with data lines**
- [ ] The **target PC** connected to the router **by Ethernet cable**
- [ ] A **phone** with Telegram installed
- [ ] Admin access to the **PC** and to the **router's** admin page
- [ ] A **2.4 GHz** Wi-Fi network (the ESP32 doesn't support 5 GHz)
- [ ] Optional: a laptop, for testing remote access from outside

### Your values sheet

You'll collect these values along the way. Copy this table somewhere private (it contains secrets) and fill it in as you go:

| Value | Example | Obtained in | Goes into `config.h` as |
|---|---|---|---|
| PC MAC address | `AA-BB-CC-DD-EE-FF` | Phase 1 | `PC_MAC` |
| PC LAN IP (reserved) | `192.168.1.100` | Phase 1 | `PC_IP_ADDRESS` |
| PC Tailscale name | `my-desktop` | Phase 2 | (used to connect) |
| Agent token | `3f9c…e1a7` (48 chars) | Phase 3 | `AGENT_TOKEN` |
| Telegram bot token | `123456789:ABC…` | Phase 5 | `BOT_TOKEN` |
| Your Telegram ID | `123456789` | Phase 5 | `ALLOWED_CHAT_ID` |
| Wi-Fi name / password | | You know them | `WIFI_SSID` / `WIFI_PASSWORD` |
| Web UI password | choose one | Phase 5 | `WEB_PASSWORD` |
| ESP32 LAN IP (reserved) | `192.168.1.50` | Phase 6 | (agent firewall) |

### Get the repository

On the target PC: `git clone https://github.com/<owner>/remote-pc-wake-esp32.git`, or download the ZIP from GitHub and extract it. → [details](02-development-environment.md#step-1--install-git-and-get-the-repository)

---

## Phase 1 — Prepare the PC for Wake-on-LAN

Detailed runbook: [01 — PC setup: BIOS/UEFI and Windows](01-pc-setup-bios-and-windows.md)

1. **BIOS:** enable *Wake on LAN* / *Power On by PCI-E*, and disable *ErP Ready* / *Deep Sleep*. → [A2–A3](01-pc-setup-bios-and-windows.md#part-a--biosuefi)
2. **Network adapter:** allow it to wake the PC with a magic packet. → [B2](01-pc-setup-bios-and-windows.md#b2-configure-the-network-adapter-for-wake-on-lan)
3. **Disable Fast Startup.** → [B3](01-pc-setup-bios-and-windows.md#b3-disable-fast-startup)
4. Write down the **MAC address**. → [B1](01-pc-setup-bios-and-windows.md#b1-identify-the-ethernet-adapter-and-its-mac-address)
5. **Reserve the PC's IP** in the router and write it down. → [B4](01-pc-setup-bios-and-windows.md#b4-reserve-a-fixed-ip-for-the-pc-in-your-router)
6. **Test it:** shut the PC down and wake it from your phone with a "Wake On Lan" app. → [B5](01-pc-setup-bios-and-windows.md#b5-test-wake-on-lan-locally-before-using-the-esp32)

**Checkpoint:** the PC powers on from shutdown with a magic packet.
**Don't continue until this works.** Everything else depends on it.

---

## Phase 2 — Remote access: Tailscale + Remote Desktop

Detailed runbook: [04 — Remote access](04-remote-access-tailscale.md)

1. On the PC, in an **elevated** PowerShell window, from the repository folder:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\Install-RemoteAccess.ps1 -RestrictRdpToTailscale
   ```
   Open the sign-in link it shows and log in. → [Part A](04-remote-access-tailscale.md#part-a--set-up-the-pc-automatic)
2. **Disable key expiry** for the PC in the Tailscale admin console. This is the only manual step. → [A3](04-remote-access-tailscale.md#a3-disable-key-expiry-required)
3. Write down the **Tailscale name** the script prints.
4. Install **Tailscale** and the **Windows App** on your phone/laptop, signed in with the same account. → [Part B](04-remote-access-tailscale.md#part-b--set-up-your-other-devices)

> Windows Home? Use the `-SkipRemoteDesktop` option and pick an [alternative](04-remote-access-tailscale.md#part-e--windows-home-and-alternatives).

**Checkpoint:** from your phone **on mobile data** (Wi-Fi off), Remote Desktop connects to the PC.

---

## Phase 3 — Install the PC agent

Detailed runbook: [05 — PC agent](05-pc-agent.md)

1. In the same elevated PowerShell window:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\agent\Install-Agent.ps1
   ```
   For now it allows your whole local network. You'll restrict it to the ESP32 in Phase 6, once the ESP32 has an IP. → [Step 2](05-pc-agent.md#step-2--install-the-agent)
2. Copy the **`AGENT_TOKEN`** line it prints.

> Don't want shutdown/sleep/lock or stats? Skip this phase and leave `AGENT_TOKEN` empty. Waking and on/off alerts still work.

**Checkpoint:** the installer ends with `[OK] Agent 1.0.0 is answering on port 8765`.

---

## Phase 4 — Development tools

Detailed runbook: [02 — Development environment](02-development-environment.md)

1. Install **Arduino IDE 2**: `winget install --id ArduinoSA.IDE.stable -e` → [Step 3](02-development-environment.md#step-3--install-arduino-ide-2x)
2. Add the ESP32 boards URL and install **"esp32" by Espressif Systems**. → [Step 4](02-development-environment.md#step-4--install-the-esp32-board-package)
3. Install the libraries **UniversalTelegramBot** and **ArduinoJson**. → [Step 5](02-development-environment.md#step-5--install-the-libraries)
4. Connect the ESP32; check it shows up as a **COM port** (install the CP210x/CH340 driver if not). → [Step 2](02-development-environment.md#step-2--connect-the-esp32-and-check-the-driver)
5. Select **ESP32 Dev Module** and the COM port. → [Step 6](02-development-environment.md#step-6--select-the-board-and-port)

**Checkpoint:** opening `firmware/remote-pc-wake/remote-pc-wake.ino` and clicking **Verify** ends with *Done compiling* (copy `config.example.h` to `config.h` first). → [Step 7](02-development-environment.md#step-7--verify-the-toolchain-build-test)

---

## Phase 5 — Telegram bot + firmware

Detailed runbook: [03 — Telegram bot, flashing and deployment](03-telegram-bot-flash-and-deploy.md)

1. Create the bot with **@BotFather** and save the **bot token**. → [Step 1](03-telegram-bot-flash-and-deploy.md#step-1--create-the-telegram-bot)
2. Get your **Telegram ID** from **@userinfobot**. → [Step 2](03-telegram-bot-flash-and-deploy.md#step-2--get-your-telegram-user-id)
3. Open your bot's chat and press **Start**. → [Step 3](03-telegram-bot-flash-and-deploy.md#step-3--start-a-chat-with-your-bot)
4. Fill in `config.h` with **every value from your sheet**, and choose a `WEB_PASSWORD`. → [Step 4](03-telegram-bot-flash-and-deploy.md#step-4--configure-the-firmware)
5. **Upload** the firmware and open the Serial Monitor at 115200 baud. → [Step 5](03-telegram-bot-flash-and-deploy.md#step-5--upload-the-firmware)

**Checkpoint:** the bot sends **ESP32 online (v1.1.0)** with buttons, and `/status` shows the PC's CPU, RAM and disks.

---

## Phase 6 — Final installation next to the router

1. Unplug the ESP32 from the PC. Power it from the **router's USB port** or a phone charger near the router. → [Step 7](03-telegram-bot-flash-and-deploy.md#step-7--permanent-installation-next-to-the-router)
2. **Reserve the ESP32's IP** in the router (it appears as `remote-pc-wake`). → [Step 1](05-pc-agent.md#step-1--reserve-an-ip-for-the-esp32)
3. **Restrict the agent to the ESP32.** Run the installer again with its IP. The token is kept, so **no re-flash is needed**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\agent\Install-Agent.ps1 -Esp32Address 192.168.1.50
   ```
4. Open **http://remote-pc-wake.local** on your phone (on home Wi-Fi) and sign in with `admin` and your `WEB_PASSWORD`. → [Web UI](usage.md#web-ui-home-network)

**Checkpoint:** the web UI shows the PC as on, with its stats.

---

## Phase 7 — End-to-end test

Do it **away from home**, or with your phone on **mobile data**:

| # | Action | Expected result |
|---|---|---|
| 1 | `/shutdown` → **Now** | "The PC has shut down." |
| 2 | `/status` | PC is off |
| 3 | `/wake` | "Magic packet sent…" → about 1 minute later "The PC is online" |
| 4 | Tailscale on + Remote Desktop to the PC | You see your desktop |
| 5 | `/lock` | The PC's screen locks |
| 6 | `/shutdown 5` then `/cancel` | Scheduled, then "cancelled" |
| 7 | `/sleep`, then `/wake` | "The PC is asleep", then "online" |

**Done.** See [Daily use](usage.md) for every command, the web UI and the notifications you'll receive.

---

## If something fails

| Phase | Where to look |
|---|---|
| 1 — PC doesn't wake | [Runbook 01 troubleshooting](01-pc-setup-bios-and-windows.md#troubleshooting) |
| 2 — Can't connect remotely | [Runbook 04 troubleshooting](04-remote-access-tailscale.md#troubleshooting) |
| 3 — Agent install/test fails | [Runbook 05 troubleshooting](05-pc-agent.md#troubleshooting) |
| 4 — Compile/upload errors | [Runbook 02 troubleshooting](02-development-environment.md#troubleshooting) |
| 5–6 — Bot silent, Wi-Fi, status wrong | [Runbook 03 troubleshooting](03-telegram-bot-flash-and-deploy.md#troubleshooting) |
