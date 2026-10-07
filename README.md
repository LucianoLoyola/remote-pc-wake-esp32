# remote-pc-wake-esp32

**Turn on your PC from anywhere with a cheap ESP32 and a Telegram bot, then control it remotely over Tailscale.**

No port forwarding, no public IP, no always-on PC. It works behind CGNAT.

```
                        ┌───────────── your home network ─────────────┐
 📱 Phone ── /wake ──►  Telegram  ◄── polls ── ESP32 ── magic packet ──► 🖥️ PC powers on
                                                                         │
 📱 Phone / 💻 Laptop ════════ Tailscale (encrypted) ════════════════════► Remote Desktop
                        └─────────────────────────────────────────────┘
```

## Why

- **Your main PC doesn't need to stay on 24/7.** The ESP32 does the waiting at about 0.2–0.3 W (80 MHz CPU, Wi-Fi modem sleep, configurable polling interval).
- **No inbound connections.** The ESP32 polls Telegram over HTTPS, and Tailscale punches through NAT/CGNAT. Nothing on your network is exposed to the internet.
- **Your PC isn't a VPN gateway.** Tailscale runs as a regular node: only the PC itself is reachable, not the rest of your LAN.
- **Cheap.** An ESP32 board costs a few dollars, and you may already have one in a drawer.

## How it works

1. You send `/wake` to your private Telegram bot.
2. The ESP32, sitting next to your router, receives the command and broadcasts a [Wake-on-LAN](https://en.wikipedia.org/wiki/Wake-on-LAN) magic packet on your LAN.
3. The PC's network card, which stays powered while the PC is off, recognizes the packet and powers the PC on.
4. The ESP32 watches for the PC to come online and tells you when it's ready.
5. You connect with Remote Desktop (or RustDesk/Parsec) over [Tailscale](https://tailscale.com).

## Bot commands

| Command | Action |
|---|---|
| `/wake` | Send the magic packet and report when the PC is online |
| `/status` | Check whether the PC is on |
| `/help` | List commands |

Only your Telegram user ID is allowed to send commands.

## Requirements

- An **ESP32** board (classic ESP32 DevKit / WROOM-32, or S2/S3/C3) and a USB cable with data lines
- A **PC connected by Ethernet** whose motherboard supports Wake-on-LAN (almost all desktop boards do)
- **Windows 10/11.** Pro, Enterprise or Education for the built-in Remote Desktop host; on Home, use RustDesk/Parsec/Chrome Remote Desktop.
- A **2.4 GHz Wi-Fi** network on the same LAN as the PC
- A **Telegram** account and a free **Tailscale** account

## Setup

Follow the runbooks in order:

| # | Runbook | What you'll do |
|---|---|---|
| 01 | [PC setup: BIOS/UEFI and Windows](docs/01-pc-setup-bios-and-windows.md) | Enable Wake-on-LAN, disable Fast Startup, reserve an IP, install Tailscale, enable Remote Desktop |
| 02 | [Development environment](docs/02-development-environment.md) | Install Arduino IDE, the ESP32 board package, drivers and libraries |
| 03 | [Telegram bot, flashing and deployment](docs/03-telegram-bot-flash-and-deploy.md) | Create the bot, configure and upload the firmware, install the ESP32 next to your router |

**Quick start** for people who've done this before:

```powershell
git clone https://github.com/<owner>/remote-pc-wake-esp32.git
cd remote-pc-wake-esp32\firmware\remote-pc-wake
Copy-Item config.example.h config.h   # then edit config.h
arduino-cli compile --fqbn esp32:esp32:esp32 .
arduino-cli upload  --fqbn esp32:esp32:esp32 -p COM3 .
```

## Repository layout

```
├── docs/
│   ├── 01-pc-setup-bios-and-windows.md
│   ├── 02-development-environment.md
│   └── 03-telegram-bot-flash-and-deploy.md
├── firmware/
│   └── remote-pc-wake/
│       ├── remote-pc-wake.ino     # ESP32 firmware
│       └── config.example.h       # copy to config.h (git-ignored)
└── tools/
    └── Send-MagicPacket.ps1       # test WoL from another Windows PC
```

## Security notes

- **Secrets stay local.** `config.h` (Wi-Fi password, bot token) is git-ignored. Never commit it.
- **Single authorized user.** The bot ignores everyone except `ALLOWED_CHAT_ID`.
- **No stale commands.** Messages sent while the ESP32 was offline are discarded on boot, so a power outage can't trigger an unexpected wake-up.
- **TLS verification.** The ESP32 validates Telegram's certificate.
- **Never expose Remote Desktop (port 3389) to the internet.** Always connect through Tailscale.
- The worst an attacker with your bot token can do is turn your PC on. They still need your Windows credentials and access to your Tailscale network to get in. If the token leaks, revoke it in @BotFather anyway.

## Roadmap / ideas

Contributions are welcome. Some ideas:

- [ ] Support for Ethernet ESP32 boards (WT32-ETH01, Olimex ESP32-POE)
- [ ] Wake multiple PCs (`/wake desktop`, `/wake nas`)
- [ ] Multiple authorized users
- [ ] Wi-Fi provisioning portal (configure without recompiling)
- [ ] OTA firmware updates
- [ ] Relay output for a hard reset / power button press
- [ ] Linux and macOS guides for the target PC

## Contributing

1. Fork the repository and create a branch (`git checkout -b feature/my-idea`).
2. Keep secrets out of commits: never add `config.h`.
3. Test on real hardware and say which board and PC you used in the pull request.
4. Open a pull request with a clear description.

Bug reports with your board model, motherboard and Serial Monitor output are very helpful.

## License

[MIT](LICENSE)
