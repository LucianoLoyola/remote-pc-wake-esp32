# Runbook 03 — Telegram bot, flashing and deployment

This runbook creates the Telegram bot, configures and uploads the firmware, and installs the ESP32 next to your router.

**Prerequisites:**

- [Runbook 01](01-pc-setup-bios-and-windows.md) completed. You have the PC's **MAC address** and **fixed IP**, and local WoL works.
- [Runbook 02](02-development-environment.md) completed. The firmware compiles.

**Estimated time:** 15 minutes.

---

## Step 1 — Create the Telegram bot

1. In Telegram, open a chat with **[@BotFather](https://t.me/BotFather)** (check the blue verified badge).
2. Send `/newbot`.
3. Choose a display name (e.g. `My PC Waker`) and a username ending in `bot` (e.g. `my_pc_waker_bot`).
4. BotFather replies with a **token** like `123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ`.

> The token gives full control of the bot. Don't share it or commit it to Git. If it leaks, send `/revoke` to BotFather to get a new one.

## Step 2 — Get your Telegram user ID

**Automatic:** skip this step. `New-FirmwareConfig.ps1` (Step 4) detects your ID when you send a message to your bot.

**Manual:**

1. Open a chat with **[@userinfobot](https://t.me/userinfobot)** and send any message.
2. It replies with your numeric **Id** (e.g. `123456789`).

The firmware **only obeys this ID**. Anyone else who finds the bot gets "Not authorized."

## Step 3 — Start a chat with your bot

Search for your bot's username in Telegram, open the chat and press **Start**. A bot can't message you until you've done this.

---

## Step 4 — Configure the firmware

### Automatic

Run it **on the target PC**, in an **elevated** PowerShell window, from the repository folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\New-FirmwareConfig.ps1
```

The script creates `firmware/remote-pc-wake/config.h` and fills it in:

| Value | How |
|---|---|
| PC MAC and IP | Detected from this PC's Ethernet adapter |
| Agent token | Read from the installed agent ([Runbook 05](05-pc-agent.md)), if any |
| Telegram ID | Detected: the script asks you to send any message to your bot |
| Wi-Fi name and password, bot token, web UI password | Asked (the Wi-Fi name is suggested if the PC is on Wi-Fi) |

You can also pass values as parameters (`-WifiSsid`, `-BotToken`, `-ChatId`, `-PcMac`, `-PcIp`, `-AgentToken`). Passwords are always asked for securely, never typed on the command line. If `config.h` already exists, the script keeps its values and only changes what you pass, so you can run it again to change a single setting:

| To change | Run with |
|---|---|
| Wi-Fi network | `-WifiSsid "NewNetwork"` (asks for its password) |
| Bot token | `-BotToken "123:ABC..."` |
| Web UI password | `-ChangeWebPassword` (asks for the new one) |
| Disable the web UI | `-DisableWebUi` |
| Fixed IP for the ESP32 (router can't reserve one) | `-Esp32StaticIp 192.168.1.210` |
| Back to automatic IP for the ESP32 | `-Esp32UseDhcp` |

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\New-FirmwareConfig.ps1 -WifiSsid "NewNetwork"
```

> Running it on a different PC than the one you want to wake? Pass `-PcMac` and `-PcIp` with the target PC's values.

The settings in the tables below keep their defaults. Edit `config.h` by hand to change them.

### Manual

1. In `firmware/remote-pc-wake/`, copy `config.example.h` to `config.h` if you haven't already.
2. Edit `config.h`:

| Setting | Value | Where it comes from |
|---|---|---|
| `WIFI_SSID` / `WIFI_PASSWORD` | Your Wi-Fi network | **2.4 GHz** network; the ESP32 doesn't support 5 GHz |
| `BOT_TOKEN` | Bot token | Step 1 |
| `ALLOWED_CHAT_ID` | Your numeric ID | Step 2 |
| `PC_MAC` | PC's Ethernet MAC | Runbook 01, B1 |
| `PC_IP_ADDRESS` | PC's fixed IP | Runbook 01, B4 |
| `PC_CHECK_PORT` | `3389` if you use Remote Desktop, `445` otherwise | Must be a port the PC answers on while it's on |

**Power-saving settings** (the defaults are fine for most people):

| Setting | Default | Notes |
|---|---|---|
| `POLL_INTERVAL_SECONDS` | `15` | How often the ESP32 checks Telegram. `/wake` reacts within this time. Raise it to save more power. |
| `CPU_FREQUENCY_MHZ` | `80` | Lowest clock that supports Wi-Fi. |
| `WIFI_TX_POWER` | `WIFI_POWER_11dBm` | Low transmit power, since the board sits next to the router. Raise it if Wi-Fi drops. |

**Optional features** (you can enable them later and re-flash):

| Setting | Default | Notes |
|---|---|---|
| `AGENT_TOKEN` / `AGENT_PORT` | empty / `8765` | Enables shutdown, restart, sleep, lock and PC stats. The agent installer prints both values ([Runbook 05](05-pc-agent.md)). Leave the token empty if you haven't installed the agent yet. |
| `WEB_USERNAME` / `WEB_PASSWORD` | `admin` / empty | Web UI on your home network. **Disabled while the password is empty.** |
| `ESP32_STATIC_IP` / `NETWORK_GATEWAY` / `NETWORK_SUBNET` / `NETWORK_DNS` | empty / empty / `255.255.255.0` / empty | Fixed IP for the ESP32, only if your router can't reserve one ([Runbook 05, Step 1](05-pc-agent.md#step-1--reserve-an-ip-for-the-esp32)). Empty = the router assigns it. `NETWORK_DNS` empty = use the router. |
| `MONITOR_INTERVAL_SECONDS` | `30` | How often the ESP32 checks whether the PC is on (for notifications) |
| `NOTIFY_UNEXPECTED_POWER_ON` / `_OFF` | `true` | Alert when the PC turns on or off without being asked through the bot |
| `NOTIFY_AGENT_WARNINGS` | `true` | Forward agent warnings (disk almost full, Windows Update restart pending) |

> `config.h` is listed in `.gitignore`, so it won't be committed.

## Step 5 — Upload the firmware

### Automatic

Connect the ESP32 by USB and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Firmware.ps1 -Monitor
```

It compiles the firmware, finds the ESP32's COM port, uploads, and opens the serial monitor (Ctrl+C to exit). You should see `Connected. IP: ...` and get the "ESP32 online" message in Telegram.

| Option | Use it when |
|---|---|
| `-Port COM3` | Several boards are connected, or the port isn't detected |
| `-Board esp32:esp32:esp32s3` | Your board isn't a classic ESP32 (S3, C3, S2...) |
| `-CompileOnly` | You only want to check that it builds |

If it gets stuck on *Connecting...*, hold the **BOOT** button on the board and run it again.

### Manual

1. Connect the ESP32 by USB.
2. In Arduino IDE, check **Tools → Board** (*ESP32 Dev Module*) and **Tools → Port**.
3. Click **Upload** (→ icon, `Ctrl + U`). If it gets stuck on *Connecting...*, hold the **BOOT** button until the upload starts.
4. Open **Tools → Serial Monitor**, set it to **115200 baud**, and press the **EN/RST** button on the board. You should see:
   ```
   Connecting to Wi-Fi....
   Connected. IP: 192.168.1.50
   ```
5. In Telegram, the bot sends **ESP32 online (v1.2.0). PC is off** (or on) with action buttons. If `WEB_PASSWORD` is set, the message also includes the web UI address.

## Step 6 — Test it

> Each reply can take up to `POLL_INTERVAL_SECONDS` (15 s by default) to arrive.

With the PC **on**:

- `/status` → `PC is on`
- `/wake` → `The PC is already on.`

Shut the PC down, wait about 30 seconds, then:

- `/status` → `PC is off`
- `/wake` → `Magic packet sent...` and then `The PC is online (took N s).`

> The "online" message appears when the PC answers on `PC_CHECK_PORT`, which only happens once Windows has finished booting.

---

## Step 7 — Permanent installation next to the router

- **Placement:** near the router, so the Wi-Fi signal is strong and the ESP32 is on the **same network** as the PC. Don't use a guest network.
- **Power:** either
  - the router's **USB port**, if it has one and keeps it powered (check: some routers turn the USB port off when nothing is mounted), or
  - any 5 V USB phone charger (1 A or more) plugged into a wall outlet. This is the most reliable option, and the one to use if your router has no USB port.

  Don't power it from the target PC's USB ports, a TV or a monitor: most of them cut power when the device is off, so the ESP32 would turn off exactly when you need it to wake the PC.

  The ESP32 doesn't have to sit next to the router; anywhere with good Wi-Fi signal works. If it's far from the router, raise `WIFI_TX_POWER`.
- **Enclosure (recommended):** a small plastic case protects the board from dust and short circuits. Don't use a metal box, because it blocks Wi-Fi.
- The firmware is tuned for 24/7 operation: the CPU runs at 80 MHz and idles between checks, Wi-Fi modem sleep is on, and transmit power is reduced. Typical consumption is about 0.2–0.3 W, and the board stays barely warm to the touch.
- Polling doesn't wear out the flash memory. Commands are handled entirely in RAM, and the firmware never writes to flash during normal operation.

> **Why Wi-Fi and not a cable?** Most ESP32 boards don't have an Ethernet port. The ESP32 talks to the PC through the router either way, so Wi-Fi works fine. Boards with Ethernet (WT32-ETH01, Olimex ESP32-POE) exist, but this firmware doesn't support them yet. Contributions are welcome!

---

## How it behaves in practice

| Situation | Behavior |
|---|---|
| ESP32 boots / recovers from a power outage | Sends "ESP32 online" (useful as a power-outage notification) |
| Messages sent while the ESP32 was offline | **Discarded**, so an old `/wake` never turns the PC on unexpectedly |
| Wi-Fi drops | Reconnects automatically; restarts itself if it can't connect within 30 s |
| PC doesn't come online within `WAKE_TIMEOUT_SECONDS` | Sends a warning |
| PC turns on or goes offline without being asked through the bot | Sends an alert (configurable) |

All commands, the web UI and every notification are described in [Daily use](usage.md).

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Serial Monitor stuck on `Connecting to Wi-Fi...` | Wrong SSID/password, or the network is 5 GHz only. Enable 2.4 GHz on the router. If the ESP32 is far from the router, raise `WIFI_TX_POWER`. |
| Bot replies slowly | Expected: replies take up to `POLL_INTERVAL_SECONDS`. Lower it if you prefer faster responses. |
| Connected to Wi-Fi but the bot never replies | Wrong `BOT_TOKEN`; you didn't press **Start** in the bot chat; or `ALLOWED_CHAT_ID` is wrong (the Serial Monitor shows `Ignored message from unauthorized chat ...` with your real ID). |
| `/wake` is sent but the PC doesn't power on | Repeat the local test in Runbook 01 (B5). If that fails too, it's a BIOS/Windows issue. Also confirm the ESP32 and the PC are on the same subnet. |
| `/status` always says "off" | The PC's firewall blocks `PC_CHECK_PORT`, Remote Desktop is disabled, or the IP changed (create the DHCP reservation). Try `PC_CHECK_PORT 445`. |
| PC wakes up but you can't connect remotely | Tailscale "Run unattended" or key expiry ([Runbook 04](04-remote-access-tailscale.md)). |
