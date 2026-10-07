# Getting started — complete onboarding

This guide takes you from zero to a working setup, in the most efficient order. Every Windows step is a **PowerShell script**; each step also links to the **detailed runbook section**, which explains the manual alternative and what to do if something goes wrong.

**Total time:** about 1–1.5 hours, most of it downloads and reboots.

```
 Phase 1  Prepare the PC for Wake-on-LAN          BIOS (manual) + script      ~20 min
 Phase 2  Remote access: Tailscale + Remote Desktop  script                   ~10 min
 Phase 3  Install the PC agent                    script                      ~5 min
 Phase 4  Development tools                       script                      ~15 min
 Phase 5  Telegram bot + firmware                 BotFather (manual) + scripts ~10 min
 Phase 6  Final installation next to the router   router (manual) + script    ~10 min
 Phase 7  End-to-end test                         phone, outside home         ~10 min
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

### What the scripts detect and what you provide

| Value | Source |
|---|---|
| PC MAC address and IP | Detected (`Enable-WakeOnLan.ps1`, `New-FirmwareConfig.ps1`) |
| Agent token | Generated and read automatically |
| Your Telegram ID | Detected when you message your bot |
| ESP32 COM port | Detected |
| Telegram bot token | **You**, from @BotFather (Phase 5) |
| Wi-Fi name and password | **You** (the name is suggested if the PC uses Wi-Fi) |
| Web UI password | **You** choose it |
| ESP32 IP | Shown in your router (Phase 6) |

### Get the repository and open PowerShell

1. On the target PC, download the repository: `git clone https://github.com/LucianoLoyola/remote-pc-wake-esp32.git`, or **Code → Download ZIP** on GitHub and extract it. → [details](02-development-environment.md#step-1--install-git-and-get-the-repository)
2. Open an **elevated** PowerShell window (right-click Start → **Terminal (Admin)**) and go to the repository folder:
   ```powershell
   cd $HOME\Documents\remote-pc-wake-esp32
   ```

All the commands below run from that window.

---

## Phase 1 — Prepare the PC for Wake-on-LAN

Detailed runbook: [01 — PC setup: BIOS/UEFI and Windows](01-pc-setup-bios-and-windows.md)

