# WakeDesk

*Your desktop, wherever you are.*

[![PowerShell analysis](https://github.com/wakedesk/wakedesk-esp32/actions/workflows/powershell-analysis.yml/badge.svg)](https://github.com/wakedesk/wakedesk-esp32/actions/workflows/powershell-analysis.yml)

**Turn your PC on and off from anywhere with a cheap ESP32 and a Telegram bot, get alerts about it, and control it remotely over Tailscale.**

No port forwarding, no public IP, no always-on PC. It works behind CGNAT.

> WakeDesk was previously called *remote-pc-wake-esp32*. Old links redirect here, and existing installations keep working: some technical names (like `remote-pc-wake.local`) keep the old name on purpose. See the [brand guide](docs/brand.md).

```
 Phone ── /wake ──► Telegram ◄── polls ── ESP32 ── magic packet ──► PC powers on
       ◄─ alerts ──                        │
                                           ├── shutdown / sleep / stats ──► PC agent
                                           └── web UI (home network only)

 Phone / Laptop ══════ Tailscale (encrypted) ══════► Remote Desktop to the PC
```

## Why

- **Your main PC doesn't need to stay on 24/7.** The ESP32 does the waiting at about 0.2–0.3 W (80 MHz CPU, Wi-Fi modem sleep, configurable polling interval).
- **No inbound connections.** The ESP32 polls Telegram over HTTPS, and Tailscale punches through NAT/CGNAT. Nothing on your network is exposed to the internet.
- **Your PC isn't a VPN gateway.** Tailscale runs as a regular node: only the PC itself is reachable, not the rest of your LAN.
- **Cheap.** An ESP32 board costs a few dollars, and you may already have one in a drawer.

## Features

- **Wake** the PC with Wake-on-LAN and get notified when it's ready
- **Shut down, restart, sleep or lock** it, now or on a schedule (with the PC agent)
- **Status**: CPU, RAM, disks, NVIDIA GPU, uptime, signed-in user
- **Alerts**: power outage recovery, PC turned on/off unexpectedly, PC agent down, disk almost full, Windows Update restart pending
- **Telegram buttons** for every action, from anywhere
- **Web UI** on your home network (`http://remote-pc-wake.local`)
- **Remote Desktop over Tailscale**, with a one-command setup script

## What you can do with it

- **Use your full desktop from anywhere** (laptop, tablet or phone) with Remote Desktop
- **Grab a file you left at home**, or send one to the PC with Taildrop
- **Use your PC's power from a weak laptop**: compile, render, run heavy software
- **Play your PC games remotely** with Parsec or Moonlight
- **Start a long task**, check on it later, and shut the PC down when it's done

## Bot commands

| Command | Action |
|---|---|
| `/wake` | Turn on the PC and report when it's online |
| `/status` | On/off, CPU, RAM, disks, GPU, uptime |
| `/shutdown [min]` | Shut down now (with confirmation) or in N minutes |
| `/restart [min]` | Restart now (with confirmation) or in N minutes |
| `/sleep` | Put the PC to sleep |
| `/lock` | Lock the PC's screen |
| `/cancel` | Cancel a scheduled shutdown/restart |
| `/menu` | Buttons for all actions |

Only your Telegram account can send commands. Power actions, stats and warnings need the [PC agent](docs/05-pc-agent.md); waking and on/off alerts work without it. See [Daily use](docs/usage.md) for the web UI and all notifications.

## Requirements

- An **ESP32** board (classic ESP32 DevKit / WROOM-32, or S2/S3/C3) and a USB cable with data lines
- A **PC connected by Ethernet** whose motherboard supports Wake-on-LAN (almost all desktop boards do)
- **Windows 10/11.** Pro, Enterprise or Education for the built-in Remote Desktop host; on Home, use RustDesk/Parsec/Chrome Remote Desktop.
- A **2.4 GHz Wi-Fi** network on the same LAN as the PC
- A **Telegram** account and a free **Tailscale** account

## Setup

**Start here: [Getting started — complete onboarding](docs/00-getting-started.md).** It walks through the whole process in the best order, with a checkpoint after each phase.

The detailed runbooks it links to:

| # | Runbook | What you'll do |
|---|---|---|
| 01 | [PC setup: BIOS/UEFI and Windows](docs/01-pc-setup-bios-and-windows.md) | Enable Wake-on-LAN, disable Fast Startup, fix the PC's IP (router reservation or script) |
| 02 | [Development environment](docs/02-development-environment.md) | Install Arduino IDE, the ESP32 board package, drivers and libraries |
| 03 | [Telegram bot, flashing and deployment](docs/03-telegram-bot-flash-and-deploy.md) | Create the bot, configure and upload the firmware, install the ESP32 next to your router |
| 04 | [Remote access: Tailscale and Remote Desktop](docs/04-remote-access-tailscale.md) | Reach and control the PC from anywhere. One script does most of it. |
| 05 | [PC agent](docs/05-pc-agent.md) | Enable shutdown, restart, sleep, lock, stats and warnings |

Then see **[Daily use](docs/usage.md)** for commands, the web UI and notifications.

Every Windows step is automated with a PowerShell script, and every runbook also documents the manual alternative. **Quick start** for people who've done this before. On the target PC, set the BIOS first, then run from an elevated PowerShell window in the repository folder:

```powershell
# Wake-on-LAN (then reserve the PC's IP in the router, or run Set-StaticIp.ps1 if it can't)
powershell -ExecutionPolicy Bypass -File .\scripts\Enable-WakeOnLan.ps1
# Tailscale + Remote Desktop
powershell -ExecutionPolicy Bypass -File .\scripts\Install-RemoteAccess.ps1 -RestrictRdpToTailscale
# PC agent
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Agent.ps1
# Your settings (asks for Wi-Fi, bot token...)
powershell -ExecutionPolicy Bypass -File .\scripts\New-FirmwareConfig.ps1
# ESP32 by USB: installs the released firmware and sends your settings (no Arduino needed)
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Firmware.ps1 -Monitor
```

The firmware is built and published by GitHub Actions on every release; it contains no personal data, and your settings are sent to the ESP32 over USB. To modify the firmware, see [Runbook 02](docs/02-development-environment.md).

See [all the scripts](docs/00-getting-started.md#all-the-scripts).

## Can I trust the scripts?

You shouldn't have to take our word for it, so the project makes the scripts easy to check:

- **Every change is documented.** The [Scripts reference](docs/scripts-reference.md) lists, for each script, every setting it changes, every internet address it contacts, and how to undo it. The same information is in each script's help: `Get-Help .\scripts\<script>.ps1 -Full`.
- **Automated analysis before and after every merge.** On every pull request to `main`, and again on `main` after the merge, GitHub checks every script with Microsoft's [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer). It also rejects code that downloads and runs other code, or that hides what it does. The results are public (badge at the top), and you can [run the same checks yourself](docs/scripts-reference.md#automated-analysis).
- **Plain code, no telemetry.** No obfuscation, no binaries, no hidden network access. Software is installed only through winget and the official Arduino/Espressif indexes.
- **Check before changing.** `Enable-WakeOnLan.ps1 -CheckOnly` reports the configuration without touching it.

## Repository layout

```
├── .github/
│   ├── ISSUE_TEMPLATE/            # bug report, hardware report and feature request forms
│   ├── pull_request_template.md
│   └── workflows/
│       ├── firmware.yml           # builds the firmware; attaches it to each release
│       └── powershell-analysis.yml  # script checks on pull requests to main and on main
├── agent/
│   └── RemotePcWakeAgent.ps1      # PC agent (runs as a startup task)
├── docs/
│   ├── 00-getting-started.md      # complete onboarding, start here
│   ├── 01-pc-setup-bios-and-windows.md
│   ├── 02-development-environment.md
│   ├── 03-telegram-bot-flash-and-deploy.md
│   ├── 04-remote-access-tailscale.md
│   ├── 05-pc-agent.md
│   ├── scripts-reference.md       # what each script changes, contacts, and how to undo it
│   ├── brand.md                   # name, colors and image guidelines
│   └── usage.md                   # commands, web UI, notifications
├── firmware/
│   └── remote-pc-wake/
│       ├── remote-pc-wake.ino     # ESP32 firmware
│       ├── settings.h             # settings stored on the ESP32, USB provisioning
│       ├── web_ui.h               # web UI page
│       └── config.example.h       # copy to config.h (git-ignored)
├── scripts/                       # one script per Windows configuration
│   ├── Enable-WakeOnLan.ps1       # network adapter + Fast Startup for Wake-on-LAN
│   ├── Install-RemoteAccess.ps1   # Tailscale + Remote Desktop
│   ├── Set-AutoSleep.ps1          # sleep after N minutes of inactivity
│   ├── Set-StaticIp.ps1           # fixed IP for the PC (routers without DHCP reservation)
│   ├── Install-Agent.ps1          # install/update the PC agent
│   ├── Uninstall-Agent.ps1
│   ├── Install-DevTools.ps1       # Arduino CLI/IDE, ESP32 package, libraries (only to build)
│   ├── New-FirmwareConfig.ps1     # create/update config.h
│   ├── Install-Firmware.ps1       # install the released firmware, send your settings
│   ├── Send-MagicPacket.ps1       # test WoL from another Windows PC
│   └── lib/Common.ps1             # shared helpers
├── tests/
│   └── Invoke-ScriptAnalysis.ps1  # syntax, forbidden patterns, PSScriptAnalyzer
├── PSScriptAnalyzerSettings.psd1  # analyzer rules (and the reason for each exclusion)
├── CONTRIBUTING.md                # development setup and project rules
├── CODE_OF_CONDUCT.md
└── SECURITY.md                    # how to report vulnerabilities, security model
```

## Security notes

- **Secrets stay local.** `config.h` (Wi-Fi password, bot token, agent token) is git-ignored. Never commit it.
- **Single authorized user.** The bot ignores everyone except `ALLOWED_CHAT_ID`. A leaked bot token would let someone read and intercept the bot's messages, so revoke it in @BotFather if that happens.
- **No stale commands.** Messages sent while the ESP32 was offline are discarded on boot, so a power outage can't trigger an unexpected wake-up.
- **TLS verification.** The ESP32 validates Telegram's certificate.
- **PC agent locked down.** It requires a random token, the firewall only admits the ESP32, and it can only run its fixed set of actions (no arbitrary commands). See [Runbook 05](docs/05-pc-agent.md#security-notes).
- **Web UI is LAN-only and password-protected**, and every action taken from it is reported in Telegram.
- **Never expose Remote Desktop (port 3389) or the agent (port 8765) to the internet.** Always connect through Tailscale.

## Roadmap / pending

Contributions are welcome (see [CONTRIBUTING.md](CONTRIBUTING.md)):

- [ ] **Multiple devices**: wake and control several PCs/NAS/consoles from one ESP32 (`/wake desktop`, `/wake nas`, a device picker in the web UI and buttons, per-device MAC/IP/agent token)
- [ ] Support for Ethernet ESP32 boards (WT32-ETH01, Olimex ESP32-POE)
- [ ] Multiple authorized Telegram users
- [ ] Wi-Fi provisioning portal (configure without recompiling)
- [ ] OTA firmware updates
- [ ] Scheduled wake-ups (e.g. weekdays at 8:00)
- [ ] Detect unexpected shutdowns (crash / power loss) from the Windows event log
- [ ] CPU temperature via LibreHardwareMonitor
- [ ] Linux and macOS agents and guides

## Contributing

Contributions are welcome: bug reports, **hardware reports** (does it work on your board, motherboard and router?), documentation and code. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development setup and the project rules.

- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security policy](SECURITY.md): report vulnerabilities privately, not as public issues.

## License

[MIT](LICENSE)