1. **BIOS (manual):** enable *Wake on LAN* / *Power On by PCI-E*, and disable *ErP Ready* / *Deep Sleep*. This can't be done from Windows. → [Part A](01-pc-setup-bios-and-windows.md#part-a--biosuefi)
2. **Windows:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\Enable-WakeOnLan.ps1
   ```
   It configures the network adapter and disables Fast Startup, then prints the PC's **MAC** and **IP**. → [Part B](01-pc-setup-bios-and-windows.md#part-b--windows)
3. **Router (manual):** reserve that IP for that MAC (DHCP reservation). → [B4](01-pc-setup-bios-and-windows.md#b4-reserve-a-fixed-ip-for-the-pc-in-your-router)
4. **Test:** shut the PC down and wake it from your phone with a "Wake On Lan" app. → [B5](01-pc-setup-bios-and-windows.md#b5-test-wake-on-lan-locally-before-using-the-esp32)

**Checkpoint:** the PC powers on from shutdown with a magic packet.
**Don't continue until this works.** Everything else depends on it.

---

## Phase 2 — Remote access: Tailscale + Remote Desktop

Detailed runbook: [04 — Remote access](04-remote-access-tailscale.md)

1. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\Install-RemoteAccess.ps1 -RestrictRdpToTailscale
   ```
   Open the sign-in link it shows and log in. If it warns about Windows Hello-only sign-in, run it again adding `-AllowPasswordSignIn`. → [Part A](04-remote-access-tailscale.md#part-a--set-up-the-pc-automatic)
2. **Tailscale admin console (manual):** disable key expiry for the PC. → [A3](04-remote-access-tailscale.md#a3-disable-key-expiry-required)
3. Install **Tailscale** and the **Windows App** on your phone/laptop, signed in with the same account. → [Part B](04-remote-access-tailscale.md#part-b--set-up-your-other-devices)
4. Optional: let the PC sleep by itself after an hour of inactivity. → [Part F](04-remote-access-tailscale.md#part-f--save-power-when-youre-done)
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\Set-AutoSleep.ps1 -Minutes 60
   ```

> Windows Home? Add `-SkipRemoteDesktop` and pick an [alternative](04-remote-access-tailscale.md#part-e--windows-home-and-alternatives).

**Checkpoint:** from your phone **on mobile data** (Wi-Fi off), Remote Desktop connects to the PC.

---

## Phase 3 — Install the PC agent

Detailed runbook: [05 — PC agent](05-pc-agent.md)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Agent.ps1
```

For now it allows your whole local network; you'll restrict it to the ESP32 in Phase 6. You don't need to copy the token: Phase 5 reads it automatically. → [Step 2](05-pc-agent.md#step-2--install-the-agent)

> Don't want shutdown/sleep/lock or stats? Skip this phase. Waking and on/off alerts still work.

**Checkpoint:** the installer ends with `[OK] Agent 1.0.0 is answering on port 8765`.

---

## Phase 4 — Development tools

Detailed runbook: [02 — Development environment](02-development-environment.md)

Connect the ESP32 by USB and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-DevTools.ps1
```

It installs Git, Arduino IDE, Arduino CLI, the ESP32 board package and the libraries, and checks the board's USB driver. → [Automatic setup](02-development-environment.md#automatic-setup-steps-27)

**Checkpoint:** the script ends showing the ESP32's COM port (e.g. `[OK] Silicon Labs CP210x on COM3`).

---

## Phase 5 — Telegram bot + firmware

Detailed runbook: [03 — Telegram bot, flashing and deployment](03-telegram-bot-flash-and-deploy.md)

1. **Telegram (manual):** create the bot with **@BotFather** and copy the **bot token**. → [Step 1](03-telegram-bot-flash-and-deploy.md#step-1--create-the-telegram-bot)
2. Create `config.h`:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\New-FirmwareConfig.ps1
   ```
   It detects the PC's MAC and IP and the agent token, asks for the Wi-Fi, bot token and web UI password, and asks you to send any message to your bot to detect your Telegram ID. → [Step 4](03-telegram-bot-flash-and-deploy.md#step-4--configure-the-firmware)
3. Build and upload:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\Install-Firmware.ps1 -Monitor
   ```
   Press Ctrl+C to close the monitor once you see `Connected. IP: ...`. → [Step 5](03-telegram-bot-flash-and-deploy.md#step-5--upload-the-firmware)

**Checkpoint:** the bot sends **ESP32 online (v1.1.0)** with buttons, and `/status` shows the PC's CPU, RAM and disks.

---

## Phase 6 — Final installation next to the router

1. Unplug the ESP32 from the PC. Power it from the **router's USB port** or a phone charger near the router. → [Step 7](03-telegram-bot-flash-and-deploy.md#step-7--permanent-installation-next-to-the-router)
2. **Router (manual):** reserve the ESP32's IP (it appears as `remote-pc-wake`). → [Step 1](05-pc-agent.md#step-1--reserve-an-ip-for-the-esp32)
3. Restrict the agent to the ESP32. The token is kept, so **no re-flash is needed**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\Install-Agent.ps1 -Esp32Address 192.168.1.50
   ```
4. Open **http://remote-pc-wake.local** on your phone (on home Wi-Fi) and sign in with `admin` and your web UI password. → [Web UI](usage.md#web-ui-home-network)

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

## All the scripts

Want to know exactly what a script changes on your PC before running it? See the [Scripts reference](scripts-reference.md): every change, every internet address contacted, and how to undo it.

| Script | Phase | Admin | What it configures |
|---|---|---|---|
| `Enable-WakeOnLan.ps1` | 1 | Yes (`-CheckOnly`: no) | Network adapter wake settings, Fast Startup |
| `Send-MagicPacket.ps1` | 1 | No | Test: wakes a PC from another Windows PC |
| `Install-RemoteAccess.ps1` | 2 | Yes | Tailscale, Remote Desktop, password sign-in |
| `Set-AutoSleep.ps1` | 2 | No | Sleep after N minutes of inactivity |
| `Install-Agent.ps1` | 3, 6 | Yes | PC agent, its firewall rule and startup task |
| `Uninstall-Agent.ps1` | — | Yes | Removes the PC agent |
| `Install-DevTools.ps1` | 4 | No | Git, Arduino IDE/CLI, ESP32 package, libraries |
| `New-FirmwareConfig.ps1` | 5 | Yes, to read the agent token | `config.h` |
| `Install-Firmware.ps1` | 5 | No | Builds and uploads the firmware |

Steps that can't be scripted from Windows: BIOS settings, router DHCP reservations, creating the bot in @BotFather, and disabling Tailscale key expiry.

---

## If something fails

| Phase | Where to look |
|---|---|
| 1 — PC doesn't wake | [Runbook 01 troubleshooting](01-pc-setup-bios-and-windows.md#troubleshooting) |
| 2 — Can't connect remotely | [Runbook 04 troubleshooting](04-remote-access-tailscale.md#troubleshooting) |
| 3 — Agent install/test fails | [Runbook 05 troubleshooting](05-pc-agent.md#troubleshooting) |
| 4 — Tool install, compile or upload errors | [Runbook 02 troubleshooting](02-development-environment.md#troubleshooting) |
| 5–6 — Bot silent, Wi-Fi, status wrong | [Runbook 03 troubleshooting](03-telegram-bot-flash-and-deploy.md#troubleshooting) |
